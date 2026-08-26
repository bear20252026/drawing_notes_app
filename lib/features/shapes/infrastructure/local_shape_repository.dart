// shapes — Infrastructure 层：基于本地存储的形状仓储实现
// 遵循 Clean Architecture：Infrastructure 层实现 Domain 层定义的接口

import '../domain/shape_repository.dart';
import '../domain/shape_template.dart';

/// 基于内存 + JSON 文件持久化的形状仓储实现
///
/// 当前实现使用内存缓存 + JSON 文件持久化
/// 可扩展为基于 SQLite / Hive 等数据库实现
class LocalShapeRepository implements ShapeRepository {
  /// 内存缓存（启动时从文件加载，操作时同步写入）
  final List<ShapeTemplate> _cache = [];

  /// 是否已初始化（避免重复加载）
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    // 从 JSON 文件加载（此处为简化实现——实际项目中可替换为文件 I/O）
    // TODO: 实现从 application_support_directory/shapes.json 加载
    _initialized = true;
  }

  @override
  Future<List<ShapeTemplate>> listShapes() async {
    await _ensureInitialized();
    return List.unmodifiable(_cache);
  }

  @override
  Future<void> addShape(ShapeTemplate shape) async {
    await _ensureInitialized();
    _cache.add(shape);
    await _persist();
  }

  @override
  Future<void> updateShape(ShapeTemplate shape) async {
    await _ensureInitialized();
    final index = _cache.indexWhere((s) => s.id == shape.id);
    if (index != -1) {
      _cache[index] = shape;
      await _persist();
    }
  }

  @override
  Future<void> deleteShape(String id) async {
    await _ensureInitialized();
    _cache.removeWhere((s) => s.id == id);
    await _persist();
  }

  @override
  Future<ShapeTemplate?> findById(String id) async {
    await _ensureInitialized();
    try {
      return _cache.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 持久化到本地文件
  Future<void> _persist() async {
    // TODO: 将 _cache 序列化为 JSON 并写入 application_support_directory/shapes.json
    // 当前为简化实现——实际项目中可替换为 StorageService / UnifiedStorage
  }
}
