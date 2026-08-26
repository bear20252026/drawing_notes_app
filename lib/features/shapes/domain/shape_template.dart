// shapes — Domain 层：形状模板实体（零外部依赖）
// 遵循 Clean Architecture：Domain 层不依赖任何外部库或框架

/// 形状模板（不可变）
///
/// 表示用户可复用的自定义形状定义
class ShapeTemplate {
  const ShapeTemplate({
    required this.id,
    required this.name,
    required this.pathData,
    this.createdAt,
    this.updatedAt,
  });

  /// 唯一标识符
  final String id;

  /// 形状名称
  final String name;

  /// 形状路径数据（SVG 路径字符串）
  final String pathData;

  /// 创建时间
  final DateTime? createdAt;

  /// 更新时间
  final DateTime? updatedAt;

  /// 创建副本并覆盖指定字段
  ShapeTemplate copyWith({
    String? id,
    String? name,
    String? pathData,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ShapeTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      pathData: pathData ?? this.pathData,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShapeTemplate &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          pathData == other.pathData;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ pathData.hashCode;

  @override
  String toString() => 'ShapeTemplate(id: $id, name: $name)';
}
