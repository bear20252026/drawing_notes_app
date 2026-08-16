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

/// 几何引擎（直线几何的单一可信来源——专家 I-007）。
class GeometryEngine {
  const GeometryEngine._();

  /// 创建直线（端点规范化——包围盒由 [LineGeometry.bounds] 提供）。
  static LineGeometry line({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) => LineGeometry(x1: x1, y1: y1, x2: x2, y2: y2);
}
