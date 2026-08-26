import '../document.dart';

/// 文档仓库接口 — 零依赖。
///
/// 定义文档持久化的抽象接口，由 infrastructure 层实现。
abstract class DocumentRepository {
  /// 加载文档
  Future<DrawingDocument?> load(String id);

  /// 保存文档
  Future<void> save(DrawingDocument document);

  /// 删除文档
  Future<void> delete(String id);

  /// 列出所有文档
  Future<List<DrawingDocument>> list();

  /// 创建新文档
  Future<DrawingDocument> create({String? title});
}
