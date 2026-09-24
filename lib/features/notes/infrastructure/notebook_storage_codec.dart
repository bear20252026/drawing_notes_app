part of 'notebook_storage.dart';

// 编码落盘域（O1 拆分自 notebook_storage.dart）：会话密钥、快照准备、
// 懒迁移队列、写笔记本与字节写入。public API 与静态编码阈值留在本体。行为零变化。

/// 加密编码/写盘域私有助手（拆分自 notebook_storage.dart）。
extension _NotebookStorageCodec on NotebookStorage {

  Future<Uint8List?> _currentKey() async {
    final provider = keyProvider;
    if (provider == null) return null;
    return provider();
  }


  /// 读取后的字节准备（批次①c，与 StorageService/NoteBlockDocStore 同纪律）：
  /// 密文+解锁 → 解密；密文+锁定 → [VaultFileLockException]；
  /// 明文+有钥 → 原样返回并经写尾队列懒迁移（[migrate] 为 false 时仅解密，
  /// 不排队迁移——备份回退路径用，避免用备份内容覆盖主文件）。
  Future<Uint8List> _prepareNotebookBytes(
    String id,
    Uint8List raw, {
    bool migrate = true,
  }) async {
    final key = await _currentKey();
    if (VaultFileCodec.isEncrypted(raw)) {
      if (key == null) throw const VaultFileLockException();
      return VaultFileCodec.decrypt(raw, key, aadContext: 'nb:$id');
    }
    if (key != null && migrate) _enqueueRawRewrite(id, raw);
    return raw;
  }


  /// 懒迁移：明文笔记本经写尾队列重写为 DNV 密文。
  void _enqueueRawRewrite(String id, Uint8List plaintext) {
    final previous = _writeTails[id] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.catchError((_) {}).then((_) async {
      final key = await _currentKey();
      if (key == null) return;
      final sealed = await VaultFileCodec.encrypt(
        plaintext,
        key,
        aadContext: 'nb:$id',
      );
      final file = File(await _pathFor(id));
      if (!file.existsSync()) return; // 已被删除——不复活
      final tmp = File('${file.path}.${LocalIdGenerator.next('write')}.tmp');
      await tmp.writeAsBytes(sealed, flush: true);
      try {
        await tmp.rename(file.path);
      } on FileSystemException {
        if (!file.existsSync()) rethrow;
        await file.delete();
        await tmp.rename(file.path);
      }
    });
    _writeTails[id] = operation;
    operation.catchError((_) {
      // 迁移失败静默（下次读取再试——幂等）。
      if (identical(_writeTails[id], operation)) _writeTails.remove(id);
    });
  }


  /// 原子写入笔记本文件（不涉及加密判断；被 [save] 调用）。
  Future<String> _writeNotebook(Notebook notebook) async {
    if (!NotebookStorage.isValidId(notebook.id)) {
      throw ArgumentError.value(notebook.id, 'notebook.id', '笔记本 ID 不合法');
    }
    await _ensureNotebooksDir();
    // 在排队前取不可变快照（ toJson() 产出纯 Map/List/String/num），避免
    // 用户继续编辑时旧任务写入可变的混合状态；随后 jsonEncode + UTF-8
    // 的大载荷开销交给 isolate（见 _encodeSnapshotAsync——DocumentCodec
    // .encodeSnapshotAsync 同纪律），保存瞬间不再阻塞 UI。
    final snapshot = notebook.toJson();
    final finalPath = await _pathFor(notebook.id);
    final id = notebook.id;
    final previous = _writeTails[id] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.catchError((_) {}).then((_) async {
      final data = await NotebookStorage._encodeSnapshotAsync(snapshot);
      // 批次①c：保险库解锁 → DNV 信封（AAD 绑定 nb:<id>）；锁定 → 明文
      // 兼容（既有单笔记本密码/DAN 层不受影响，读取时懒迁移）。
      final key = await _currentKey();
      final payload = key == null
          ? data
          : await VaultFileCodec.encrypt(data, key, aadContext: 'nb:$id');
      await _writeNotebookBytes(File(finalPath), payload);
    });
    _writeTails[id] = operation;
    try {
      await operation;
      onWrite?.call();
      return finalPath;
    } finally {
      if (identical(_writeTails[id], operation)) {
        unawaited(_writeTails.remove(id));
      }
    }
  }


  /// A5 修复（审计 2026-09-07）：tmp 写入/rename 失败时清理残留临时文件
  /// （favorite_store 同款纪律）。storeImage（E-19）亦复用本出口。
  Future<void> _writeNotebookBytes(File destination, List<int> data) async {
    final tmp = File(
      '${destination.path}.${LocalIdGenerator.next('write')}.tmp',
    );
    try {
      await tmp.writeAsBytes(data, flush: true);
      if (destination.existsSync()) {
        try {
          await destination.copy('${destination.path}.bak');
        } catch (_) {
          // 备份是恢复保障；其失败不阻塞当前写入。
        }
      }
      try {
        await tmp.rename(destination.path);
      } on FileSystemException {
        if (!destination.existsSync()) rethrow;
        await destination.delete();
        await tmp.rename(destination.path);
      }
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始存储异常。
      }
      rethrow;
    }
  }
}
