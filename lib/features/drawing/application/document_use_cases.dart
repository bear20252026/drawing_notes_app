import '../../domain/entities/document.dart';
import '../../domain/repositories/document_repository.dart';

/// 文档用例 — Application 层。
///
/// 封装文档相关的业务用例，仅依赖 Domain 层。
class DocumentUseCases {
  final DocumentRepository _repository;

  const DocumentUseCases(this._repository);

  /// 加载文档
  Future<DrawingDocument?> loadDocument(String id) {
    return _repository.load(id);
  }

  /// 保存文档
  Future<void> saveDocument(DrawingDocument document) {
    return _repository.save(document);
  }

  /// 删除文档
  Future<void> deleteDocument(String id) {
    return _repository.delete(id);
  }

  /// 列出所有文档
  Future<List<DrawingDocument>> listDocuments() {
    return _repository.list();
  }

  /// 创建新文档
  Future<DrawingDocument> createDocument({String? title}) {
    return _repository.create(title: title);
  }
}
