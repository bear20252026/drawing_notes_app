/// 块文档存储门面——文件密码域（L-03 拆分，行为零变化）。
///
/// v5 双保护器设密/验证/改密/重置盘/移除，共享主库的会话 DEK 缓存
/// 与写链，通过 part 同库访问。
///
/// P0 竞态收口（审计 2026-10-03）：**改密/绑盘/重置/移密的「读信封 →
/// Argon2id 重绕 → 写回」三步必须整体在同 id 的独占写队列内执行**。
/// 重绕是数百毫秒级的慢操作，旧实现在队列外读信封，期间编辑器自动
/// 保存落盘的新正文会被「旧正文 + 新槽位」覆盖，而 UI 仍提示成功。
/// 口径对齐 StorageFilePasswordManager（E-17 同步注释）与其
/// `_readCurrentRaw` 在队列内重读最新已落盘文件的既有先例——
/// 见 `storage_file_password_manager.dart` 的 `setFilePassword`。

part of 'note_block_doc_store.dart';

extension NoteBlockDocStorePasswords on NoteBlockDocStore {
  // ==== 文件密码管理 API（N2，与 NotebookStorage 同口径） ====

  /// 启用密码保护并保存：整份文档 JSON 作为 v5 载荷加密，明文不落盘。
  ///
  /// [usbKey] 为重置密码盘钥匙（可选——设密时当场插盘绑定）。
  /// 成功后 DEK 入会话缓存（可直接编辑续写）。
  Future<void> encryptAndSave(
    NoteBlockDoc doc,
    String password, {
    List<int>? usbKey,
  }) {
    // P1 fail-closed（空密码收口第三层）：空串绝不封成「已加密」。
    if (password.isEmpty) throw ArgumentError('密码不能为空');
    return _enqueue(doc.id, () => _encryptAndSaveLocked(doc, password, usbKey));
  }

