import '../entities/stroke.dart';

/// 笔画仓库接口 — 零依赖。
///
/// 定义笔画持久化的抽象接口。
abstract class StrokeRepository {
  /// 保存笔画
  Future<void> save(String documentId, Stroke stroke);

  /// 删除笔画
  Future<void> delete(String documentId, String strokeId);

  /// 加载文档的所有笔画
  Future<List<Stroke>> loadByDocument(String documentId);

  /// 批量保存笔画
  Future<void> saveBatch(String documentId, List<Stroke> strokes);
}
