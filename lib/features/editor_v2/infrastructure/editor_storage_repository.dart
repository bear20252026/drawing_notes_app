// editor_v2 — Infrastructure 层：EditorRepository 实现
// 遵循 Clean Architecture：Infrastructure 层实现 Domain 层定义的接口
// 此文件依赖外部存储实现（StorageService）—— 由 DI 注入

import 'package:editor_core/editor_core.dart';

import '../../../infrastructure/storage/storage_service.dart';
import '../domain/editor_repository.dart';

/// EditorRepository 的存储实现（基于 StorageService）
///
/// 将 Domain 层的 DocumentMeta 与存储层的存储格式桥接
/// 所有 I/O 异常向上传播——由 Application 层决定处理策略
class EditorStorageRepository implements EditorRepository {
  const EditorStorageRepository(this._storage);

  final StorageService _storage;

  @override
  Future<Map<String, dynamic>?> loadDocument(String documentId) {
    return _storage.loadJson(documentId);
  }

  @override
  Future<void> saveDocument(String documentId, Map<String, dynamic> json) {
    return _storage.saveJson(documentId, json);
  }

  @override
  Future<List<DocumentMeta>> listDocumentMeta() async {
    final metas = await _storage.listDocuments();
    return metas
        .map((m) => DocumentMeta(
              id: m.id,
              title: m.title,
              createdAt: m.createdAt,
              updatedAt: m.updatedAt,
            ))
        .toList();
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    await _storage.delete(documentId);
  }
}
