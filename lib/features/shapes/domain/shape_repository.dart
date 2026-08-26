// shapes — Domain 层：形状仓储接口（零外部依赖）
// 遵循 Clean Architecture：Domain 层定义抽象契约，实现由 Infrastructure 层提供

import 'shape_template.dart';

/// 形状仓储接口
///
/// 负责形状模板的持久化读写
/// 实现由 Infrastructure 层提供（基于本地存储 / 数据库等）
abstract class ShapeRepository {
  /// 列出所有形状模板
  Future<List<ShapeTemplate>> listShapes();

  /// 添加形状模板
  Future<void> addShape(ShapeTemplate shape);

  /// 更新形状模板
  Future<void> updateShape(ShapeTemplate shape);

  /// 删除形状模板
  Future<void> deleteShape(String id);

  /// 根据 ID 查找形状模板
  Future<ShapeTemplate?> findById(String id);
}
