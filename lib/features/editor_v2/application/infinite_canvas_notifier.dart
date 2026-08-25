// editor_v2——InfiniteCanvasNotifier（批次 F-6——2026-08-21——Excalidraw 模式）。
//
// 无限画布 ViewModel（Riverpod Notifier）——缩放/平移/重置。
// 照搬 Excalidraw 无限画布模式——Flutter 适配。
// 纯 Dart 逻辑——无 UI 依赖——Headless Logic。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'viewport_state.dart';

/// 无限画布 ViewModel（缩放/平移/重置）。
///
/// 遵循 Excalidraw 模式：
/// - 双指缩放（scale 变化）
/// - 拖拽平移（offset 变化）
/// - 重置（恢复初始状态）
class InfiniteCanvasNotifier extends Notifier<ViewportState> {
  @override
  ViewportState build() => const ViewportState();

  /// 平移（拖拽）。
  void pan(double dx, double dy) {
    state = state.copyWith(
      offsetX: state.offsetX + dx,
      offsetY: state.offsetY + dy,
    );
  }

  /// 缩放（双指——focalPoint 为中心）。
  void zoom(double scaleFactor, double focalX, double focalY) {
    final newScale = (state.scale * scaleFactor).clamp(0.1, 10.0);
    final dx = focalX - (focalX - state.offsetX) * newScale / state.scale;
    final dy = focalY - (focalY - state.offsetY) * newScale / state.scale;
    state = ViewportState(scale: newScale, offsetX: dx, offsetY: dy);
  }

  /// 重置（恢复初始状态）。
  void reset() => state = const ViewportState();
}

/// Riverpod Provider。
final infiniteCanvasProvider =
    NotifierProvider<InfiniteCanvasNotifier, ViewportState>(
  InfiniteCanvasNotifier.new,
);
