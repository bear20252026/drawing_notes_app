import '../../domain/entities/document.dart';
import '../../domain/repositories/document_repository.dart';

/// 文档仓库实现 — Infrastructure 层。
///
/// 使用本地存储实现文档持久化。
class DocumentRepositoryImpl implements DocumentRepository {
  // TODO: 接入实际存储（SQLite / 文件系统）
  final Map<String, DrawingDocument> _documents = {};

  @override
  Future<DrawingDocument?> load(String id) async {
    return _documents[id];
  }

  @override
  Future<void> save(DrawingDocument document) async {
    _documents[document.id] = document;
  }

  @override
  Future<void> delete(String id) async {
    _documents.remove(id);
  }

  @override
  Future<List<DrawingDocument>> list() async {
    return _documents.values.toList();
  }

  @override
  Future<DrawingDocument> create({String? title}) async {
    final doc = DrawingDocument(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      title: title ?? '未命名',
    );
    _documents[doc.id] = doc;
    return doc;
  }
}
