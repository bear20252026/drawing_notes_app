// editor_v2——ViewportState（批次 F-6——2026-08-21——Excalidraw 模式）。
//
// 视口状态（缩放/平移）——不可变——坐标转换/可见区域。
// 照搬 Excalidraw 无限画布模式——Flutter 适配。
// 纯 Dart——禁 Flutter/dart:io（R-02）。
library;

import 'package:flutter/painting.dart';

/// 视口状态（无限画布——缩放/平移）。
///
/// 遵循 Excalidraw 模式：
/// - 不可变（copyWith）
/// - 世界坐标 ↔ 屏幕坐标转换
/// - 可见世界区域（用于裁剪——世界空间裁剪——性能）
class ViewportState {
  const ViewportState({
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
  });

  final double scale;
  final double offsetX;
  final double offsetY;

  /// 世界坐标 → 屏幕坐标。
  Offset worldToScreen(double worldX, double worldY) =>
      Offset(worldX * scale + offsetX, worldY * scale + offsetY);

  /// 屏幕坐标 → 世界坐标。
  Offset screenToWorld(double screenX, double screenY) =>
      Offset((screenX - offsetX) / scale, (screenY - offsetY) / scale);

  /// 可见世界区域（用于裁剪——只绘制可见区域——性能优化）。
  ({double left, double top, double right, double bottom}) visibleWorldRect(
      double viewportWidth, double viewportHeight) {
    final topLeft = screenToWorld(0, 0);
    final bottomRight = screenToWorld(viewportWidth, viewportHeight);
    return (
      left: topLeft.dx,
      top: topLeft.dy,
      right: bottomRight.dx,
      bottom: bottomRight.dy,
    );
  }

  /// 不可变拷贝。
  ViewportState copyWith({double? scale, double? offsetX, double? offsetY}) {
    return ViewportState(
      scale: scale ?? this.scale,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewportState &&
          scale == other.scale &&
          offsetX == other.offsetX &&
          offsetY == other.offsetY;

  @override
  int get hashCode => Object.hash(scale, offsetX, offsetY);
}
