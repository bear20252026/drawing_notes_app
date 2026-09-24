part of 'storage_service.dart';

// 删除私有助手域（O1 拆分自 storage_service.dart）：独占删除实现。
// public 回收站 API 与 delete @override 包装留在本体。行为零变化。

/// 删除私有助手（拆分自 storage_service.dart）。
extension _StorageTrash on StorageService {
  Future<bool> _deleteLocked(String id) async {
    await _ensureDocumentsDir();
    final file = File(_pathFor(id));
    if (!file.existsSync()) return false;

    // 必须在删除主文件前读取其引用；无法读取时不进行资产回收，保证数据安全。
    DrawingDocument? document;
    try {
      var raw = await file.readAsBytes();
      if (VaultFileCodec.isEncrypted(raw)) {
        final key = await _currentKey();
        // 锁定/无密钥：解不开就不读——文档置 null，保守跳过资产回收。
        if (key != null) {
          raw = await VaultFileCodec.decrypt(raw, key, aadContext: 'doc:$id');
        }
      }
      document = _codec.decode(raw);
    } catch (_) {
      // 损坏/锁定文档仍允许用户删除，但不基于不可信内容删除任何资产。
    }

    final imagePaths = <String>{};
    if (document != null) {
      for (final item in document.imageItems) {
        final managedPath = await _managedImagePathOrNull(item.filePath);
        if (managedPath != null) imagePaths.add(managedPath);
      }
    }

    // M-06 修复（专家审计 2026-08-15）：删除移入回收站（30 天保留——
    // Android 官方 createTrashRequest 模式），非永久删除——误删可恢复。
    final trashDir = await _ensureTrashDir();
    await file.rename(
      '${trashDir.path}${Platform.pathSeparator}'
      '${id}_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    final backup = File('${file.path}.bak');
    if (backup.existsSync()) {
      await backup.delete();
    }

    // 清理缩略图（尽力而为，缩略图缺失不影响使用）。
    try {
      await _ensureThumbsDir();
      final thumb = File(_thumbPathFor(id));
      if (thumb.existsSync()) {
        await thumb.delete();
      }
    } catch (_) {
      // 缩略图清理失败不影响文档删除与后续资产回收。
    }
    forgetFilePassword(id); // 批次②：删除后清除会话文件密码缓存

    await _deleteUnreferencedManagedImages(imagePaths, excludingDocumentId: id);
    onWrite?.call();
    return true;
  }

  /// 恢复回收站项（M-06）：trashName 如 `doc123_1720000000000.json`——
  /// 移回 documents/ 目录。返回恢复后的文档 ID；失败（原 ID 冲突等）返回 null。
  /// E-17 修复（审计 2026-09-07）：rename 挂入与保存/删除相同的 per-id
  /// 写尾队列——恢复与在途保存交错会把恢复出的旧文档覆盖为新快照，
  /// 或让同 ID 冲突判定出现 TOCTOU。
}
