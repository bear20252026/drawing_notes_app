/// 编辑器覆盖层 — 独立 Widget（拖拽/选择/编辑覆盖层）。
///
/// 从 editor_page_overlays.dart 拆分出的独立组件。
/// 负责：
/// - 选择框显示
/// - 拖拽指示器
/// - 对齐参考线
/// - 文字编辑覆盖层
/// - 图片裁剪覆盖层
///
/// 通过 [EditorState] 读取状态，通过回调向上传递交互事件。
library;

import 'package:flutter/material.dart';

import '../controllers/editor_state.dart';

/// 编辑器覆盖层。
class EditorOverlayLayer extends StatelessWidget {
  const EditorOverlayLayer({
    super.key,
    required this.editorState,
    this.onSelectionUpdate,
    this.onCropUpdate,
  });

  /// 编辑器状态。
  final EditorState editorState;

  /// 选择框更新回调。
  final void Function(Rect rect)? onSelectionUpdate;

  /// 裁剪框更新回调。
  final void Function(Rect rect)? onCropUpdate;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 对齐参考线
        if (editorState.snapGuides.isNotEmpty) _buildSnapGuides(),
        // 框选矩形
        if (editorState.marqueeRect != null) _buildMarqueeRect(),
        // 形状草稿
        if (editorState.shapeDraftStart != null &&
            editorState.shapeDraftCurrent != null)
          _buildShapeDraft(),
        // 裁剪覆盖层
        if (editorState.cropItem != null && editorState.cropRect != null)
          _buildCropOverlay(),
        // 拖放指示器
        if (editorState.isDraggingFile) _buildDropIndicator(),
      ],
    );
  }

  Widget _buildSnapGuides() {
    return Stack(
      children: [
        for (final guide in editorState.snapGuides)
          Positioned(
            left: guide.vertical ? guide.pos : null,
            top: guide.vertical ? null : guide.pos,
            width: guide.vertical ? 1 : null,
            height: guide.vertical ? null : 1,
            child: ColoredBox(
              color: const Color(0xFFFF2D55).withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }

  Widget _buildMarqueeRect() {
    final rect = editorState.marqueeRect!;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF0066CC),
            width: 1,
          ),
          color: const Color(0xFF0066CC).withValues(alpha: 0.1),
        ),
      ),
    );
  }

  Widget _buildShapeDraft() {
    final start = editorState.shapeDraftStart!;
    final current = editorState.shapeDraftCurrent!;
    final rect = Rect.fromPoints(start, current);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF0066CC),
            width: 2,
          ),
          color: const Color(0xFF0066CC).withValues(alpha: 0.05),
        ),
      ),
    );
  }

  Widget _buildCropOverlay() {
    final rect = editorState.cropRect!;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.white,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildDropIndicator() {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xFF0066CC).withValues(alpha: 0.05),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFF0066CC),
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '拖放文件到此处',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0066CC),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
