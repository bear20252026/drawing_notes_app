import 'dart:math' as math;
import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/domain/shape_endpoint_binding.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';

/// 独立绘图文档中直线箭头的绑定几何。
///
/// 本类不依赖控制器、画布或存储，可用作创建、对象变换、导出前校正和回归测试
/// 的唯一几何真相。第一版支持矩形外接框上的归一化锚点；椭圆/菱形的精确边界
/// 吸附留给后续版本，避免以不可靠的近似破坏对象关系不变量。
class ShapeBindingGeometry {
  const ShapeBindingGeometry._();

  static bool isBindable(PageShapeItem shape) =>
      shape.shapeType == ShapeType.rect ||
      shape.shapeType == ShapeType.ellipse ||
      shape.shapeType == ShapeType.diamond;

  static Rect rawBounds(PageShapeItem shape) =>
      Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);

  /// 在给定点命中最上层可绑定形状。箭头本身不作为目标，避免新建箭头
  /// 意外绑定到自身；同层元素按集合后序视作更靠上，符合现有渲染顺序。
  static PageShapeItem? bindableShapeAt(
    Offset point,
    Iterable<PageShapeItem> shapes, {
    String? excludingId,
  }) {
    final candidates =
        shapes
            .where((shape) => shape.id != excludingId && isBindable(shape))
            .toList()
          ..sort((a, b) => a.zOrder.compareTo(b.zOrder));
    for (final shape in candidates.reversed) {
      if (rawBounds(shape).contains(point)) return shape;
    }
    return null;
  }

  /// 由画布上的点创建相对目标 bounds 的稳定锚点。
  static ShapeEndpointBinding bindingAt(PageShapeItem target, Offset point) {
    final bounds = rawBounds(target);
    final anchorX = bounds.width <= 0
        ? 0.5
        : (point.dx - bounds.left) / bounds.width;
    final anchorY = bounds.height <= 0
        ? 0.5
        : (point.dy - bounds.top) / bounds.height;
    return ShapeEndpointBinding(
      targetShapeId: target.id,
      anchorX: anchorX,
      anchorY: anchorY,
    );
  }

  /// 把归一化锚点投影到目标的最新外接框。
  static Offset projectBinding(
    ShapeEndpointBinding binding,
    Iterable<PageShapeItem> shapes,
  ) {
    final target = shapes
        .where((shape) => shape.id == binding.targetShapeId)
        .firstOrNull;
    if (target == null || !isBindable(target)) {
      throw StateError('绑定目标不存在或不可绑定：${binding.targetShapeId}');
    }
    final bounds = rawBounds(target);
    return Offset(
      bounds.left + bounds.width * binding.anchorX,
      bounds.top + bounds.height * binding.anchorY,
    );
  }

  /// 当前箭头的可见全局端点，正确处理既有翻转和旋转。
  static ({Offset start, Offset end}) arrowEndpoints(PageShapeItem arrow) {
    assert(arrow.shapeType == ShapeType.arrow);
    final start = _localToGlobal(arrow, Offset(0, arrow.height));
    final end = _localToGlobal(arrow, Offset(arrow.width, 0));
    return (start: start, end: end);
  }

  /// 取得应用绑定后的可见端点。缺失/损坏绑定安全回退至现有自由端点，
  /// 保证旧文档、已删除目标和离线恢复不会让画布崩溃。
  static ({Offset start, Offset end}) resolvedArrowEndpoints(
    PageShapeItem arrow,
    Iterable<PageShapeItem> shapes,
  ) {
    final fallback = arrowEndpoints(arrow);
    Offset resolve(ShapeEndpointBinding? binding, Offset fallbackPoint) {
      if (binding == null) return fallbackPoint;
      try {
        return projectBinding(binding, shapes);
      } on StateError {
        return fallbackPoint;
      }
    }

    return (
      start: resolve(arrow.startBinding, fallback.start),
      end: resolve(arrow.endBinding, fallback.end),
    );
  }

  /// 将箭头重写为表示指定全局端点的现有 `x/y/width/height/flip` 规范格式。
  /// 旋转在此基础上会引入语义歧义，绑定箭头第一版固定清除 rotation；这比同时
  /// 保存旋转和错误投影端点更安全，也与目前箭头创建行为一致。
  static void applyArrowEndpoints(
    PageShapeItem arrow, {
    required Offset start,
    required Offset end,
  }) {
    assert(arrow.shapeType == ShapeType.arrow);
    final width = math.max((end.dx - start.dx).abs(), 1.0);
    final height = math.max((end.dy - start.dy).abs(), 1.0);
    arrow
      ..x = math.min(start.dx, end.dx)
      ..y = math.min(start.dy, end.dy)
      ..width = width
      ..height = height
      ..flipX = end.dx < start.dx
      ..flipY = end.dy > start.dy
      ..rotation = 0;
  }

  /// 建立新箭头两端的绑定关系，并把它立即规范化为绑定后的可见端点。
  ///
  /// 任一端在空白处释放时仍保留为自由端点，因此用户可画出“形状 → 空白”
  /// 的待连接箭头；这是关系图编辑中必要的渐进状态。
  static void bindArrowAtEndpoints(
    PageShapeItem arrow,
    Iterable<PageShapeItem> shapes, {
    required Offset start,
    required Offset end,
  }) {
    assert(arrow.shapeType == ShapeType.arrow);
    final startTarget = bindableShapeAt(start, shapes, excludingId: arrow.id);
    final endTarget = bindableShapeAt(end, shapes, excludingId: arrow.id);
    arrow
      ..startBinding = startTarget == null
          ? null
          : bindingAt(startTarget, start)
      ..endBinding = endTarget == null ? null : bindingAt(endTarget, end);
    // 新建时自由端的几何真相就是手势释放点；不能调用现有 arrow 的占位端点。
    final resolvedStart = startTarget == null
        ? start
        : projectBinding(arrow.startBinding!, shapes);
    final resolvedEnd = endTarget == null
        ? end
        : projectBinding(arrow.endBinding!, shapes);
    applyArrowEndpoints(arrow, start: resolvedStart, end: resolvedEnd);
  }

  /// 重新投影箭头的所有有效绑定端点，并在至少一个端点变化时返回 true。
  static bool reprojectArrow(
    PageShapeItem arrow,
    Iterable<PageShapeItem> shapes,
  ) {
    if (arrow.shapeType != ShapeType.arrow) {
      return false;
    }
    final before = arrowEndpoints(arrow);
    final resolved = resolvedArrowEndpoints(arrow, shapes);
    if (before.start == resolved.start && before.end == resolved.end) {
      return false;
    }
    applyArrowEndpoints(arrow, start: resolved.start, end: resolved.end);
    return true;
  }

  static Offset _localToGlobal(PageShapeItem shape, Offset local) {
    final center = Offset(shape.width / 2, shape.height / 2);
    final scaled = Offset(
      shape.flipX ? 2 * center.dx - local.dx : local.dx,
      shape.flipY ? 2 * center.dy - local.dy : local.dy,
    );
    final delta = scaled - center;
    final cosAngle = math.cos(shape.rotation);
    final sinAngle = math.sin(shape.rotation);
    final rotated = Offset(
      delta.dx * cosAngle - delta.dy * sinAngle,
      delta.dx * sinAngle + delta.dy * cosAngle,
    );
    return Offset(shape.x + center.dx, shape.y + center.dy) + rotated;
  }
}
