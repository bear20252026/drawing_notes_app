/// 手势变换纯数学（架构重构 R3：从 editor_page 隔离的可单测函数）。
///
/// 设计原则（见 docs/ARCHITECTURE_REVISION.md）：
/// - 本文件**只包含纯函数**：无状态、无 IO、无 UI 依赖；
/// - 视口旋转/缩放/平移等坐标变换数学集中于此，便于单元测试与复用；
/// - editor_page 手势回调仅做调度，变换计算调用本文件函数。
library;

import 'dart:math';

import 'package:flutter/widgets.dart';

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
