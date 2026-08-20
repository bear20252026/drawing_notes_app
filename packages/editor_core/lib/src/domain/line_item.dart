// editor_core——V2 领域模型扩展（批次 C——2026-08-18——专家方案）。
//
// 为 DocumentReducer 提供 V2 不可变领域模型：
// - LayerV2（图层——不可变）
// - ShapeItem（形状——不可变）
// - TextItem（文本——不可变）
// - LineItem（笔画——不可变）
// - Point（点——不可变）
library;

/// 点（不可变）。
class Point {
  const Point(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Point && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// 线段（不可变）。
class LineItem {
  const LineItem({
    required this.id,
    required this.points,
  });

  final String id;
  final List<Point> points;

  LineItem copyWith({List<Point>? points}) {
    return LineItem(id: id, points: points ?? this.points);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineItem &&
          id == other.id &&
          _listEquals(points, other.points);

  @override
  int get hashCode => Object.hash(id, points);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 形状（不可变）。
class ShapeItem {
  const ShapeItem({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
  });

  final String id;
  final String type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;

  ShapeItem copyWith({double? x, double? y, double? width, double? height, double? rotation}) {
    return ShapeItem(
      id: id,
      type: type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShapeItem &&
          id == other.id &&
          type == other.type &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(id, type, x, y);
}

/// 文本（不可变）。
class TextItem {
  const TextItem({
    required this.id,
    required this.content,
    required this.x,
    required this.y,
  });

  final String id;
  final String content;
  final double x;
  final double y;

  TextItem copyWith({String? content, double? x, double? y}) {
    return TextItem(
      id: id,
      content: content ?? this.content,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextItem &&
          id == other.id &&
          content == other.content &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(id, content, x, y);
}

/// 图片（不可变）。
class ImageItem {
  const ImageItem({
    required this.id,
    required this.mediaId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
  });

  final String id;
  final String mediaId;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;

  ImageItem copyWith({double? x, double? y, double? width, double? height, double? rotation}) {
    return ImageItem(
      id: id,
      mediaId: mediaId,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageItem &&
          id == other.id &&
          mediaId == other.mediaId &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(id, mediaId, x, y);
}

/// 图层（不可变）。
class LayerV2 {
  const LayerV2({
    required this.id,
    required this.name,
    this.strokes = const [],
    this.shapes = const [],
    this.texts = const [],
    this.images = const [],
    this.visible = true,
    this.opacity = 1.0,
  });

  final String id;
  final String name;
  final List<LineItem> strokes;
  final List<ShapeItem> shapes;
  final List<TextItem> texts;
  final List<ImageItem> images;
  final bool visible;
  final double opacity;

  LayerV2 copyWith({
    String? name,
    List<LineItem>? strokes,
    List<ShapeItem>? shapes,
    List<TextItem>? texts,
    List<ImageItem>? images,
    bool? visible,
    double? opacity,
  }) {
    return LayerV2(
      id: id,
      name: name ?? this.name,
      strokes: strokes ?? this.strokes,
      shapes: shapes ?? this.shapes,
      texts: texts ?? this.texts,
      images: images ?? this.images,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerV2 &&
          id == other.id &&
          name == other.name &&
          _listEquals(strokes, other.strokes) &&
          _listEquals(shapes, other.shapes) &&
          _listEquals(texts, other.texts) &&
          _listEquals(images, other.images) &&
          visible == other.visible &&
          opacity == other.opacity;

  @override
  int get hashCode => Object.hash(id, name, strokes, shapes, texts, images, visible, opacity);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
