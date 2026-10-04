part of 'notebook_storage.dart';

// 口令与信封管理面（O1 拆分自 notebook_storage.dart）：设密/改密/绑盘/USB 重置
// 的独占槽位内实现、区内读写原语与会话口令缓存/失败回滚。public API、@override、
// 字段与静态成员留在本体。行为零变化。

/// 口令/信封域私有助手（拆分自 notebook_storage.dart）。
extension _NotebookStoragePassword on NotebookStorage {

  Future<String> _encryptAndSaveLocked(
    Notebook notebook,
    String password,
    List<int>? usbKey,
  ) async {
    // 第一步合规（2026-08-16 专家审计最优先行动②）：加密笔记本不生成
    // 明文 searchSummary——"废除默认明文 searchSummary"。未来 K_note
    // 密钥层级落地后摘要可加密存储（解锁会话内搜索——安全）。
    final payloadJson = jsonEncode({
      'pages': notebook.pages.map((p) => p.toJson()).toList(),
    });
    // 队列内重读：拿到的必然是「此刻已落盘」的最新载荷。旧实现在队列外照抄
    // 内存快照的信封——重绕是数百毫秒级慢操作，窗口内的改密/绑盘会被
    // 「旧槽位组 + 新载荷」覆盖（旧密码复活 = 静默降密）。
    final existing =
        await _encryptedPayloadOnDiskInsideExclusive(notebook.id) ??
        notebook.encryptedPayload;
    if (existing != null &&
        EncryptionService.isDualProtectorEnvelope(existing)) {
      // v5 续写：密码解出 DEK → 复用槽位组，仅重生成 payload。
      final map = jsonDecode(existing) as Map<String, dynamic>;
      final dek = await NotebookStorage._encryption
          .unwrapPasswordSlotForRewrap(
            notebookId: notebook.id,
            encryptedJson: existing,
            password: password,
          );
      if (dek == null) {
        throw const FormatException('会话密码与当前信封不匹配');
      }
      final newPayload = await NotebookStorage._encryption.rewrapPayloadV5(
        notebookId: notebook.id,
        map: map,
        dek: dek,
        plaintext: payloadJson,
      );
      notebook.encryptedPayload = newPayload;
    } else {
      notebook.encryptedPayload = await NotebookStorage._encryption
          .encryptWithPasswordV5(
            notebookId: notebook.id,
            plaintext: payloadJson,
            password: password,
            usbKey: usbKey,
          );
    }
    notebook.encrypted = true;
    // 会话口令回滚纪律（对齐 StorageFilePasswordManager 的密封失败回滚）：
    // 先记失败前状态再缓存新口令，密封落盘失败（文件被删/保险库回锁）即回滚——
    // 磁盘信封未变时残留新口令会让后续 load+decrypt 抛 FormatException。
    final priorPassword = notebookPasswordFor(notebook.id);
    _cacheNotebookPassword(notebook.id, password);
    // 直接原子写入（toJson 中 encrypted 时 pages 序列化为空，仅存密文载荷）。
    // 注意：不能走 save()——save 对"加密且内存有明文页面"会抛 StateError
    // （这是编辑会话的守卫），而加密保存时内存本来就有明文页面。
    // 落盘用 [_writeNotebookInsideExclusive]（非排队原语）：本方法已持有
    // 该 id 的独占槽位，`_writeNotebook` 再挂 `_writeTails` 等于 await 自己
    // 所在的链 → 死锁（[:617] 同款纪律）。
    try {
      return await _writeNotebookInsideExclusive(notebook);
    } catch (_) {
      _rollbackSessionPassword(notebook.id, priorPassword);
      rethrow;
    }
  }


