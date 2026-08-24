// editor_core——V2 领域模型扩展（批次 C——2026-08-18——专家方案）。
//
// 为 DocumentReducer 提供 V2 不可变领域模型：
// - LayerV2（图层——不可变）
// - ShapeItem（形状——不可变）
// - TextItem（文本——不可变）
// - LineItem（笔画——不可变）
// - Point（点——不可变）
// - TableV2（数据库表格——AFFiNE 借鉴——不可变）
// - NoteItem（便签块——AFFiNE 借鉴——不可变）
library;

import 'note_item.dart';
import 'table_v2.dart';

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
    this.strokeWidth = 2.0,
    this.color = '#000000',
    this.opacity = 1.0,
  });

  final String id;
  final List<Point> points;

  /// 笔画宽度（V1/V2 迁移阶段1——2026-08-24）。
  final double strokeWidth;

  /// 笔画颜色（#RRGGBB——V1/V2 迁移阶段1——2026-08-24）。
  final String color;

  /// 笔画不透明度（0.0~1.0——V1/V2 迁移阶段1——2026-08-24）。
  final double opacity;

  LineItem copyWith({List<Point>? points, double? strokeWidth, String? color, double? opacity}) {
    return LineItem(
      id: id,
      points: points ?? this.points,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineItem &&
          id == other.id &&
          strokeWidth == other.strokeWidth &&
          color == other.color &&
          opacity == other.opacity &&
          _listEquals(points, other.points);

  @override
  int get hashCode => Object.hash(id, strokeWidth, color, opacity, points);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 序列化为 JSON 映射。
  Map<String, dynamic> toJson() => {
        'id': id,
        'points': points.map((p) => {'x': p.x, 'y': p.y}).toList(),
        'strokeWidth': strokeWidth,
        'color': color,
        'opacity': opacity,
      };

  /// 从 JSON 映射反序列化。
  static LineItem fromJson(Map<String, dynamic> json) => LineItem(
        id: json['id'] as String,
        points: (json['points'] as List<dynamic>)
            .map((e) => Point((e['x'] as num).toDouble(), (e['y'] as num).toDouble()))
            .toList(),
        strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
        color: (json['color'] as String?) ?? '#000000',
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      );
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
    this.strokeColor = '#000000',
    this.fillColor = '#CCCCCC',
  });

  final String id;
  final String type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;

  /// 描边颜色（#RRGGBB）。
  final String strokeColor;

  /// 填充颜色（#RRGGBB）。
  final String fillColor;

  ShapeItem copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    String? strokeColor,
    String? fillColor,
  }) {
    return ShapeItem(
      id: id,
      type: type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      strokeColor: strokeColor ?? this.strokeColor,
      fillColor: fillColor ?? this.fillColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShapeItem &&
          id == other.id &&
          type == other.type &&
          x == other.x &&
          y == other.y &&
          strokeColor == other.strokeColor &&
          fillColor == other.fillColor;

  @override
  int get hashCode => Object.hash(id, type, x, y, strokeColor, fillColor);

  /// 序列化为 JSON 映射。
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotation': rotation,
        'strokeColor': strokeColor,
        'fillColor': fillColor,
      };

  /// 从 JSON 映射反序列化。
  static ShapeItem fromJson(Map<String, dynamic> json) => ShapeItem(
        id: json['id'] as String,
        type: json['type'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        strokeColor: (json['strokeColor'] as String?) ?? '#000000',
        fillColor: (json['fillColor'] as String?) ?? '#CCCCCC',
      );
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

  /// 序列化为 JSON 映射。
  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'x': x,
        'y': y,
      };

  /// 从 JSON 映射反序列化。
  static TextItem fromJson(Map<String, dynamic> json) => TextItem(
        id: json['id'] as String,
        content: json['content'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );
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

  /// 序列化为 JSON 映射。
  Map<String, dynamic> toJson() => {
        'id': id,
        'mediaId': mediaId,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotation': rotation,
      };

  /// 从 JSON 映射反序列化。
  static ImageItem fromJson(Map<String, dynamic> json) => ImageItem(
        id: json['id'] as String,
        mediaId: json['mediaId'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      );
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
    this.tables = const [],
    this.notes = const [],
    this.visible = true,
    this.opacity = 1.0,
  });

  final String id;
  final String name;
  final List<LineItem> strokes;
  final List<ShapeItem> shapes;
  final List<TextItem> texts;
  final List<ImageItem> images;

  /// 数据库表格（AFFiNE 借鉴——表格块——不可变）。
  final List<TableV2> tables;

  /// 便签块（AFFiNE 借鉴——sticky note——不可变）。
  final List<NoteItem> notes;
  final bool visible;
  final double opacity;

  LayerV2 copyWith({
    String? name,
    List<LineItem>? strokes,
    List<ShapeItem>? shapes,
    List<TextItem>? texts,
    List<ImageItem>? images,
    List<TableV2>? tables,
    List<NoteItem>? notes,
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
      tables: tables ?? this.tables,
      notes: notes ?? this.notes,
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
          _listEquals(tables, other.tables) &&
          _listEquals(notes, other.notes) &&
          visible == other.visible &&
          opacity == other.opacity;

  @override
  int get hashCode => Object.hash(id, name, strokes, shapes, texts, images, tables, notes, visible, opacity);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 序列化为 JSON 映射。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'shapes': shapes.map((s) => s.toJson()).toList(),
        'texts': texts.map((t) => t.toJson()).toList(),
        'images': images.map((i) => i.toJson()).toList(),
        'tables': tables.map((t) => t.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
        'visible': visible,
        'opacity': opacity,
      };

  /// 从 JSON 映射反序列化。
  static LayerV2 fromJson(Map<String, dynamic> json) => LayerV2(
        id: json['id'] as String,
        name: json['name'] as String,
        strokes: (json['strokes'] as List<dynamic>)
            .map((e) => LineItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        shapes: (json['shapes'] as List<dynamic>)
            .map((e) => ShapeItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        texts: (json['texts'] as List<dynamic>)
            .map((e) => TextItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        images: (json['images'] as List<dynamic>)
            .map((e) => ImageItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        tables: (json['tables'] as List<dynamic>)
            .map((e) => TableV2.fromJson(e as Map<String, dynamic>))
            .toList(),
        notes: (json['notes'] as List<dynamic>)
            .map((e) => NoteItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        visible: (json['visible'] as bool?) ?? true,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      );
}
