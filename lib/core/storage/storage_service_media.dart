part of 'storage_service.dart';

// 媒体资产私有助手域（O1 拆分自 storage_service.dart）：缩略图路径与
// 受管图片引用清理。public 媒体 API 与静态成员留在本体。行为零变化。

/// 媒体资产私有助手（拆分自 storage_service.dart）。
extension _StorageMedia on StorageService {
  String _thumbPathFor(String id) {
    if (!StorageService.isValidId(id)) {
      throw ArgumentError.value(id, 'id', '缩略图 ID 不合法（路径遍历防护）');
    }
    return '${_thumbsDir!.path}${Platform.pathSeparator}$id.png';
  }

  /// 保存文档的缩略图（PNG 字节），供列表页快速展示。
  /// 缩略图与工程文件分离存储，损坏不影响工程文件。
  /// 批次①c：有主密钥时信封加密落盘（读取走 [thumbnailBytes]）。
  /// 批次②：单文件密码文档不写缩略图（防首页预览泄露——用户拍板）。

  Future<String?> _managedImagePathOrNull(String path) async {
    if (path.isEmpty) return null;
    final root = await _ensureImagesDir();
    final image = File(path).absolute;
    final parentPath = image.parent.absolute.uri.normalizePath().toFilePath();
    final rootPath = root.absolute.uri.normalizePath().toFilePath();
    if (parentPath != rootPath) return null;
    return image.uri.normalizePath().toFilePath();
  }

  /// 删除已经不被其他绘图文档引用的受管图片。任何文档**解码失败（含加密
  /// 文档在锁定态）即中止整个回收**——无法证明它是否引用了资产，保守策略
  /// 优先保证用户数据不被误删（安全审计 P2-4，2026-09-06：此前跳过失败
  /// 文档，其引用的图片可能被误判孤儿并删除）。
  Future<void> _deleteUnreferencedManagedImages(
    Set<String> candidates, {
    required String excludingDocumentId,
  }) async {
    if (candidates.isEmpty) return;
    final referencedElsewhere = <String>{};
    final dir = await _ensureDocumentsDir();
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final Uint8List raw;
      try {
        raw = await entity.readAsBytes();
      } catch (_) {
        return; // 读取失败：无法证明引用关系，保守中止回收。
      }
      final fileName = entity.uri.pathSegments.last;
      final docId = fileName.substring(0, fileName.length - '.json'.length);
      final Uint8List plain;
      try {
        plain = await _prepareDocBytes(docId, raw);
      } catch (_) {
        // 解码/解密失败（如锁定态的密文文档）：其 imageItems 不可知，
        // 贸然回收可能误删它引用的图片 → 保守中止本次回收。
        return;
      }
      try {
        final other = _codec.decode(plain);
        if (other.id == excludingDocumentId) continue;
        for (final item in other.imageItems) {
          final managedPath = await _managedImagePathOrNull(item.filePath);
          if (managedPath != null) referencedElsewhere.add(managedPath);
        }
      } catch (_) {
        // 解析失败同样中止，避免将未知引用误判为孤儿资产。
        return;
      }
    }

    for (final candidate in candidates.difference(referencedElsewhere)) {
      try {
        final image = File(candidate);
        if (image.existsSync()) await image.delete();
      } on FileSystemException {
        // 主文档已经成功删除；图片回收失败可在未来维护扫描中重试。
      }
    }
  }

  /// 生成一个唯一的文档 ID。
}