  Future<void> _encryptAndSaveLocked(
    NoteBlockDoc doc,
    String password,
    List<int>? usbKey,
  ) async {
    if (!NoteBlockDocStore.isValidId(doc.id)) {
      throw ArgumentError.value(doc.id, 'doc.id', '文档 ID 不合法');
    }
    await _ensureDir();
    final plaintext = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(doc.toJson()),
    );
    final sealed = await NoteBlockDocStore._encryption
        .encryptBlockDocPasswordV5(
          docId: doc.id,
          plaintext: utf8.decode(plaintext),
          password: password,
          usbKey: usbKey,
        );
    await _writeFileAtomic(doc.id, utf8.encode(sealed));
    // 缓存会话 DEK（unwrap 一次 PBKDF2，之后续写零重派生）。
    final dek = await NoteBlockDocStore._encryption
        .unwrapBlockDocPasswordSlotForRewrap(
          docId: doc.id,
          encryptedJson: sealed,
          password: password,
        );
    if (dek != null) _sessionDeks[doc.id] = dek;
  }

  /// 校验笔记文件密码（正确即 DEK 入会话缓存——解锁一次本会话免重复输入）。
  Future<bool> verifyBlockDocPassword(String id, String password) async {
    final envelope = await _readEnvelopeJson(id);
    if (envelope == null) return false;
    try {
      await NoteBlockDocStore._encryption.decryptBlockDocPassword(
        docId: id,
        encryptedJson: envelope,
        password: password,
      );
    } on FormatException {
      return false;
    }
    final dek = await NoteBlockDocStore._encryption
        .unwrapBlockDocPasswordSlotForRewrap(
          docId: id,
          encryptedJson: envelope,
          password: password,
        );
    if (dek != null) _sessionDeks[id] = dek;
    _headerCache = null; // 解锁后列表从「加密笔记」占位刷新为真实标题
    return true;
  }

  /// 修改笔记文件密码：仅重绕密码槽（payload 与重置盘槽位原样保留）。
  /// 旧密码错误抛 [FormatException]。成功后 DEK 已更新缓存。
  ///
  /// 读信封 + 重绕 + 写回整体在写队列内（见本文件头 P0 竞态收口）。
  Future<void> changeBlockDocPassword(
    String id,
    String oldPassword,
    String newPassword, {
    List<int>? usbKey,
  }) {
    // P1 fail-closed：新密码空串直接拒绝（旧密码可为历史遗留空值，
    // 仍须允许其通过校验以解密密文，故只拦新密码）。
    if (newPassword.isEmpty) throw ArgumentError('密码不能为空');
    return _enqueue(
      id,
      () => _changeBlockDocPasswordLocked(
        id,
        oldPassword,
        newPassword,
        usbKey: usbKey,
      ),
    );
  }

  Future<void> _changeBlockDocPasswordLocked(
    String id,
    String oldPassword,
    String newPassword, {
    List<int>? usbKey,
  }) async {
    // 队列内重读：拿到的必然是「此刻已落盘」的最新信封。
    final envelope = await _readEnvelopeJson(id);
    if (envelope == null) {
      throw StateError('该笔记未设置文件密码');
    }
    var newEnvelope = await NoteBlockDocStore._encryption
        .changeBlockDocPasswordV5(
          docId: id,
          encryptedJson: envelope,
          oldPassword: oldPassword,
          newPassword: newPassword,
        );
    if (usbKey != null && !EncryptionService.hasUsbSlotV5(newEnvelope)) {
      newEnvelope = await NoteBlockDocStore._encryption.bindBlockDocUsbSlotV5(
        docId: id,
        encryptedJson: newEnvelope,
        password: newPassword,
        usbKey: usbKey,
      );
    }
    await _writeFileAtomic(id, utf8.encode(newEnvelope));
    final dek = await NoteBlockDocStore._encryption
        .unwrapBlockDocPasswordSlotForRewrap(
          docId: id,
          encryptedJson: newEnvelope,
          password: newPassword,
        );
    if (dek != null) _sessionDeks[id] = dek;
  }

  /// 该笔记是否已绑定重置密码盘（v5 且含 USB 槽位）。
  Future<bool> hasBlockDocUsbSlot(String id) async {
    final envelope = await _readEnvelopeJson(id);
    if (envelope == null) return false;
    return EncryptionService.hasUsbSlotV5(envelope);
  }

  /// 事后绑定重置密码盘。密码错误/已绑定抛 [FormatException]。
  ///
  /// 读信封 + 重绕 + 写回整体在写队列内（见本文件头 P0 竞态收口）。
  Future<void> bindBlockDocUsbSlot(
    String id,
    String password,
    List<int> usbKey,
  ) {
    return _enqueue(id, () => _bindBlockDocUsbSlotLocked(id, password, usbKey));
  }

  Future<void> _bindBlockDocUsbSlotLocked(
    String id,
    String password,
    List<int> usbKey,
  ) async {
    final envelope = await _readEnvelopeJson(id);
    if (envelope == null) {
      throw StateError('该笔记未设置文件密码');
    }
    final newEnvelope = await NoteBlockDocStore._encryption
        .bindBlockDocUsbSlotV5(
          docId: id,
          encryptedJson: envelope,
          password: password,
          usbKey: usbKey,
        );
    await _writeFileAtomic(id, utf8.encode(newEnvelope));
  }

  /// 用重置密码盘重置笔记文件密码。
  ///
  /// 重置 = U 盘钥匙解出 DEK → 新盐重绕密码槽，payload 密文不动。
  /// 成功后 DEK 已缓存（可直接解锁）。返回 false = 未绑定/盘不匹配/非 v5。
  ///
  /// 读信封 + 重绕 + 写回整体在写队列内（见本文件头 P0 竞态收口）。
  Future<bool> resetBlockDocPasswordWithUsb(
    String id,
    List<int> usbKey,
    String newPassword,
  ) {
    // P1 fail-closed：重置即设新密码，空串拒绝。
    if (newPassword.isEmpty) throw ArgumentError('密码不能为空');
    return _enqueue(
      id,
      () => _resetBlockDocPasswordWithUsbLocked(id, usbKey, newPassword),
    );
  }

  Future<bool> _resetBlockDocPasswordWithUsbLocked(
    String id,
    List<int> usbKey,
    String newPassword,
  ) async {
    final envelope = await _readEnvelopeJson(id);
    if (envelope == null) return false;
    final newEnvelope = await NoteBlockDocStore._encryption
        .resetBlockDocPasswordWithUsbV5(
          docId: id,
          encryptedJson: envelope,
          usbKey: usbKey,
          newPassword: newPassword,
        );
    if (newEnvelope == null) return false;
    await _writeFileAtomic(id, utf8.encode(newEnvelope));
    final dek = await NoteBlockDocStore._encryption
        .unwrapBlockDocPasswordSlotForRewrap(
          docId: id,
          encryptedJson: newEnvelope,
          password: newPassword,
        );
    if (dek != null) _sessionDeks[id] = dek;
    _headerCache = null;
    return true;
  }

  /// 移除文件密码：密码解出整份明文 → 回到普通存储（有主密钥则回封
  /// 主密钥信封——绝不落裸明文）。密码错误抛 [FormatException]。
  ///
  /// 解密 + 回封 + 写回整体在写队列内（见本文件头 P0 竞态收口）。
  Future<void> removeBlockDocPassword(String id, String password) {
    return _enqueue(id, () => _removeBlockDocPasswordLocked(id, password));
  }

  Future<void> _removeBlockDocPasswordLocked(
    String id,
    String password,
  ) async {
    final envelope = await _readEnvelopeJson(id);
    if (envelope == null) {
      throw StateError('该笔记未设置文件密码');
    }
    final clear = await NoteBlockDocStore._encryption.decryptBlockDocPassword(
      docId: id,
      encryptedJson: envelope,
      password: password,
    );
    var data = utf8.encode(clear);
    final key = await _currentKey();
    if (key != null) {
      data = await VaultFileCodec.encrypt(data, key, aadContext: 'block:$id');
    }
    await _writeFileAtomic(id, data);
    forgetBlockDocPassword(id);
    _headerCache = null;
  }
}
