import 'dart:ui';

import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_binding_geometry.dart';

/// 由一次按下—拖拽—抬起手势生成形状的几何结果。
class ShapeCreationGeometry {
  /// 本次手势是否为单击（位移小于点击阈值）。
  final bool isClick;

  ShapeCreationGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.flipX,
    required this.flipY,
    this.isClick = false,
    this.lineStart,
    this.lineEnd,
  });

  /// 单击阈值（二-6，审计 2026-09-06）：4px 时轻微手抖即被判为拖拽/单击的
  /// 边界极易误触，提到 8px 与端点吸附容差同量级；编辑器预览层共用此常量。
  static const double clickThreshold = 8;
  static const double _defaultWidth = 160;
  static const double _defaultHeight = 110;
  static const double _minSize = 2;
  static const double _maxSize = 10000;

  /// 吸附数值单一来源在 [ShapeBindingGeometry]（rendering 层）——
  /// application 层（对象编辑会话）也要用同一套吸附，而洋葱规则禁止
  /// application → infrastructure，故常量与纯函数上移、此处仅转发。
  static const double angleSnapToleranceDegrees =
      ShapeBindingGeometry.angleSnapToleranceDegrees;
  static const double gridSnapStep = ShapeBindingGeometry.gridSnapStep;

  final double x;
  final double y;
  final double width;
  final double height;
  final bool flipX;
  final bool flipY;

  /// 线性元素（直线/箭头）的真实端点（相对外接框左上角），
  /// 用于修复方向与鼠标轨迹不一致的问题（参考 Saber shape_pen）。
  final Offset? lineStart;
  final Offset? lineEnd;

  factory ShapeCreationGeometry.fromDrag(Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final isClick = dx.abs() < clickThreshold && dy.abs() < clickThreshold;
    final width = isClick
        ? _defaultWidth
        : dx.abs().clamp(_minSize, _maxSize).toDouble();
    final height = isClick
        ? _defaultHeight
        : dy.abs().clamp(_minSize, _maxSize).toDouble();
    final left = isClick ? start.dx - width / 2 : _min(start.dx, end.dx);
    final top = isClick ? start.dy - height / 2 : _min(start.dy, end.dy);
    return ShapeCreationGeometry(
      x: left,
      y: top,
      width: width,
      height: height,
      flipX: !isClick && dx < 0,
      flipY: !isClick && dy < 0,
      isClick: isClick,
      // 线性元素保存相对外接框的真实端点（含拖动方向）。
      lineStart: start - Offset(left, top),
      lineEnd: end - Offset(left, top),
    );
  }

  /// 角度吸附转发（见 [ShapeBindingGeometry.snapDragAngle]）。
  static Offset snapDragAngle(
    Offset anchor,
    Offset end, {
    double toleranceDegrees = angleSnapToleranceDegrees,
    bool force = false,
  }) => ShapeBindingGeometry.snapDragAngle(
    anchor,
    end,
    toleranceDegrees: toleranceDegrees,
    force: force,
  );

  /// 网格吸附转发（见 [ShapeBindingGeometry.snapToGrid]）。
  static Offset snapToGrid(Offset point, double step) =>
      ShapeBindingGeometry.snapToGrid(point, step);

  /// 创建线性元素（直线/箭头）时统一应用吸附的拖拽点换算。
  ///
  /// 规则（档位互斥，网格优先）：开启 [gridSnapEnabled] 时两端对齐 20px
  /// 网格、不再做角度吸附；否则对线性元素做 0°/45°/90° 角度磁吸
  /// （[forceAngle] 时忽略容差、直接吸附到最近 45° 方向，即桌面 Shift 行为）。
  /// 预览层（_shapeDraft）与提交层（_onPointerUp）共用本函数保证所见即所得。
  static ({Offset start, Offset end}) snappedDragPoints(
    Offset start,
    Offset end, {
    required bool linear,
    bool gridSnapEnabled = false,
    bool forceAngle = false,
  }) {
    if (gridSnapEnabled) {
      return (
        start: snapToGrid(start, gridSnapStep),
        end: snapToGrid(end, gridSnapStep),
      );
    }
    if (!linear) return (start: start, end: end);
    return (start: start, end: snapDragAngle(start, end, force: forceAngle));
  }

  PageShapeItem createShape({
    required String id,
    required ShapeType shapeType,
    required int color,
    required double strokeWidth,
    String? boundElementId,
    int? fillColor,
  }) {
    // 单击放置的线性元素没有拖拽方向：端点置空，交由渲染端回退为
    // 默认对角线（与 Excalidraw 单击放置一致），避免退化为零长度线段。
    final linearClick =
        isClick &&
        (shapeType == ShapeType.line || shapeType == ShapeType.arrow);
    return PageShapeItem(
      id: id,
      shapeType: shapeType,
      x: x,
      y: y,
      width: width,
      height: height,
      color: color,
      fillColor: fillColor,
      strokeWidth: strokeWidth.clamp(1, 20).toDouble(),
      flipX: flipX,
      flipY: flipY,
      boundElementId: boundElementId,
      lineStart: linearClick ? null : lineStart,
      lineEnd: linearClick ? null : lineEnd,
    );
  }

  static double _min(double a, double b) => a < b ? a : b;
}
