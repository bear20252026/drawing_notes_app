import '../../domain/entities/stroke.dart';
import '../../domain/repositories/stroke_repository.dart';

/// 笔画用例 — Application 层。
///
/// 封装笔画相关的业务用例，仅依赖 Domain 层。
class StrokeUseCases {
  final StrokeRepository _repository;

  const StrokeUseCases(this._repository);

  /// 保存笔画
  Future<void> saveStroke(String documentId, Stroke stroke) {
    return _repository.save(documentId, stroke);
  }

  /// 删除笔画
  Future<void> deleteStroke(String documentId, String strokeId) {
    return _repository.delete(documentId, strokeId);
  }

  /// 加载文档的所有笔画
  Future<List<Stroke>> loadStrokes(String documentId) {
    return _repository.loadByDocument(documentId);
  }

  /// 批量保存笔画
  Future<void> saveStrokes(String documentId, List<Stroke> strokes) {
    return _repository.saveBatch(documentId, strokes);
  }
}