  /// 分页画布「读-改-写」的局部字段更新收口（P1 修复，本次）。
  ///
  /// 原实现是队列外的整本 `load → save`：load 取到的是打开那一刻的快照，
  /// 期间任何并发保存（编辑器自动保存、另一次改密）先落盘的新快照都会被
  /// 这份陈旧快照**整体覆盖**。这里把读→改→写收进同一 per-id 写尾队列槽位
  /// （[_runExclusive]），且只替换信封字段 `encrypted`/`encryptedPayload`，
  /// 其余字段一律取槽位内重读到的磁盘当前值。
  ///
  /// **本方法是「独占槽位内」原语**：调用方（设密/改密/绑盘/重置盘）自己
  /// 持有槽位，此处不再排队——`_runExclusive` 重入同一 id 等于 await 自己
  /// 所在的链 → 死锁。
  ///
  /// 落盘用 [_writeNotebookBytes]（非排队原语）：`_writeNotebook` 自己会挂到
  /// `_writeTails`，在独占槽位内再排队等于 await 自己所在的链 → 死锁；画布域
  /// 同场景用的是 `runDocExclusive` + `saveEncoded`（非队列原语）的同款纪律。
  Future<void> _patchEncryptedPayloadInsideExclusive(
    String id,
    String newPayload,
  ) async {
    // 先取密钥再读文件：读到的必须是自己即将写回的那一份（顺序不能颠倒）。
    final key = await _currentKey();
    final file = File(await _pathFor(id));
    if (!file.existsSync()) throw StateError('该分页画布已不存在：$id');
    final onDisk = await file.readAsBytes();
    final clear = key == null || !VaultFileCodec.isEncrypted(onDisk)
        ? onDisk
        : await VaultFileCodec.decrypt(
            onDisk,
            key,
            aadContext: 'nb:$id',
          );
    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('笔记本数据损坏');
      }
      root = decoded;
    } on FormatException {
      throw const FormatException('笔记本数据损坏');
    }
    root['encrypted'] = true;
    root['encryptedPayload'] = newPayload;
    final data = utf8.encode(jsonEncode(root));
    await _writeNotebookBytes(
      file,
      key == null
          ? data
          : await VaultFileCodec.encrypt(
              data,
              key,
              aadContext: 'nb:$id',
            ),
    );
    onWrite?.call();
  }


  /// 独占槽位内重读磁盘当前的加密载荷（非陈旧快照）。
  ///
  /// **不走 [load]**：它会顺带 `_enqueueRawRewrite` 懒迁移——迁移捕获的正是
  /// 本次读到的明文，排在调用方那条独占链之后执行，会用「读时的整本明文」
  /// 反超随后写回的新载荷（口径同
  /// `test/storage_staleness_guards_test.dart` 锁的画布懒迁移陈旧快照）。
  /// 文件不存在返回 null（新建笔记本首存场景）；保险库锁定
  /// （有信封却无密钥）抛 [VaultFileLockException]，与 [load] 同语义。
  Future<String?> _encryptedPayloadOnDiskInsideExclusive(String id) async {
    final file = File(await _pathFor(id));
    if (!file.existsSync()) return null;
    final key = await _currentKey();
    final onDisk = await file.readAsBytes();
    if (key == null && VaultFileCodec.isEncrypted(onDisk)) {
      throw const VaultFileLockException();
    }
    final clear = key == null
        ? onDisk
        : await VaultFileCodec.decrypt(
            onDisk,
            key,
            aadContext: 'nb:$id',
          );
    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('笔记本数据损坏');
      }
      root = decoded;
    } on FormatException {
      throw const FormatException('笔记本数据损坏');
    }
    final payload = root['encryptedPayload'];
    return payload is String && payload.isNotEmpty ? payload : null;
  }


  /// 独占槽位内的整本落盘原语：编码/密封口径与 `_writeNotebook` 一致，
  /// 但**不挂 `_writeTails`**——调用方已持有该 id 的槽位，再排队就是 await
  /// 自己所在的链 → 死锁（见 [_patchEncryptedPayloadInsideExclusive] 头注释）。
  Future<String> _writeNotebookInsideExclusive(Notebook notebook) async {
    if (!NotebookStorage.isValidId(notebook.id)) {
      throw ArgumentError.value(notebook.id, 'notebook.id', '笔记本 ID 不合法');
    }
    await _ensureNotebooksDir();
    final finalPath = await _pathFor(notebook.id);
    final data = await NotebookStorage._encodeSnapshotAsync(notebook.toJson());
    final key = await _currentKey();
    await _writeNotebookBytes(
      File(finalPath),
      key == null
          ? data
          : await VaultFileCodec.encrypt(
              data,
              key,
              aadContext: 'nb:${notebook.id}',
            ),
    );
    onWrite?.call();
    return finalPath;
  }


  Future<void> _changeNotebookPasswordLocked(
    String id,
    String oldPassword,
    String newPassword, {
    List<int>? usbKey,
  }) async {
    // 队列内重读：拿到的必然是「此刻已落盘」的最新载荷（非陈旧快照）。
    final payload = await _encryptedPayloadOnDiskInsideExclusive(id);
    if (payload == null) {
      throw StateError('该分页画布未设置文件密码');
    }
    String newPayload;
    if (EncryptionService.isDualProtectorEnvelope(payload)) {
      newPayload = await NotebookStorage._encryption.changeNotebookPasswordV5(
        notebookId: id,
        encryptedJson: payload,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      if (usbKey != null && !EncryptionService.hasUsbSlotV5(payload)) {
        newPayload = await NotebookStorage._encryption.bindNotebookUsbSlotV5(
          notebookId: id,
          encryptedJson: newPayload,
          password: newPassword,
          usbKey: usbKey,
        );
      }
    } else {
      // 旧格式升级：解密出明文 → v5 重加密（顺带完成格式升级）。
      final clear = await NotebookStorage._encryption.decryptWithPasswordAad(
        notebookId: id,
        encryptedJson: payload,
        password: oldPassword,
      );
      newPayload = await NotebookStorage._encryption.encryptWithPasswordV5(
        notebookId: id,
        plaintext: clear,
        password: newPassword,
        usbKey: usbKey,
      );
    }
    // 会话口令回滚纪律（见 _rollbackSessionPassword）。
    final priorPassword = notebookPasswordFor(id);
    _cacheNotebookPassword(id, newPassword);
    try {
      await _patchEncryptedPayloadInsideExclusive(id, newPayload);
    } catch (_) {
      _rollbackSessionPassword(id, priorPassword);
      rethrow;
    }
  }


  Future<void> _bindNotebookUsbSlotLocked(
    String id,
    String password,
    List<int> usbKey,
  ) async {
    // 队列内重读：拿到的必然是「此刻已落盘」的最新载荷（非陈旧快照）。
    final payload = await _encryptedPayloadOnDiskInsideExclusive(id);
    if (payload == null) {
      throw StateError('该分页画布未设置文件密码');
    }
    String newPayload;
    if (EncryptionService.isDualProtectorEnvelope(payload)) {
      newPayload = await NotebookStorage._encryption.bindNotebookUsbSlotV5(
        notebookId: id,
        encryptedJson: payload,
        password: password,
        usbKey: usbKey,
      );
    } else {
      final clear = await NotebookStorage._encryption.decryptWithPasswordAad(
        notebookId: id,
        encryptedJson: payload,
        password: password,
      );
      newPayload = await NotebookStorage._encryption.encryptWithPasswordV5(
        notebookId: id,
        plaintext: clear,
        password: password,
        usbKey: usbKey,
      );
    }
    await _patchEncryptedPayloadInsideExclusive(id, newPayload);
  }


  Future<bool> _resetNotebookPasswordWithUsbLocked(
    String id,
    List<int> usbKey,
    String newPassword,
  ) async {
    // 队列内重读：拿到的必然是「此刻已落盘」的最新载荷（非陈旧快照）。
    final payload = await _encryptedPayloadOnDiskInsideExclusive(id);
    if (payload == null) return false;
    final newPayload = await NotebookStorage._encryption
        .resetNotebookPasswordWithUsbV5(
          notebookId: id,
          encryptedJson: payload,
          usbKey: usbKey,
          newPassword: newPassword,
        );
    if (newPayload == null) return false;
    // 会话口令回滚纪律（见 _rollbackSessionPassword）。
    final priorPassword = notebookPasswordFor(id);
    _cacheNotebookPassword(id, newPassword);
    try {
      await _patchEncryptedPayloadInsideExclusive(id, newPayload);
    } catch (_) {
      _rollbackSessionPassword(id, priorPassword);
      rethrow;
    }
    return true;
  }


  void _cacheNotebookPassword(String id, String password) {
    _sessionNotebookPasswords[id] = password;
  }


  /// 把会话口令回滚到「密封/落盘失败之前」的状态（对齐
  /// StorageFilePasswordManager 的密封失败回滚纪律）：失败前无口令 → forget，
  /// 有旧口令 → 恢复旧值。落盘失败时磁盘信封未变，若残留新口令则下一次
  /// load+decrypt 会抛 FormatException——选 fail-closed（宁可重新问一次口令），
  /// 不残留与磁盘错配的口令导致后续写回明文语义错乱。
  void _rollbackSessionPassword(String id, String? prior) {
    if (prior == null) {
      forgetNotebookPassword(id);
    } else {
      _cacheNotebookPassword(id, prior);
    }
  }
}
