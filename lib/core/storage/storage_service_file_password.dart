// storage_service.dart 的 part：单文件密码管理 API（批次②/N2：文件密码 + U 盘槽位）。
// 与主文件同 library，extension 可直接访问 StorageService 私有成员。
part of 'storage_service.dart';

extension StorageServiceFilePassword on StorageService {
  // ---- 单文件密码管理 API（批次②：画作级独立密码） ----

  /// 读取当前正式文件（缺失回退 .bak）；两者都不存在返回 null。
  Future<Uint8List?> _readCurrentRaw(String id) async {
    await _ensureDocumentsDir();
    final file = File(_pathFor(id));
    final bak = File('${file.path}.bak');
    if (await file.exists()) return file.readAsBytes();
    if (await bak.exists()) return bak.readAsBytes();
    return null;
  }

  /// 该文档是否受独立文件密码保护（读文件头版本字节，不解密）。
  Future<bool> isFilePasswordProtected(String id) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null) return false;
    return VaultFileCodec.isPasswordEnvelope(raw);
  }

  /// 校验文件密码；正确则缓存进会话（解锁一次本会话免重复输入）。
  /// v3 信封同时缓存 DEK / USB 槽位（续写续用）。
  Future<bool> verifyFilePassword(String id, String password) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null || !VaultFileCodec.isPasswordEnvelope(raw)) return false;
    try {
      if (VaultFileCodec.isV3Envelope(raw)) {
        final unlock = await VaultFileCodec.unlockWithPasswordV3(
          raw,
          password,
          aadContext: 'doc:$id',
        );
        _cacheV3Material(id, unlock);
      } else {
        await VaultFileCodec.decryptWithPassword(
          raw,
          password,
          aadContext: 'doc:$id',
        );
      }
    } on VaultFileException {
      return false;
    }
    cacheFilePassword(id, password);
    return true;
  }

  /// 该文档是否绑定了重置密码盘（v3 信封且含 USB 槽位；读头部不解密）。
  Future<bool> hasFileUsbSlot(String id) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null) return false;
    return VaultFileCodec.hasUsbSlotV3(raw);
  }

  /// 为未设密文档设置独立文件密码（v3 双保护器信封重封 + 删除缩略图）。
  ///
  /// 前提：文档当前为明文或 v1 主密钥信封（应用锁已解锁时可读）。
  /// 已设密时抛 [StateError]（走 [changeFilePassword]）。
  /// [resetDiskKey] 非空时同时嵌入重置盘槽位（设密时插盘绑定——LUKS
  /// 同款：U 盘钥匙不在设备上，错过本次可事后走 [bindFileUsbSlot]）。
  Future<void> setFilePassword(
    String id,
    String password, {
    List<int>? resetDiskKey,
  }) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null) {
      throw StateError('文档不存在');
    }
    if (VaultFileCodec.isPasswordEnvelope(raw)) {
      throw StateError('该文档已设置文件密码，请使用修改密码');
    }
    // 取明文：v1 信封需主密钥（锁定时 fail-closed）。
    Uint8List plain;
    if (VaultFileCodec.isEncrypted(raw)) {
      final key = await _currentKey();
      if (key == null) throw const VaultFileLockException();
      plain = await VaultFileCodec.decrypt(raw, key, aadContext: 'doc:$id');
    } else {
      plain = raw;
    }
    // DEK 由会话生成并缓存（续写复用，重置盘槽位跨保存有效的前提）。
    final dek = VaultFileCodec.generateDek();
    final usbWrapped = resetDiskKey == null
        ? null
        : await VaultFileCodec.wrapUsbSlotV3(
            usbKey: resetDiskKey,
            dek: dek,
            aadContext: 'doc:$id',
          );
    cacheFilePassword(id, password);
    _sessionDocDeks[id] = dek;
    if (usbWrapped != null) {
      _sessionFileUsbWrapped[id] = usbWrapped;
    } else {
      _sessionFileUsbWrapped.remove(id);
    }
    try {
      final sealed = await VaultFileCodec.encryptWithPasswordV3(
        plain,
        password,
        aadContext: 'doc:$id',
        dek: dek,
        usbWrapped: usbWrapped,
      );
      await _writeSealedBytes(id, sealed);
    } catch (_) {
      forgetFilePassword(id); // 密封失败不残留会话密码（防后续写回明文语义错乱）
      rethrow;
    }
    await _deleteThumbnail(id);
    onWrite?.call();
  }

  /// 修改文件密码（验证旧密码 → 重封）。旧密码错误抛 [VaultFileException]。
  ///
  /// N4 批 2：v2 旧文件自动升级为 v3（引入 DEK，暂无重置盘槽位——可
  /// 事后绑定）；v3 文件 DEK 与重置盘槽位原样保留（改密≠换钥匙）。
  Future<void> changeFilePassword(
    String id,
    String oldPassword,
    String newPassword,
  ) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null || !VaultFileCodec.isPasswordEnvelope(raw)) {
      throw StateError('该文档未设置文件密码');
    }
    if (VaultFileCodec.isV3Envelope(raw)) {
      final unlock = await VaultFileCodec.unlockWithPasswordV3(
        raw,
        oldPassword,
        aadContext: 'doc:$id',
      ); // 旧密码错误在此抛出——会话缓存尚未改动
      _cacheV3Material(id, unlock);
      cacheFilePassword(id, newPassword);
      try {
        final sealed = await VaultFileCodec.encryptWithPasswordV3(
          unlock.plain,
          newPassword,
          aadContext: 'doc:$id',
          dek: unlock.dek,
          usbWrapped: unlock.usbWrapped,
        );
        await _writeSealedBytes(id, sealed);
      } catch (_) {
        cacheFilePassword(id, oldPassword); // 回滚会话缓存到仍有效的旧密码
        rethrow;
      }
      await _deleteThumbnail(id);
      onWrite?.call();
      return;
    }
    final plain = await VaultFileCodec.decryptWithPassword(
      raw,
      oldPassword,
      aadContext: 'doc:$id',
    );
    // v2 → v3 升级：生成新 DEK，暂不嵌重置盘槽位（钥匙不在设备上）。
    final dek = VaultFileCodec.generateDek();
    _sessionDocDeks[id] = dek;
    _sessionFileUsbWrapped.remove(id);
    cacheFilePassword(id, newPassword);
    try {
      final sealed = await VaultFileCodec.encryptWithPasswordV3(
        Uint8List.fromList(plain),
        newPassword,
        aadContext: 'doc:$id',
        dek: dek,
      );
      await _writeSealedBytes(id, sealed);
    } catch (_) {
      cacheFilePassword(id, oldPassword); // 回滚会话缓存到仍有效的旧密码
      rethrow;
    }
    await _deleteThumbnail(id);
    onWrite?.call();
  }

  /// 绑定重置密码盘到已设密文档（事后绑定通道；须验证文件密码）。
  /// 已绑定 / 非 v3 信封抛 [StateError]；密码错误抛 [VaultFileException]。
  Future<void> bindFileUsbSlot(
    String id,
    String password,
    List<int> usbKey,
  ) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null || !VaultFileCodec.isPasswordEnvelope(raw)) {
      throw StateError('该文档未设置文件密码');
    }
    if (!VaultFileCodec.isV3Envelope(raw)) {
      throw StateError('旧版密码文件：请先修改一次密码升级格式后再绑定');
    }
    if (VaultFileCodec.hasUsbSlotV3(raw)) {
      throw StateError('该文档已绑定重置密码盘');
    }
    final unlock = await VaultFileCodec.unlockWithPasswordV3(
      raw,
      password,
      aadContext: 'doc:$id',
    );
    final usbWrapped = await VaultFileCodec.wrapUsbSlotV3(
      usbKey: usbKey,
      dek: unlock.dek,
      aadContext: 'doc:$id',
    );
    final sealed = await VaultFileCodec.encryptWithPasswordV3(
      unlock.plain,
      password,
      aadContext: 'doc:$id',
      dek: unlock.dek,
      usbWrapped: usbWrapped,
    );
    _cacheV3Material(
      id,
      VaultFileV3Unlock(unlock.plain, unlock.dek, usbWrapped),
    );
    cacheFilePassword(id, password);
    await _writeSealedBytes(id, sealed);
    await _deleteThumbnail(id);
    onWrite?.call();
  }

  /// 重置密码盘重置文件密码（N4 批 2：忘记密码通道）。
  ///
  /// USB 钥匙解出 DEK → 新盐重绕密码槽（载荷密文与重置盘槽位原样保留，
  /// LUKS 同款）。**不需要旧密码**；成功后会话已缓存新密码（可直接打开）。
  /// 非密码信封 / 未绑定重置盘 / 盘不匹配 → 返回 false（fail-closed）。
  Future<bool> resetFilePasswordWithUsb(
    String id,
    List<int> usbKey,
    String newPassword,
  ) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null || !VaultFileCodec.isV3Envelope(raw)) return false;
    final VaultFileV3Rewrap rewrap;
    try {
      rewrap = await VaultFileCodec.rewrapPasswordSlotV3(
        raw,
        usbKey,
        newPassword,
        aadContext: 'doc:$id',
      );
    } on VaultFileException {
      return false;
    }
    _sessionDocDeks[id] = rewrap.dek;
    final usb = rewrap.usbWrapped;
    if (usb != null) {
      _sessionFileUsbWrapped[id] = usb;
    } else {
      _sessionFileUsbWrapped.remove(id);
    }
    cacheFilePassword(id, newPassword);
    await _writeSealedBytes(id, rewrap.blob);
    await _deleteThumbnail(id);
    onWrite?.call();
    return true;
  }

  /// 移除文件密码：回封为 v1 主密钥信封（应用锁未解锁时拒绝——
  /// 明文落盘不可接受，fail-closed）。密码错误抛 [VaultFileException]。
  Future<void> removeFilePassword(String id, String password) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null || !VaultFileCodec.isPasswordEnvelope(raw)) {
      throw StateError('该文档未设置文件密码');
    }
    Uint8List plain;
    if (VaultFileCodec.isV3Envelope(raw)) {
      final unlock = await VaultFileCodec.unlockWithPasswordV3(
        raw,
        password,
        aadContext: 'doc:$id',
      );
      _cacheV3Material(id, unlock);
      plain = unlock.plain;
    } else {
      plain = await VaultFileCodec.decryptWithPassword(
        raw,
        password,
        aadContext: 'doc:$id',
      );
    }
    final key = await _currentKey();
    if (key == null) {
      throw const VaultFileLockException();
    }
    final sealed = await VaultFileCodec.encrypt(
      plain,
      key,
      aadContext: 'doc:$id',
    );
    forgetFilePassword(id);
    await _writeSealedBytes(id, sealed);
    onWrite?.call();
  }

  /// 删除缩略图（设密/改密时调用——防首页预览泄露，用户拍板「隐藏缩略图」）。
  Future<void> _deleteThumbnail(String id) async {
    try {
      await _ensureThumbsDir();
      final thumb = File(_thumbPathFor(id));
      if (await thumb.exists()) await thumb.delete();
    } catch (_) {
      // 缩略图清理失败不影响密码设置本身。
    }
  }
}
