import '../../domain/entities/stroke.dart';
import '../../domain/repositories/stroke_repository.dart';

/// 笔画仓库实现 — Infrastructure 层。
class StrokeRepositoryImpl implements StrokeRepository {
  // TODO: 接入实际存储
  final Map<String, List<Stroke>> _strokes = {};

  @override
  Future<void> save(String documentId, Stroke stroke) async {
    _strokes.putIfAbsent(documentId, () => []);
    final list = _strokes[documentId]!;
    list.removeWhere((s) => s.id == stroke.id);
    list.add(stroke);
  }

  @override
  Future<void> delete(String documentId, String strokeId) async {
    _strokes[documentId]?.removeWhere((s) => s.id == strokeId);
  }

  @override
  Future<List<Stroke>> loadByDocument(String documentId) async {
    return _strokes[documentId] ?? [];
  }

  @override
  Future<void> saveBatch(String documentId, List<Stroke> strokes) async {
    _strokes[documentId] = strokes;
  }
}
