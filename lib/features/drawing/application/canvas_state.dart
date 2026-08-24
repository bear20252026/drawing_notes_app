// canvas_state.dart — 画布视口状态管理器（从 DrawingController 提取）。
//
// 职责：管理画布缩放/平移/旋转变换。
// 设计：纯状态容器 + onChange 回调，不依赖 ChangeNotifier。

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:drawing_notes_app/features/drawing/domain/document.dart';

/// 画布视口状态管理器。
///
/// 从 DrawingController 的视口字段提取：
/// - viewScale / viewOffset / viewRotation
/// - 坐标变换方法（viewToCanvas / canvasToView）
///
/// 使用方式：
/// ```dart
/// final canvasState = CanvasState(document: doc, onChange: () => notifyListeners());
/// canvasState.viewScale = 2.0;
/// final canvasPoint = canvasState.viewToCanvas(viewPoint);
/// ```
class CanvasState {
  CanvasState({
    required this.document,
    this.onChange,
  });

  /// 文档引用（获取画布尺寸）。
  final DrawingDocument document;

  /// 状态变更回调（由 DrawingController 注入 notifyListeners）。
  final void Function()? onChange;

  // ─── 状态字段 ───

  /// 画布缩放比例（1.0 = 实际大小）。
  double _viewScale = 1.0;

  /// 画布在视口中的平移偏移（画布中心相对视口中心的位移）。
  Offset _viewOffset = Offset.zero;

  /// 画布旋转角度（弧度，Phase 7 双指旋转用）。
  double _viewRotation = 0.0;

  // ─── 只读访问器 ───

  double get viewScale => _viewScale;
  Offset get viewOffset => _viewOffset;
  double get viewRotation => _viewRotation;

  /// 画布文档中心（缩放/旋转的基准点）。
  Offset get canvasCenter => document.size.center(Offset.zero);

  // ─── 写入方法 ───

  set viewScale(double value) {
    _viewScale = value;
    onChange?.call();
  }

  set viewOffset(Offset value) {
    _viewOffset = value;
    onChange?.call();
  }

  set viewRotation(double value) {
    _viewRotation = value;
    onChange?.call();
  }

  // ─── 坐标变换 ───

  /// 把视图坐标（像素）转换为画布逻辑坐标。
  ///
  /// 变换模型（与 CanvasPainter 严格互逆）：
  ///   view = R(rot) · (scale · (p - center)) + center + offset
  ///   逆：p = R(-rot) · (view - center - offset) / scale + center
  Offset viewToCanvas(Offset viewPoint) {
    final center = canvasCenter;
    final translated = viewPoint - center - _viewOffset;
    if (_viewRotation == 0) {
      return translated / _viewScale + center;
    }
    final cos = _cos(-_viewRotation);
    final sin = _sin(-_viewRotation);
    return Offset(
      (translated.dx * cos - translated.dy * sin) / _viewScale + center.dx,
      (translated.dx * sin + translated.dy * cos) / _viewScale + center.dy,
    );
  }

  /// 把画布坐标转换为视图坐标。
  Offset canvasToView(Offset canvasPoint) {
    final center = canvasCenter;
    final scaled = (canvasPoint - center) * _viewScale;
    if (_viewRotation == 0) {
      return scaled + center + _viewOffset;
    }
    final cos = _cos(_viewRotation);
    final sin = _sin(_viewRotation);
    return Offset(
      scaled.dx * cos - scaled.dy * sin,
      scaled.dx * sin + scaled.dy * cos,
    ) + center + _viewOffset;
  }

  // ─── 内部工具 ───

  static double _cos(double radians) => math.cos(radians);
  static double _sin(double radians) => math.sin(radians);
}
