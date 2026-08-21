// editor_core——LassoSelection 套索选择（Excalidraw 借鉴——2026-08-21）。
//
// Excalidraw Lasso Selection 本地化——多元素框选/套索选择。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - lasso/ 目录——套索选择实现
// - 支持矩形框选和自由曲线选择
// - 元素包含检测（bounds 交叉判定）
library;

import 'dart:math' as math;

/// 选择区域类型（Excalidraw lasso 模式借鉴）。
enum LassoType {
  /// 矩形框选（拖拽矩形区域）。
  rectangle,

  /// 自由曲线套索（自由绘制选择区域）。
  freeform,
}

/// 套索选择区域（Excalidraw Lasso 本地化——不可变）。
///
/// 矩形框选：由左上角和右下角定义。
/// 自由曲线：由一系列点定义（多边形近似）。
class LassoSelection {
  const LassoSelection({
    required this.type,
    required this.points,
  });

  /// 创建矩形框选。
  factory LassoSelection.rectangle(double x1, double y1, double x2, double y2) {
    return LassoSelection(
      type: LassoType.rectangle,
      points: [
        (x: x1, y: y1),
        (x: x2, y: y1),
        (x: x2, y: y2),
        (x: x1, y: y2),
      ],
    );
  }

  /// 创建自由曲线套索。
  factory LassoSelection.freeform(List<({double x, double y})> points) {
    return LassoSelection(
      type: LassoType.freeform,
      points: points,
    );
  }

  final LassoType type;
  final List<({double x, double y})> points;

  /// 选择区域是否为空。
  bool get isEmpty => points.length < 3;

  /// 边界框（用于快速预筛选）。
  ({double left, double top, double right, double bottom}) get bounds {
    if (points.isEmpty) return (left: 0, top: 0, right: 0, bottom: 0);
    var left = points.first.x;
    var top = points.first.y;
    var right = points.first.x;
    var bottom = points.first.y;
    for (final p in points) {
      if (p.x < left) left = p.x;
      if (p.y < top) top = p.y;
      if (p.x > right) right = p.x;
      if (p.y > bottom) bottom = p.y;
    }
    return (left: left, top: top, right: right, bottom: bottom);
  }

  /// 点是否在选择区域内（矩形框选——简单 bounds 检测）。
  bool containsPoint(double px, double py) {
    if (type == LassoType.rectangle) {
      final b = bounds;
      return px >= b.left && px <= b.right && py >= b.top && py <= b.bottom;
    }
    // 自由曲线：射线法（ray casting）判断点是否在多边形内。
    return _pointInPolygon(px, py, points);
  }

  /// 元素是否在选择区域内（bounds 交叉检测）。
  bool containsElement(double ex, double ey, double ew, double eh) {
    final b = bounds;
    // 快速预筛选：bounds 交叉。
    if (ex + ew < b.left || ex > b.right || ey + eh < b.top || ey > b.bottom) {
      return false;
    }
    // 矩形框选：bounds 完全包含。
    if (type == LassoType.rectangle) {
      return ex >= b.left && ex + ew <= b.right && ey >= b.top && ey + eh <= b.bottom;
    }
    // 自由曲线：检查元素中心点是否在区域内。
    return containsPoint(ex + ew / 2, ey + eh / 2);
  }

  /// 射线法判断点是否在多边形内（Excalidraw lasso 核心算法）。
  static bool _pointInPolygon(double px, double py, List<({double x, double y})> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].x, yi = polygon[i].y;
      final xj = polygon[j].x, yj = polygon[j].y;
      if ((yi > py) != (yj > py) &&
          px < (xj - xi) * (py - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LassoSelection && type == other.type && points.length == other.points.length;

  @override
  int get hashCode => Object.hash(type, points.length);
}
