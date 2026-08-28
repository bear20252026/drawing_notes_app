import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/drawing/presentation/editor_selection_geometry.dart';

/// 形状 8 向缩放手柄（四角 + 四边中点，借鉴 Excalidraw）。
///
/// 巨型类 Widget 组合解耦（2026-08-15 阶段 1）：从 editor_page_drag_ops
/// 的 [_buildResizeHandles]/[_resizeHandle] 提取为独立 Widget（DEV
/// 2026-08 方案：只读渲染提取 Widget、交互经回调注入）。
/// - 纯渲染：手柄位置计算 + 外观 + 手势检测；
/// - 交互编排（几何计算、状态修改和通知）经命名 [onResize] 回调由宿主承担。
class ResizeHandles extends StatelessWidget {
  const ResizeHandles({
    super.key,
    required this.width,
    required this.height,
    required this.screenToCanvasDelta,
    required this.onResize,
    required this.onChanged,
  });

  /// 元素外接框尺寸（经 viewScale 换算后的展示坐标，决定手柄位置）。
  final double width;
  final double height;

  /// 屏幕增量 → 画布增量（视口旋转/缩放换算，由宿主注入）。
  final Offset Function(Offset screenDelta) screenToCanvasDelta;

  /// 手柄拖拽回调：传递明确的八向 [EditorShapeResizeHandle] 语义和
  /// 画布增量；宿主决定如何计算及写入领域状态。
  final void Function(EditorShapeResizeHandle handle, Offset canvasDelta)
  onResize;

  /// 每次拖拽更新后的通知（宿主 State 通知变更/自动保存）。
  final VoidCallback onChanged;

  static const double _handleSize = 10.0;

  @override
  Widget build(BuildContext context) {
    const size = _handleSize;
    final handles = <({EditorShapeResizeHandle handle, Offset position})>[
      (handle: EditorShapeResizeHandle.topLeft, position: Offset.zero),
      (handle: EditorShapeResizeHandle.top, position: Offset(width / 2, 0)),
      (handle: EditorShapeResizeHandle.topRight, position: Offset(width, 0)),
      (handle: EditorShapeResizeHandle.left, position: Offset(0, height / 2)),
      (
        handle: EditorShapeResizeHandle.right,
        position: Offset(width, height / 2),
      ),
      (handle: EditorShapeResizeHandle.bottomLeft, position: Offset(0, height)),
      (
        handle: EditorShapeResizeHandle.bottom,
        position: Offset(width / 2, height),
      ),
      (
        handle: EditorShapeResizeHandle.bottomRight,
        position: Offset(width, height),
      ),
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final entry in handles)
          _handle(handle: entry.handle, position: entry.position, size: size),
      ],
    );
  }

  Widget _handle({
    required EditorShapeResizeHandle handle,
    required Offset position,
    required double size,
  }) {
    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          onResize(handle, screenToCanvasDelta(details.delta));
          onChanged();
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF42A5F5),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
      ),
    );
  }
}
