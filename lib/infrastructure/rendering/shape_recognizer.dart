import 'dart:math' as math;
import 'dart:ui';

import '../../features/drawing/domain/shape_item.dart';
import '../../features/drawing/domain/stroke.dart';

/// 手绘闭合轮廓的轻量规则形状识别器。
///
/// 它刻意采用保守策略：只有高直线度的开放笔画，以及闭合、尺寸足够且
/// 几何误差较小的矩形、椭圆、菱形轮廓会转为规则形状；其余涂鸦和高亮笔
/// 均保留原状。
/// 该类不修改文档，因而可在控制器与单元测试中复用。
class ShapeRecognizer {
  const ShapeRecognizer._();

  static const double _minimumExtent = 18;
  static const double _closureRatio = 0.16;
  static const double _maxEllipseRadialError = 0.16;

  // Q-6 修复（专家审查 2026-08-15）：识别阈值提取命名常量（原魔法数字）。
  static const double _strokeWidthClosureFactor = 2.4; // 闭合距离上限系数
  static const double _rectPerimeterMin = 0.88; // 矩形周长比下限
  static const double _rectPerimeterMax = 1.32; // 矩形周长比上限
  static const double _maxRectEdgeDistance = 0.055; // 矩形贴合阈值（×对角线）
  static const double _diamondPerimeterMin = 0.58; // 菱形周长比下限
  static const double _diamondPerimeterMax = 0.75; // 菱形周长比上限
  static const double _maxDiamondEdgeDistance = 0.06; // 菱形贴合阈值（×对角线）
  static const double _ellipsePerimeterMin = 0.60; // 椭圆周长比下限
  static const double _ellipsePerimeterMax = 0.94; // 椭圆周长比上限

  static RecognizedShape? recognize(Stroke stroke) {
    if (stroke.type != BrushType.pen && stroke.type != BrushType.pencil) {
      return null;
    }
    final points = stroke.points;
    if (points.length < 2) return null;

    final line = _recognizeLine(points, stroke.width);
    if (line != null) return line;

    // 四个顶点加上回到起点的闭合采样即可表达最简手绘矩形。
    if (points.length < 5) return null;

    final bounds = _boundsFor(points);
    if (bounds.width < _minimumExtent || bounds.height < _minimumExtent) {
      return null;
    }

    final diagonal = math.sqrt(
      bounds.width * bounds.width + bounds.height * bounds.height,
    );
    final closureDistance = (points.first.offset - points.last.offset).distance;
    if (closureDistance >
        math.max(stroke.width * _strokeWidthClosureFactor, diagonal * _closureRatio)) {
      return null;
    }

    final pathLength = _pathLength(points);
    final boxPerimeter = 2 * (bounds.width + bounds.height);
    final perimeterRatio = pathLength / boxPerimeter;

    // 矩形沿外接框四条边行进，路径长度接近盒周长；椭圆则显著更短。
    if (perimeterRatio >= _rectPerimeterMin &&
        perimeterRatio <= _rectPerimeterMax &&
        _meanDistanceToBoxEdge(points, bounds) <= diagonal * _maxRectEdgeDistance &&
        _hasCornerEvidence(points, bounds)) {
      return RecognizedShape(ShapeType.rect, bounds);
    }

    final ellipseError = _meanEllipseRadialError(points, bounds);
    // 椭圆同样经过上下左右四个极值点；仅凭菱形顶点证据会产生误判。
    // 菱形路径通常显著短于椭圆路径，因此同时收紧其外接框周长比。
    if (perimeterRatio >= _diamondPerimeterMin &&
        perimeterRatio <= _diamondPerimeterMax &&
        _meanDistanceToDiamondEdge(points, bounds) <= diagonal * _maxDiamondEdgeDistance &&
        _hasDiamondCornerEvidence(points, bounds)) {
      return RecognizedShape(ShapeType.diamond, bounds);
    }

    if (perimeterRatio >= _ellipsePerimeterMin &&
        perimeterRatio <= _ellipsePerimeterMax &&
        ellipseError <= _maxEllipseRadialError) {
      return RecognizedShape(ShapeType.ellipse, bounds);
    }
    return null;
  }

