import 'dart:math' as math;
import 'dart:ui';

import 'package:drawing_notes_app/core/canvas_model/shape_endpoint_binding.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';

/// 独立绘图文档中直线箭头的绑定几何。
///
/// 本类不依赖控制器、画布或存储，可用作创建、对象变换、导出前校正和回归测试
/// 的唯一几何真相。第一版支持矩形外接框上的归一化锚点；椭圆/菱形的精确边界
/// 吸附留给后续版本，避免以不可靠的近似破坏对象关系不变量。
class ShapeBindingGeometry {
  const ShapeBindingGeometry._();

  /// 端点磁吸容差（画布坐标，审计二-3）：端点距目标外接框 ≤ 该值即吸附，
  /// 同时替代旧「按中心 50px」判定，修掉大形状边缘绑不上/小形状被抢绑的问题。
  static const double endpointSnapTolerance = 8;

  /// 线性元素命中带宽（画布坐标）：点到线段距离 ≤ 线宽/2 + 该值才算命中
  /// （审计二-5：外接框只留给封闭形状）。
  static const double linearHitSlack = 6;

  /// 角度吸附容差（度）：偏离 0°/45°/90° 在该范围内自动磁吸。
  /// 审计二-1 建议 ±3~5°，取上限 5°——触屏手指抖动幅度大于鼠标。
  static const double angleSnapToleranceDegrees = 5;

  /// 网格吸附步长（画布坐标），与编辑器拖动吸附/网格绘制共用 20px。
  static const double gridSnapStep = 20;

  /// 把拖拽终点磁吸到最近的 45° 整数倍方向（0/45/90/135…）。
  ///
  /// 落在 [anchor]→[end] 连线与最近吸附方向夹角小于 [toleranceDegrees]
  /// （或 [force]，桌面 Shift 键）时，把终点投影到该方向射线上，保持
  /// 原长度不变——这是「画得直」的核心修正（审计二-1）。
  static Offset snapDragAngle(
    Offset anchor,
    Offset end, {
    double toleranceDegrees = angleSnapToleranceDegrees,
    bool force = false,
  }) {
    final delta = end - anchor;
    final length = delta.distance;
    if (length < 1e-6) return end;
    final angleDeg = delta.direction * 180 / math.pi;
    final snappedDeg = (angleDeg / 45).roundToDouble() * 45;
    final deviation = (angleDeg - snappedDeg).abs();
    if (!force && deviation > toleranceDegrees) return end;
    if (deviation < 1e-9) return end;
    final radians = snappedDeg * math.pi / 180;
    return anchor + Offset(math.cos(radians), math.sin(radians)) * length;
  }

  /// 网格吸附：把点对齐到 [step] 网格（审计二-2/三-4：网格作为吸附档位）。
  static Offset snapToGrid(Offset point, double step) {
    if (step <= 0) return point;
    return Offset(
      (point.dx / step).roundToDouble() * step,
      (point.dy / step).roundToDouble() * step,
    );
  }

  static bool isBindable(PageShapeItem shape) =>
      shape.shapeType == ShapeType.rect ||
      shape.shapeType == ShapeType.ellipse ||
      shape.shapeType == ShapeType.diamond;

  static bool isLinear(PageShapeItem shape) => isLinearByType(shape.shapeType);

  static bool isLinearByType(ShapeType type) =>
      type == ShapeType.line || type == ShapeType.arrow;

