// editor_v2——InfiniteCanvasWidget（批次 F-6——2026-08-21——Excalidraw 模式）。
//
// 无限画布 Widget（GestureDetector + Transform 包装器）。
// 照搬 Excalidraw 无限画布模式——Flutter 适配。
// 不修改现有 CanvasPainterV2——新增包装层（安全约束）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/infinite_canvas_notifier.dart';

/// 无限画布 Widget（GestureDetector + Transform 包装器）。
///
/// 遵循 Excalidraw 模式：
/// - 单指拖拽 → 平移
/// - 双指缩放 → 缩放（focalPoint 为中心）
/// - Transform 矩阵（世界空间裁剪——性能）
/// - 不修改现有 CanvasPainterV2/PagedCanvasViewModel——新增层（安全约束）
class InfiniteCanvasWidget extends ConsumerWidget {
  const InfiniteCanvasWidget({
    super.key,
    required this.child,
    this.enablePan = true,
    this.enableZoom = true,
  });

  final Widget child;
  final bool enablePan;
  final bool enableZoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewport = ref.watch(infiniteCanvasProvider);

    return GestureDetector(
      onScaleUpdate: (details) {
        if (enablePan && details.pointerCount == 1) {
          ref.read(infiniteCanvasProvider.notifier).pan(
            details.focalPointDelta.dx,
            details.focalPointDelta.dy,
          );
        } else if (enableZoom && details.pointerCount >= 2) {
          ref.read(infiniteCanvasProvider.notifier).zoom(
            details.scale,
            details.localFocalPoint.dx,
            details.localFocalPoint.dy,
          );
        }
      },
      child: Transform.scale(
        scale: viewport.scale,
        child: Transform.translate(
          offset: Offset(viewport.offsetX, viewport.offsetY),
          child: child,
        ),
      ),
    );
  }
}
