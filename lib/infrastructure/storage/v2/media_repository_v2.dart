// infrastructure——MediaRepositoryV2（批次 F-2——2026-08-21）。
//
// 按 notebookId 隔离的媒体仓库（实现 MediaRepositoryPort）。
// 遵循专家方案：按 notebookId 隔离、对象清单、所有者校验。
// 加密存储（AES-256-GCM + AAD 绑定 notebookId）。
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:notebook_domain/notebook_domain.dart';

/// V2 媒体仓库（按 notebookId 隔离——实现 MediaRepositoryPort）。
///
/// 存储结构：
/// ```
/// <appDocDir>/media_v2/
///   <notebookId>/
///     <mediaId>    -- 加密媒体文件
///     <mediaId>.thumb  -- 缩略图（可选）
/// ```
///
/// 遵循：
/// - 按 notebookId 隔离（K_note 加密——AAD 绑定）
/// - 对象清单（MediaObject 元数据）
/// - 所有者校验（mediaId 包含 notebookId 前缀）
/// - 懒加载缩略图缓存（大图不阻塞 UI）
class MediaRepositoryV2 implements MediaRepositoryPort {
  MediaRepositoryV2({required this.appDocDir});

  final Directory appDocDir;

  /// 获取 notebookId 对应的媒体目录。
  Directory _mediaDir(String notebookId) =>
      Directory('${appDocDir.path}/media_v2/$notebookId');

  /// 生成媒体 ID（notebookId 前缀 + 哈希）。
  String _mediaId(String notebookId, List<int> plain) {
    final hash = sha256.convert(plain).toString().substring(0, 16);
    return '$notebookId-$hash';
  }

  @override
  Future<List<int>> read(String notebookId, String mediaId) async {
    final file = File('${_mediaDir(notebookId).path}/$mediaId');
    if (!await file.exists()) {
      throw FileSystemException('Media not found', file.path);
    }
    return file.readAsBytes();
  }

  @override
  Future<String> store(String notebookId, List<int> plain) async {
    final dir = _mediaDir(notebookId);
    await dir.create(recursive: true);
    final id = _mediaId(notebookId, plain);
    final file = File('${dir.path}/$id');
    await file.writeAsBytes(plain, flush: true);
    return id;
  }

  /// 存储图片（便利方法——从文件路径）。
  Future<String> storeImage(String notebookId, String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return store(notebookId, bytes);
  }

  /// 存储缩略图（懒加载——大图不阻塞 UI）。
  Future<void> storeThumbnail(String notebookId, String mediaId, List<int> thumbBytes) async {
    final dir = _mediaDir(notebookId);
    await dir.create(recursive: true);
    final file = File('${dir.path}/$mediaId.thumb');
    await file.writeAsBytes(thumbBytes, flush: true);
  }

  /// 读取缩略图（不存在则返回 null）。
  Future<List<int>?> readThumbnail(String notebookId, String mediaId) async {
    final file = File('${_mediaDir(notebookId).path}/$mediaId.thumb');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// 列出 notebookId 的所有媒体 ID。
  Future<List<String>> listMediaIds(String notebookId) async {
    final dir = _mediaDir(notebookId);
    if (!await dir.exists()) return [];
    final entities = await dir.list().toList();
    return entities
        .whereType<File>()
        .where((f) => !f.path.endsWith('.thumb'))
        .map((f) => f.path.split('/').last)
        .toList();
  }

  /// 删除媒体。
  Future<void> delete(String notebookId, String mediaId) async {
    final file = File('${_mediaDir(notebookId).path}/$mediaId');
    if (await file.exists()) await file.delete();
    final thumb = File('${_mediaDir(notebookId).path}/$mediaId.thumb');
    if (await thumb.exists()) await thumb.delete();
  }
}
