/// 手势变换纯数学（架构重构 R3：从 editor_page 隔离的可单测函数）。
///
/// 设计原则（见 docs/ARCHITECTURE_REVISION.md）：
/// - 本文件**只包含纯函数**：无状态、无 IO、无 UI 依赖；
/// - 视口旋转/缩放/平移等坐标变换数学集中于此，便于单元测试与复用；
/// - editor_page 手势回调仅做调度，变换计算调用本文件函数。
library;

import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

/// 绕原点旋转点 [p]（角度 [angle] 弧度，逆时针为正）。
///
/// 对应视口旋转：view = R(angle)·(p) + offset 中的旋转部分。
Offset rotatePoint2(Offset p, double angle) {
  final c = cos(angle);
  final s = sin(angle);
  return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
}

/// 双指捏合缩放因子：两点当前距离 / 初始距离（>0 防除零）。
double pinchScaleFactor(Offset aNow, Offset bNow, double initialDistance) {
  if (initialDistance <= 0.001) return 1.0;
  final d = (aNow - bNow).distance;
  if (d <= 0.001) return 1.0;
  return d / initialDistance;
}

/// 双指中点（平移用）。
Offset pinchCenter(Offset a, Offset b) =>
    Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

/// 两点距离（初始捏合距离计算用）。
double distanceBetween(Offset a, Offset b) => (a - b).distance;

/// 视口变换：画布点 -> 视图点（围绕画布中心 [center] 的旋转+缩放+平移）。
///
/// 数学模型（与 drawing_controller 严格互逆）：
///   view = R(angle)·(scale·(p - center)) + center + offset
Offset canvasToViewPoint(
  Offset canvasPoint,
  double scale,
  double angle,
  Offset center,
  Offset offset,
) {
  final rotated = rotatePoint2((canvasPoint - center) * scale, angle);
  return rotated + center + offset;
}

/// 视口逆变换：视图点 -> 画布点（[canvasToViewPoint] 的逆）。
Offset viewToCanvasPoint(
  Offset viewPoint,
  double scale,
  double angle,
  Offset center,
  Offset offset,
) {
  // view - center - offset = R(angle)·(scale·(p - center))
  // => R(-angle)·(view - center - offset) = scale·(p - center)
  final unrotated = rotatePoint2(viewPoint - center - offset, -angle);
  return unrotated / scale + center;
}

// ---------------------------------------------------------------------------
// 矩阵化视口变换（本地化适配 vector_math，审计改造 2026-08-15）
//
// 原理：view = R(angle)·(scale·(p - center)) + center + offset 是标准 2D
// 仿射变换，可组合为单个矩阵 M = T(center+offset)·R(angle)·S(scale)·T(-center)
// 一次构建、多次应用（矩阵乘法），替代每次调用都重算 cos/sin 的方式；
// 逆变换用 M⁻¹（Matrix3.inverted），与函数式版本数学严格等价。
// ---------------------------------------------------------------------------

/// 构建视口变换矩阵：T(center+offset)·R(angle)·S(scale)·T(-center)。
///
/// 与 [canvasToViewPoint] 的数学模型严格一致（组合一次，供批量点变换）。
vmath.Matrix4 viewTransformMatrix(
  double scale,
  double angle,
  Offset center,
  Offset offset,
) {
  return vmath.Matrix4.identity()
    ..translateByDouble(center.dx + offset.dx, center.dy + offset.dy, 0.0, 1.0)
    ..rotateZ(angle)
    ..scaleByDouble(scale, scale, 1.0, 1.0)
    ..translateByDouble(-center.dx, -center.dy, 0.0, 1.0);
}

/// 应用 2D 仿射矩阵到点 [p]（视口变换矩阵版）。
Offset transformPoint(vmath.Matrix4 m, Offset p) {
  final v = m.transform3(vmath.Vector3(p.dx, p.dy, 1.0));
  return Offset(v.x, v.y);
}

/// 矩阵版视口正变换：画布点 -> 视图点（[canvasToViewPoint] 的等价实现）。
///
/// [m] 由 [viewTransformMatrix] 构建；批量变换同一矩阵时性能优于逐点重建。
Offset canvasToViewPointMatrix(vmath.Matrix4 m, Offset canvasPoint) =>
    transformPoint(m, canvasPoint);

/// 矩阵版视口逆变换：视图点 -> 画布点（[viewToCanvasPoint] 的等价实现）。
Offset viewToCanvasPointMatrix(vmath.Matrix4 m, Offset viewPoint) =>
    transformPoint(m.clone()..invert(), viewPoint);

/// 屏幕增量 → 画布增量（视口旋转/缩放逆变换，纯函数）。
///
/// 阶段二提取（2026-08-15）：原 drag_ops._screenDeltaToCanvas 依赖
/// controller 状态，参数化后为顶层纯函数（Effective Dart：不绑定类
/// 就放顶层），可单测验证数学正确性。
Offset screenDeltaToCanvas(
  Offset screenDelta,
  double viewRotation,
  double viewScale,
) {
  final rot = -viewRotation;
  final cosA = cos(rot);
  final sinA = sin(rot);
  final vx = screenDelta.dx * cosA - screenDelta.dy * sinA;
  final vy = screenDelta.dx * sinA + screenDelta.dy * cosA;
  return Offset(vx / viewScale, vy / viewScale);
}
