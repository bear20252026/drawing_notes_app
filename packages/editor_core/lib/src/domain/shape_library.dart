// editor_core——ShapeLibrary 形状库（Excalidraw 借鉴——2026-08-21）。
//
// Excalidraw Library System 本地化——预定义形状集合（可复用积木块）。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版架构参考：
// - LibraryItem（id/status/elements/created/name）——自包含元素组
// - Library 类管理运行时状态
// - 适配器模式解耦存储
// - 去重机制（element counts/IDs/versionNonce）
//
// 本地化：将 Excalidraw 的元素组映射为我们的 domain 模型。
library;

/// 形状库条目（Excalidraw LibraryItem 本地化——不可变）。
///
/// 每个条目是一组可复用元素（形状/笔画/文本）的集合。
class ShapeLibraryItem {
  const ShapeLibraryItem({
    required this.id,
    required this.name,
    this.shapes = const [],
    this.strokes = const [],
    this.texts = const [],
    this.description = '',
    this.tags = const [],
    this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final List<String> tags;
  final List<ShapeDef> shapes;
  final List<StrokeDef> strokes;
  final List<TextDef> texts;
  final DateTime? createdAt;

  ShapeLibraryItem copyWith({
    String? name,
    String? description,
    List<String>? tags,
    List<ShapeDef>? shapes,
    List<StrokeDef>? strokes,
    List<TextDef>? texts,
  }) {
    return ShapeLibraryItem(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      shapes: shapes ?? this.shapes,
      strokes: strokes ?? this.strokes,
      texts: texts ?? this.texts,
      createdAt: createdAt,
    );
  }

  /// 条目是否为空（无元素）。
  bool get isEmpty => shapes.isEmpty && strokes.isEmpty && texts.isEmpty;

  /// 元素总数（用于去重比较——Excalidraw versionNonce 模式）。
  int get elementCount => shapes.length + strokes.length + texts.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShapeLibraryItem && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 形状定义（库中的形状模板——不可变）。
class ShapeDef {
  const ShapeDef({
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.strokeColor = '#000000',
    this.backgroundColor = 'transparent',
    this.strokeWidth = 2,
  });

  final String type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final String strokeColor;
  final String backgroundColor;
  final int strokeWidth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShapeDef && type == other.type && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(type, x, y);
}

/// 笔画定义（库中的笔画模板——不可变）。
class StrokeDef {
  const StrokeDef({
    required this.points,
    this.strokeColor = '#000000',
    this.strokeWidth = 2,
  });

  final List<({double x, double y})> points;
  final String strokeColor;
  final int strokeWidth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokeDef && points.length == other.points.length;

  @override
  int get hashCode => points.length.hashCode;
}

/// 文本定义（库中的文本模板——不可变）。
class TextDef {
  const TextDef({
    required this.content,
    required this.x,
    required this.y,
    this.fontSize = 14,
    this.color = '#000000',
  });

  final String content;
  final double x;
  final double y;
  final int fontSize;
  final String color;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextDef && content == other.content && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(content, x, y);
}

/// 形状库（Excalidraw Library 本地化——管理形状条目集合）。
///
/// 参考 Excalidraw 架构：
/// - 条目管理（添加/删除/更新/搜索/去重）
/// - 适配器模式（存储解耦——可切换 IndexedDB/文件/内存）
/// - 不可变（copyWith）
class ShapeLibrary {
  const ShapeLibrary({
    this.items = const [],
    this.name = 'My Library',
  });

  final List<ShapeLibraryItem> items;
  final String name;

  ShapeLibrary copyWith({List<ShapeLibraryItem>? items, String? name}) {
    return ShapeLibrary(
      items: items ?? this.items,
      name: name ?? this.name,
    );
  }

  /// 添加条目（去重——按 id）。
  ShapeLibrary addItem(ShapeLibraryItem item) {
    if (items.any((i) => i.id == item.id)) return this;
    return ShapeLibrary(items: [...items, item], name: name);
  }

  /// 移除条目。
  ShapeLibrary removeItem(String itemId) {
    return ShapeLibrary(
      items: items.where((i) => i.id != itemId).toList(),
      name: name,
    );
  }

  /// 更新条目。
  ShapeLibrary updateItem(ShapeLibraryItem item) {
    return ShapeLibrary(
      items: items.map((i) => i.id == item.id ? item : i).toList(),
      name: name,
    );
  }

  /// 搜索（按名称/标签——Excalidraw deburr 模式简化版）。
  List<ShapeLibraryItem> search(String query) {
    if (query.isEmpty) return items;
    final lower = query.toLowerCase();
    return items.where((i) =>
      i.name.toLowerCase().contains(lower) ||
      i.tags.any((t) => t.toLowerCase().contains(lower))
    ).toList();
  }

  /// 条目数。
  int get count => items.length;

  /// 是否为空。
  bool get isEmpty => items.isEmpty;
}