  static RecognizedShape? _recognizeLine(
    List<StrokePoint> points,
    double strokeWidth,
  ) {
    // 单次拖动通常只产生两个端点，应保留为普通手写笔画；至少四个连续
    // 采样才视为用户有意手绘直线，降低日常书写被过度转换的概率。
    if (points.length < 4) return null;
    final start = points.first.offset;
    final end = points.last.offset;
    final length = (end - start).distance;
    if (length < _minimumExtent) return null;

    final tolerance = math.max(strokeWidth * 1.8, length * 0.045);
    final maxDeviation = points
        .map((point) => _distanceToSegment(point.offset, start, end))
        .reduce(math.max);
    if (maxDeviation > tolerance) return null;

    final bounds = _boundsFor(points);
    // 直线形状仍需要非零外接框，避免后续选择手柄和序列化出现退化尺寸。
    final normalized = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      math.max(2, bounds.width),
      math.max(2, bounds.height),
    );
    // 保存真实端点（相对外接框左上角），修复"从左往右画却生成
    // 反向/斜线"的问题（对齐 Saber shape_pen.convertToLine）。
    // flipX/flipY 不再用于线性元素的方向表达，改为 false。
    final lineStart = start - normalized.topLeft;
    final lineEnd = end - normalized.topLeft;
    return RecognizedShape(
      ShapeType.line,
      normalized,
      lineStart: lineStart,
      lineEnd: lineEnd,
    );
  }

  static Rect _boundsFor(List<StrokePoint> points) {
    var left = points.first.x;
    var right = left;
    var top = points.first.y;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.x);
      right = math.max(right, point.x);
      top = math.min(top, point.y);
      bottom = math.max(bottom, point.y);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static double _pathLength(List<StrokePoint> points) {
    var length = 0.0;
    for (var index = 1; index < points.length; index++) {
      length += (points[index].offset - points[index - 1].offset).distance;
    }
    return length;
  }

  static double _meanDistanceToBoxEdge(List<StrokePoint> points, Rect bounds) {
    var sum = 0.0;
    for (final point in points) {
      sum += math.min(
        math.min((point.x - bounds.left).abs(), (bounds.right - point.x).abs()),
        math.min((point.y - bounds.top).abs(), (bounds.bottom - point.y).abs()),
      );
    }
    return sum / points.length;
  }

  static double _meanDistanceToDiamondEdge(
    List<StrokePoint> points,
    Rect bounds,
  ) {
    final vertices = <Offset>[
      Offset(bounds.center.dx, bounds.top),
      Offset(bounds.right, bounds.center.dy),
      Offset(bounds.center.dx, bounds.bottom),
      Offset(bounds.left, bounds.center.dy),
    ];
    var sum = 0.0;
    for (final point in points) {
      var nearest = double.infinity;
      for (var index = 0; index < vertices.length; index++) {
        nearest = math.min(
          nearest,
          _distanceToSegment(
            point.offset,
            vertices[index],
            vertices[(index + 1) % vertices.length],
          ),
        );
      }
      sum += nearest;
    }
    return sum / points.length;
  }

  static bool _hasDiamondCornerEvidence(List<StrokePoint> points, Rect bounds) {
    final tolerance = math.min(bounds.width, bounds.height) * 0.2;
    final corners = <Offset>[
      Offset(bounds.center.dx, bounds.top),
      Offset(bounds.right, bounds.center.dy),
      Offset(bounds.center.dx, bounds.bottom),
      Offset(bounds.left, bounds.center.dy),
    ];
    return corners.every(
      (corner) =>
          points.any((point) => (point.offset - corner).distance <= tolerance),
    );
  }

  static bool _hasCornerEvidence(List<StrokePoint> points, Rect bounds) {
    final tolerance = math.min(bounds.width, bounds.height) * 0.18;
    final corners = <Offset>[
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ];
    // 允许轻微手抖，但要求四个转角附近均有采样，避免将菱形或涂鸦误识别。
    return corners.every(
      (corner) =>
          points.any((point) => (point.offset - corner).distance <= tolerance),
    );
  }

  static double _distanceToSegment(Offset point, Offset a, Offset b) {
    final segment = b - a;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    if (lengthSquared <= 1e-8) return (point - a).distance;
    final projection =
        ((point - a).dx * segment.dx + (point - a).dy * segment.dy) /
        lengthSquared;
    final t = projection.clamp(0.0, 1.0);
    return (point - (a + segment * t)).distance;
  }

  static double _meanEllipseRadialError(List<StrokePoint> points, Rect bounds) {
    final center = bounds.center;
    final rx = bounds.width / 2;
    final ry = bounds.height / 2;
    var sum = 0.0;
    for (final point in points) {
      final nx = (point.x - center.dx) / rx;
      final ny = (point.y - center.dy) / ry;
      sum += (math.sqrt(nx * nx + ny * ny) - 1).abs();
    }
    return sum / points.length;
  }
}

/// 识别完成后交由编辑器转换为可编辑 [PageShapeItem] 的纯几何结果。
class RecognizedShape {
  const RecognizedShape(
    this.type,
    this.bounds, {
    this.flipX = false,
    this.flipY = false,
    this.lineStart,
    this.lineEnd,
  });

  final ShapeType type;
  final Rect bounds;
  final bool flipX;
  final bool flipY;

  /// 线性元素的真实端点（相对 [bounds] 左上角），用于修复
  /// 直线/箭头方向与鼠标轨迹不一致的问题。
  final Offset? lineStart;
  final Offset? lineEnd;
}
