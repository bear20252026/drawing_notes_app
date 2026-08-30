// M11 无限画布元素扩展：笔迹（brush stroke）与形状（shape）。
//
// 对标 AFFiNE Edgeless 的 brush 元素与 shape 元素（矩形/椭圆）：
// 以世界坐标存储，随 EdgelessDoc 序列化持久化。纯 Dart，无 Flutter 依赖。
//
// 注意：points 用扁平 List<double>（x,y 交替）以减小序列化体积。
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// 形状种类（对标 AFFiNE shape 工具的矩形/椭圆）。
enum EdgelessShapeKind { rect, ellipse }

/// 笔迹：世界坐标点列 + 颜色/宽度。不可变，追加点用 [copyWithAppended]。
class EdgelessStroke {
  const EdgelessStroke({
    required this.id,
    required this.points,
    required this.color,
    required this.width,
  });

  /// 唯一标识。
  final String id;

  /// 世界坐标点列（扁平存储：x0,y0,x1,y1,...）。
  final List<double> points;

  /// 颜色（CSS 颜色字符串）。
  final String color;

  /// 线宽（世界坐标单位）。
  final double width;

  int get pointCount => points.length ~/ 2;

  Offset pointAt(int i) => Offset(points[i * 2], points[i * 2 + 1]);

  /// 追加一个点，返回新实例（原始列表不变）。
  EdgelessStroke copyWithAppended(Offset p) => EdgelessStroke(
    id: id,
    points: [...points, p.dx, p.dy],
    color: color,
    width: width,
  );

  /// 命中测试：世界点 [worldPoint] 到任一线段的距离 <= [tolerance]。
  bool hitTest(Offset worldPoint, {double tolerance = 6.0}) {
    if (pointCount < 2) {
      if (pointCount == 1) {
        return (pointAt(0) - worldPoint).distance <= tolerance;
      }
      return false;
    }
    for (var i = 0; i < pointCount - 1; i++) {
      if (_distanceToSegment(worldPoint, pointAt(i), pointAt(i + 1)) <=
          tolerance) {
        return true;
      }
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    final t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
    final clamped = t.clamp(0.0, 1.0).toDouble();
    final proj = Offset(a.dx + ab.dx * clamped, a.dy + ab.dy * clamped);
    return (p - proj).distance;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'points': points,
    'color': color,
    'width': width,
  };

  factory EdgelessStroke.fromJson(Map<String, dynamic> json) => EdgelessStroke(
    id: json['id'] as String,
    points: (json['points'] as List? ?? const [])
        .map((e) => (e as num).toDouble())
        .toList(),
    color: json['color'] as String? ?? '#1D1D1F',
    width: (json['width'] as num?)?.toDouble() ?? 3.0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgelessStroke &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          _listEquals(points, other.points) &&
          color == other.color &&
          width == width;

  @override
  int get hashCode => Object.hash(id, Object.hashAll(points), color, width);

  @override
  String toString() =>
      'EdgelessStroke($id, ${pointCount}pts, $color, w=$width)';
}

bool _listEquals(List<double> a, List<double> b) {
  if (identical(a, b) || a.length != b.length) return a.length == b.length;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 形状：世界坐标矩形区域 + 种类/颜色。不可变。
class EdgelessShape {
  const EdgelessShape({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.kind,
    required this.color,
  });

  final String id;
  final double x;
  final double y;
  final double w;
  final double h;
  final EdgelessShapeKind kind;

  /// 填充色（CSS 颜色字符串，含透明度如 '#3366CC'）。
  final String color;

  Rect get rect => Rect.fromLTWH(x, y, w, h);

  bool contains(Offset worldPoint) => rect.contains(worldPoint);

  EdgelessShape copyWith({double? x, double? y, double? w, double? h}) =>
      EdgelessShape(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        kind: kind,
        color: color,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'kind': kind.name,
    'color': color,
  };

  factory EdgelessShape.fromJson(Map<String, dynamic> json) => EdgelessShape(
    id: json['id'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    w: (json['w'] as num).toDouble(),
    h: (json['h'] as num).toDouble(),
    kind: EdgelessShapeKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => EdgelessShapeKind.rect,
    ),
    color: json['color'] as String? ?? '#0066CC',
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgelessShape &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          x == other.x &&
          y == other.y &&
          w == other.w &&
          h == other.h &&
          kind == other.kind &&
          color == other.color;

  @override
  int get hashCode => Object.hash(id, x, y, w, h, kind, color);

  @override
  String toString() =>
      'EdgelessShape($id, ${kind.name}, ${math.max(w, 0)}x${math.max(h, 0)})';
}