  static Rect rawBounds(PageShapeItem shape) =>
      Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);

  /// 点到矩形的距离（点在矩形内部为 0）。
  static double distanceToBounds(Offset point, Rect bounds) {
    final dx = point.dx.clamp(bounds.left, bounds.right) - point.dx;
    final dy = point.dy.clamp(bounds.top, bounds.bottom) - point.dy;
    return Offset(dx, dy).distance;
  }

  /// 把点投影到矩形周界上最近的位置。
  ///
  /// 外部点 → 最近边上的垂足/角点；内部点 → 推到最近边。绑定时刻把端点
  /// 重投影到目标边上（审计二-3/二-4：消掉箭头尖与目标之间的视觉缝）。
  static Offset projectPointToBounds(Offset point, Rect bounds) {
    if (!bounds.contains(point)) {
      return Offset(
        point.dx.clamp(bounds.left, bounds.right),
        point.dy.clamp(bounds.top, bounds.bottom),
      );
    }
    // 内部点：到四边的距离取最小，移动到对应边上。
    final toLeft = (point.dx - bounds.left).abs();
    final toRight = (bounds.right - point.dx).abs();
    final toTop = (point.dy - bounds.top).abs();
    final toBottom = (bounds.bottom - point.dy).abs();
    final min = math.min(math.min(toLeft, toRight), math.min(toTop, toBottom));
    if (min == toLeft) return Offset(bounds.left, point.dy);
    if (min == toRight) return Offset(bounds.right, point.dy);
    if (min == toTop) return Offset(point.dx, bounds.top);
    return Offset(point.dx, bounds.bottom);
  }

  /// 点到线段的最短距离。
  static double distanceToSegment(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final lengthSq = ab.distanceSquared;
    if (lengthSq < 1e-9) return (point - a).distance;
    final ap = point - a;
    var t = (ap.dx * ab.dx + ap.dy * ab.dy) / lengthSq;
    t = t.clamp(0.0, 1.0);
    return (point - (a + ab * t)).distance;
  }

  /// 在给定点附近（外接框 [tolerance] 距离内，含内部）命中最上层可绑定形状。
  /// 箭头本身不作为目标，避免新建箭头意外绑定到自身；同层元素按集合后序
  /// 视作更靠上，符合现有渲染顺序。
  static PageShapeItem? bindableShapeNear(
    Offset point,
    Iterable<PageShapeItem> shapes, {
    String? excludingId,
    double tolerance = endpointSnapTolerance,
  }) {
    PageShapeItem? best;
    var bestDistance = tolerance;
    for (final shape in shapes) {
      if (shape.id == excludingId || !isBindable(shape)) continue;
      final distance = distanceToBounds(point, rawBounds(shape));
      if (distance < bestDistance ||
          (distance == bestDistance &&
              best != null &&
              shape.zOrder > best.zOrder)) {
        bestDistance = distance;
        best = shape;
      }
    }
    return best;
  }

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

  /// 当前线性元素的可见全局端点，正确处理既有翻转和旋转。
  ///
  /// 端点真相优先级：显式 lineStart/lineEnd（applyLinearEndpoints 与
  /// 拖拽创建写入，flip 已归零）→ 旧文档的"左下→右上"对角线 + flip 镜像。
  static ({Offset start, Offset end}) linearEndpoints(PageShapeItem shape) {
    assert(isLinear(shape));
    if (shape.lineStart != null && shape.lineEnd != null) {
      return (
        start: _localToGlobal(shape, shape.lineStart!),
        end: _localToGlobal(shape, shape.lineEnd!),
      );
    }
    final start = _localToGlobal(shape, Offset(0, shape.height));
    final end = _localToGlobal(shape, Offset(shape.width, 0));
    return (start: start, end: end);
  }

  /// 兼容入口：箭头端点（语义与 [linearEndpoints] 相同）。
  static ({Offset start, Offset end}) arrowEndpoints(PageShapeItem arrow) {
    assert(arrow.shapeType == ShapeType.arrow);
    return linearEndpoints(arrow);
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

  /// Q-1 拆分（2026-08-16）：解绑判定纯函数——箭头是否绑定到 [targetId]
  /// （start 或 end 端点）。从 DrawingController 提取——可独立单测。
  static bool isBoundTo(PageShapeItem arrow, String targetId) =>
      arrow.startBinding?.targetShapeId == targetId ||
      arrow.endBinding?.targetShapeId == targetId;

  /// 将线性元素（直线/箭头）重写为表示指定全局端点的现有
  /// `x/y/width/height` 规范格式。
  /// 旋转在此基础上会引入语义歧义，绑定箭头第一版固定清除 rotation；这比同时
  /// 保存旋转和错误投影端点更安全，也与目前箭头创建行为一致。
  ///
  /// 方向统一编码在 lineStart/lineEnd（相对外接框左上角的真实端点），
  /// flipX/flipY 归零——渲染端对带端点的线性元素不再施加 flip 镜像，
  /// 双重表达会导致方向坍缩（见 ShapeRenderer.drawDocumentShape 注释）。
  static void applyLinearEndpoints(
    PageShapeItem shape, {
    required Offset start,
    required Offset end,
  }) {
    assert(isLinear(shape));
    final left = math.min(start.dx, end.dx);
    final top = math.min(start.dy, end.dy);
    shape
      ..x = left
      ..y = top
      ..width = math.max((end.dx - start.dx).abs(), 1.0)
      ..height = math.max((end.dy - start.dy).abs(), 1.0)
      ..flipX = false
      ..flipY = false
      ..rotation = 0
      ..lineStart = start - Offset(left, top)
      ..lineEnd = end - Offset(left, top);
  }

  /// 兼容入口：箭头端点重写（语义与 [applyLinearEndpoints] 相同）。
  static void applyArrowEndpoints(
    PageShapeItem arrow, {
    required Offset start,
    required Offset end,
  }) {
    assert(arrow.shapeType == ShapeType.arrow);
    applyLinearEndpoints(arrow, start: start, end: end);
  }

  /// 建立新箭头两端的绑定关系，并把它立即规范化为绑定后的可见端点。
  ///
  /// 任一端落在目标形状 [ShapeBindingGeometry.endpointSnapTolerance]
  /// 邻域内（含内部）即建立绑定，且端点重投影到目标外接框周界上——
  /// 消掉「箭头尖悬停在形状内部/留缝」的视觉错位（审计二-3/二-4）。
  /// 空白处释放时仍保留为自由端点，因此用户可画出“形状 → 空白”
  /// 的待连接箭头；这是关系图编辑中必要的渐进状态。
  static void bindArrowAtEndpoints(
    PageShapeItem arrow,
    Iterable<PageShapeItem> shapes, {
    required Offset start,
    required Offset end,
  }) {
    assert(arrow.shapeType == ShapeType.arrow);
    Offset resolve(Offset point) {
      final target = bindableShapeNear(point, shapes, excludingId: arrow.id);
      return target == null
          ? point
          : projectPointToBounds(point, rawBounds(target));
    }

    final resolvedStart = resolve(start);
    final resolvedEnd = resolve(end);
    arrow
      ..startBinding = _bindingNear(start, shapes, arrow.id)
      ..endBinding = _bindingNear(end, shapes, arrow.id);
    applyLinearEndpoints(arrow, start: resolvedStart, end: resolvedEnd);
  }

  static ShapeEndpointBinding? _bindingNear(
    Offset point,
    Iterable<PageShapeItem> shapes,
    String arrowId,
  ) {
    final target = bindableShapeNear(point, shapes, excludingId: arrowId);
    if (target == null) return null;
    final borderPoint = projectPointToBounds(point, rawBounds(target));
    return bindingAt(target, borderPoint);
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

  /// 局部（相对外接框左上角）→ 全局画布坐标（[_localToGlobal] 的公开入口）。
  static Offset localToGlobal(PageShapeItem shape, Offset local) =>
      _localToGlobal(shape, local);

  /// 全局画布坐标 → 局部（[_localToGlobal] 的严格逆变换）。
  /// 供端点编辑手柄把拖拽后的全局端点写回 lineStart/lineEnd 局部坐标。
  static Offset globalToLocal(PageShapeItem shape, Offset global) {
    final center = Offset(shape.width / 2, shape.height / 2);
    final deltaGlobal =
        global - Offset(shape.x + center.dx, shape.y + center.dy);
    final cosAngle = math.cos(shape.rotation);
    final sinAngle = math.sin(shape.rotation);
    final delta = Offset(
      deltaGlobal.dx * cosAngle + deltaGlobal.dy * sinAngle,
      -deltaGlobal.dx * sinAngle + deltaGlobal.dy * cosAngle,
    );
    final scaled = delta + center;
    return Offset(
      shape.flipX ? 2 * center.dx - scaled.dx : scaled.dx,
      shape.flipY ? 2 * center.dy - scaled.dy : scaled.dy,
    );
  }
}
