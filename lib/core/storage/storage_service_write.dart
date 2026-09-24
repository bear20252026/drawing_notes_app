part of 'storage_service.dart';

// 写入与加密落盘域（O1 拆分自 storage_service.dart）：文档独占锁、
// 密封（isolate 分档）、懒迁移队列、临时文件原子替换（含 Windows
// 共享冲突退避）。save/@override 与静态阈值留在本体。行为零变化。

/// 写入与加密落盘私有助手（拆分自 storage_service.dart）。
extension _StorageWrite on StorageService {
  Future<T> _runDocExclusive<T>(String id, Future<T> Function() op) {
    final previous = _writeTails[id] ?? Future<void>.value();
    final task = previous.catchError((_) {}).then((_) => op());
    late final Future<void> chain;
    chain = task.then(
      (_) {
        if (identical(_writeTails[id], chain)) _writeTails.remove(id);
      },
      onError: (_) {
        if (identical(_writeTails[id], chain)) _writeTails.remove(id);
      },
    );
    _writeTails[id] = chain;
    return task;
  }

  Future<Uint8List?> _currentKey() async {
    final provider = keyProvider;
    if (provider == null) return null;
    return provider();
  }

  /// isolate 加密封包的字节阈值：小于该值时主线程同步封包（isolate
  /// 拷贝往返开销大于收益），大载荷移入 isolate 避免 UI 掉帧。

  Future<Uint8List> _sealDocBytes(String id, Uint8List data) async {
    final filePassword = _sessionFilePasswords[id];
    if (filePassword != null) {
      final dek = _sessionDocDeks[id];
      final usbWrapped = _sessionFileUsbWrapped[id];
      Future<Uint8List> seal() => VaultFileCodec.encryptWithPasswordV3(
        data,
        filePassword,
        aadContext: 'doc:$id',
        dek: dek,
        usbWrapped: usbWrapped,
      );
      if (data.length < StorageService._isolateSealThreshold) return seal();
      return Isolate.run(seal);
    }
    final provider = keyProvider;
    // 未启用加密（无 keyProvider）：明文落盘是产品设计（用户未设 PIN），
    // 与读路径「明文 + 无密钥 → 原样返回」对称。
    if (provider == null) return data;
    final key = await provider();
    // 安全审计修复（2026-09-06 P2-3）：keyProvider 已装配（保险库启用）
    // 但取不到密钥 = 锁定态。此前静默明文落盘（fail-open，与读路径的
    // fail-closed 不对齐）；现显式失败，交由 SaveScheduler 重试策略处理。
    if (key == null) throw const VaultFileLockException();
    if (data.length < StorageService._isolateSealThreshold) {
      return VaultFileCodec.encrypt(data, key, aadContext: 'doc:$id');
    }
    return Isolate.run(
      () => VaultFileCodec.encrypt(data, key, aadContext: 'doc:$id'),
    );
  }

  /// 媒体字节写入前准备（批次①c：缩略图 / 受管图片）：有主密钥 →
  /// 信封加密（AAD 绑定文件名）。锁定态与文档同口径 fail-closed；
  /// 未启用加密（无 keyProvider）保持明文兼容。
  Future<Uint8List> _sealMediaBytes(String path, Uint8List bytes) async {
    final provider = keyProvider;
    if (provider == null) return bytes;
    final key = await provider();
    if (key == null) throw const VaultFileLockException();
    return VaultFileCodec.encrypt(
      bytes,
      key,
      aadContext: VaultFileCodec.contextForPath(path),
    );
  }

  /// 读取后的字节准备（读路径自动分流，Joplin 懒迁移模式）：
  /// - v2 密码信封 + 会话有密码 → 解密；无密码 → [VaultFilePasswordLockException]；
  /// - v1 主密钥信封 + 已解锁 → 解密；锁定 → [VaultFileLockException]；
  /// - 明文 + 有密钥 → 原样返回并排队懒迁移（下次写队列将明文重写为密文）；
  /// - 明文 + 无密钥 → 原样返回（旧版本兼容）。
  Future<Uint8List> _prepareDocBytes(String id, Uint8List raw) async {
    if (VaultFileCodec.isPasswordEnvelope(raw)) {
      final filePassword = _sessionFilePasswords[id];
      if (filePassword == null) {
        throw const VaultFilePasswordLockException();
      }
      if (VaultFileCodec.isV3Envelope(raw)) {
        // N4 批 2：v3 双保护器信封——解锁并缓存 DEK/USB 槽位（续写续用）。
        final unlock = await VaultFileCodec.unlockWithPasswordV3(
          raw,
          filePassword,
          aadContext: 'doc:$id',
        );
        _cacheV3Material(id, unlock);
        return unlock.plain;
      }
      return VaultFileCodec.decryptWithPassword(
        raw,
        filePassword,
        aadContext: 'doc:$id',
      );
    }
    final key = await _currentKey();
    if (VaultFileCodec.isEncrypted(raw)) {
      if (key == null) throw const VaultFileLockException();
      return VaultFileCodec.decrypt(raw, key, aadContext: 'doc:$id');
    }
    if (key != null) _enqueueRawRewrite(id, raw);
    return raw;
  }

