// editor_core——GeometryEngine（专家 I-007——2026-08-16——批次 B）。
//
// 唯一负责直线/箭头/矩形/椭圆几何（端点/包围盒/命中/预览/导出
// primitives——专家"UI 与核心 renderer 的直线/箭头端点实现重复且已
// 产生功能缺陷——唯一负责几何"）。纯 Dart——禁 Flutter/dart:io。
//
// 批次 B 最小：直线端点/包围盒/四象限方向参数化/点到线段距离——
// 接管直线几何（旧 ShapePainter/ShapeRenderer 后续调用同一引擎）。

import 'dart:math' as math;

/// 直线几何（端点 + 四象限方向参数化——纯 Dart——无 dart:ui 依赖）。
class LineGeometry {
  const LineGeometry({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// 外接包围盒（命中/导出 primitives 用）。
  ({double left, double top, double right, double bottom}) get bounds {
    final left = math.min(x1, x2);
    final top = math.min(y1, y2);
    final right = math.max(x1, x2);
    final bottom = math.max(y1, y2);
    return (left: left, top: top, right: right, bottom: bottom);
  }

  /// 四象限方向（1: 右上 ↗ 2: 右下 ↘ 3: 左下 ↙ 4: 左上 ↖——
  /// dx/dy 符号组合——专家四象限 golden tests 基准）。
  int get quadrant {
    final dx = x2 - x1;
    final dy = y2 - y1;
    if (dx >= 0 && dy < 0) return 1;
    if (dx >= 0 && dy >= 0) return 2;
    if (dx < 0 && dy >= 0) return 3;
    return 4;
  }

  /// 点到线段距离（投影 t + clamp 0-1——权威算法——橡皮擦/命中判定
  /// 基础——tldraw DistanceToLineSegment 同源）。
  double distanceTo(double px, double py) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 1e-8) {
      return math.sqrt((px - x1) * (px - x1) + (py - y1) * (py - y1));
    }
    final t = (((px - x1) * dx + (py - y1) * dy) / lengthSquared).clamp(0.0, 1.0);
    final projX = x1 + t * dx;
    final projY = y1 + t * dy;
    return math.sqrt((px - projX) * (px - projX) + (py - projY) * (py - projY));
  }
}

/// 矩形几何（x,y 为左上角，宽高正数——纯 Dart）。
class RectangleGeometry {
  const RectangleGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;

  /// 外接包围盒（命中/导出 primitives 用）。
  ({double left, double top, double right, double bottom}) get bounds {
    return (left: x, top: y, right: x + width, bottom: y + height);
  }

  /// 面积。
  double get area => width * height;

  /// 中心点。
  ({double x, double y}) get center => (x: x + width / 2, y: y + height / 2);

  /// 点是否在矩形内（不含旋转）。
  bool containsPoint(double px, double py) {
    return px >= x && px <= x + width && py >= y && py <= y + height;
  }

  /// 点到矩形边的距离（不含旋转）。
  double distanceToEdge(double px, double py) {
    // 点在矩形内：到最近边的距离
    if (containsPoint(px, py)) {
      final left = px - x;
      final right = x + width - px;
      final top = py - y;
      final bottom = y + height - py;
      return [left, right, top, bottom].reduce((a, b) => a < b ? a : b);
    }
    // 点在矩形外：到最近边的距离
    final dx = (px < x) ? (x - px) : (px > x + width ? px - (x + width) : 0);
    final dy = (py < y) ? (y - py) : (py > y + height ? py - (y + height) : 0);
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// 椭圆几何（cx,cy 为中心，rx,ry 为半轴——纯 Dart）。
class EllipseGeometry {
  const EllipseGeometry({
    required this.cx,
    required this.cy,
    required this.rx,
    required this.ry,
  });

  final double cx;
  final double cy;
  final double rx;
  final double ry;

  /// 外接包围盒（命中/导出 primitives 用）。
  ({double left, double top, double right, double bottom}) get bounds {
    return (left: cx - rx, top: cy - ry, right: cx + rx, bottom: cy + ry);
  }

  /// 面积。
  double get area => math.pi * rx * ry;

  /// 点是否在椭圆内。
  bool containsPoint(double px, double py) {
    final dx = (px - cx) / rx;
    final dy = (py - cy) / ry;
    return dx * dx + dy * dy <= 1;
  }

  /// 点到椭圆边的近似距离（中心到点减半径——近似）。
  double distanceToCenter(double px, double py) {
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  /// 点到椭圆边的近似距离（中心距离 - 半径）。
  double distanceToEdge(double px, double py) {
    final d = distanceToCenter(px, py);
    // 近似：假设椭圆近似圆（对 rx≈ry 准确）
    final r = (rx + ry) / 2;
    return (d - r).abs();
  }
}

/// 箭头几何（端点 + 箭头参数——纯 Dart）。
class ArrowGeometry {
  const ArrowGeometry({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.headLength = 10,
    this.headWidth = 10,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double headLength;
  final double headWidth;

  /// 外接包围盒（命中/导出 primitives 用）。
  ({double left, double top, double right, double bottom}) get bounds {
    final left = math.min(x1, x2) - headWidth;
    final top = math.min(y1, y2) - headWidth;
    final right = math.max(x1, x2) + headWidth;
    final bottom = math.max(y1, y2) + headWidth;
    return (left: left, top: top, right: right, bottom: bottom);
  }

  /// 点到线段距离（投影 t + clamp——权威算法）。
  double distanceToLine(double px, double py) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 1e-8) {
      return math.sqrt((px - x1) * (px - x1) + (py - y1) * (py - y1));
    }
    final t = (((px - x1) * dx + (py - y1) * dy) / lengthSquared).clamp(0.0, 1.0);
    final projX = x1 + t * dx;
    final projY = y1 + t * dy;
    return math.sqrt((px - projX) * (px - projX) + (py - projY) * (py - projY));
  }

  /// 箭头方向（弧度）。
  double get direction => math.atan2(y2 - y1, x2 - x1);
}

/// 几何引擎（直线/矩形/椭圆/箭头几何的单一可信来源——专家 I-007）。
class GeometryEngine {
  const GeometryEngine();

  /// 创建直线。
  static LineGeometry line({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) => LineGeometry(x1: x1, y1: y1, x2: x2, y2: y2);

  /// 创建矩形。
  static RectangleGeometry rectangle({
    required double x,
    required double y,
    required double width,
    required double height,
    double rotation = 0,
  }) => RectangleGeometry(x: x, y: y, width: width, height: height, rotation: rotation);

  /// 创建椭圆。
  static EllipseGeometry ellipse({
    required double cx,
    required double cy,
    required double rx,
    required double ry,
  }) => EllipseGeometry(cx: cx, cy: cy, rx: rx, ry: ry);

  /// 创建箭头。
  static ArrowGeometry arrow({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    double headLength = 10,
    double headWidth = 10,
  }) => ArrowGeometry(x1: x1, y1: y1, x2: x2, y2: y2, headLength: headLength, headWidth: headWidth);
}