  /// 懒迁移：把明文字节经既有写尾队列重写为密文（与保存共用并发纪律）。
  void _enqueueRawRewrite(String id, Uint8List plaintext) {
    final previous = _writeTails[id] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.catchError((_) {}).then((_) async {
      await _saveEncoded(id, plaintext);
    });
    _writeTails[id] = operation;
    operation.whenComplete(() {
      if (identical(_writeTails[id], operation)) _writeTails.remove(id);
    });
  }

  Future<void> _saveEncoded(String id, Uint8List data) async {
    await _ensureDocumentsDir();
    final sealed = await _sealDocBytes(id, data);
    await _writeSealedBytes(id, sealed);
  }

  /// 把已密封字节原子落盘（含 .bak 备份——与 _saveEncoded 同纪律）。
  ///
  /// A2/A3 修复（审计 2026-09-07）：
  /// - `.bak` 备份失败改为 fail-closed——复制失败时中止本次写入（正式文件
  ///   保持完好、清理 tmp 后抛「备份写入失败」）。此前静默吞错会在 Windows
  ///   回退路径（先删目标再 rename）下失去崩溃恢复保障：rename 期崩溃 =
  ///   旧版无 .bak、新版未落盘，文档表现为丢失。
  /// - tmp 写入/rename 任一失败都清理残留临时文件，防止半写 .tmp 堆积。
  /// 失败路径顺序保证：copy bak 在 rename tmp→dest 之前，任何失败发生时
  /// 正式文件都未被删除/覆盖。
  Future<void> _writeSealedBytes(String id, Uint8List sealed) async {
    await _ensureDocumentsDir();
    final finalFile = File(_pathFor(id));
    final tmp = File('${finalFile.path}.${LocalIdGenerator.next('write')}.tmp');
    try {
      await tmp.writeAsBytes(sealed, flush: true);

      // 备份上一版：若平台不允许直接覆盖目标文件，恢复路径仍保留上一份
      // 完整数据。备份是 Windows 删除-换入回退的崩溃恢复前提——失败即中止。
      if (finalFile.existsSync()) {
        try {
          await finalFile.copy('${finalFile.path}.bak');
        } catch (e) {
          throw FileSystemException('备份写入失败：$e', finalFile.path);
        }
      }
      await _replaceWithTemp(tmp, finalFile);
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始存储异常。
      }
      rethrow;
    }
  }

  /// 首选 rename（POSIX 原子替换）；若 Windows 拒绝覆盖已有文件，则在已经
  /// 生成 `.bak` 的前提下删除旧目标并立即换入完整临时文件。加载逻辑会在
  /// 正式文件缺失或损坏时读取 `.bak`，因此崩溃窗口不会表现为文档消失。
  ///
  /// Windows 共享冲突退避（2026-09-24 懒迁移 flake 根因修复）：杀毒/
  /// 索引器/并发读会短暂持有目标句柄——delete 抛 errno 32，甚至 delete
  /// 返回后的 delete-pending 窗口里 rename 也会失败。与 [_readWithRetry]
  /// 同思路做有界退避重试：`.bak` 已先行落盘，重试不放大风险；耗尽后
  /// 按原样抛出（备份仍在，读路径可恢复）。
  Future<void> _replaceWithTemp(File tmp, File destination) async {
    for (var attempt = 1;; attempt++) {
      try {
        try {
          await tmp.rename(destination.path);
        } on FileSystemException {
          if (!destination.existsSync()) rethrow;
          await destination.delete();
          await tmp.rename(destination.path);
        }
        return;
      } on FileSystemException catch (e) {
        // errno 5（拒绝访问）多为 delete-pending 句柄窗口，同属瞬态。
        final code = e.osError?.errorCode;
        final transient = code == 32 || code == 5;
        if (!transient || attempt >= 5) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 25 * attempt));
      }
    }
  }

  /// 加载指定文档。文件不存在返回 null，格式损坏抛出异常（由调用方提示）。
  ///
  /// 崩溃恢复：正式文件损坏时，尝试读取 `.bak` 上一版备份。
  /// 读失败重试（对齐 Saber FileManager）：瞬时 IO 错误自动重试 3 次，
  /// 避免 U 盘/网络盘抖动导致误报"文档损坏"。
}
