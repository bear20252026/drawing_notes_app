import 'package:flutter/material.dart';

import '../application/drawing_controller.dart';
import 'selection_action_button.dart';

/// 选区操作条（复制/粘贴/锁定/删除/清除 + 缩放/旋转滑块 + 状态文案）。
///
/// 巨型类 Widget 组合解耦（2026-08-15 阶段四）：从 editor_page_drag_ops
/// 的 [_buildSelectionBar] 提取为独立 Widget。依据 DEV 2026-08 方案
/// （独立 Widget 接收 controller——ContractTreeSection(selection:
/// _selection) 先例）+ Flutter 官方 SelectionOverlay buildToolbar
/// 独立构建器模式。
/// - 状态计算在 Widget 内用 [controller] getter 完成（避免过度参数化）；
/// - 交互经回调注入（滑块/清除选区/变换结束由 State 承担 _applyState）。
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.controller,
    required this.isNotebookMode,
    required this.scaleValue,
    required this.rotateDegrees,
    required this.onScaleChanged,
    required this.onRotateChanged,
    required this.onClearSelection,
    required this.onTransformEnd,
  });

  final DrawingController controller;
  final bool isNotebookMode;

  /// 当前缩放/旋转值（State 持有，经此传入）。
  final double scaleValue;
  final double rotateDegrees;

  /// 滑块变化回调（State 侧 _applyState + controller 变换）。
  final void Function(double value) onScaleChanged;
  final void Function(double value) onRotateChanged;

  /// 清除选区（State 侧 _applyState + 视图模型复位）。
  final VoidCallback onClearSelection;

  /// 变换结束（State 侧 controller.endXxxTransform + 通知）。
  final VoidCallback onTransformEnd;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasMixed =
            !isNotebookMode && controller.hasMixedDocumentObjectSelection;
        final hasSel = controller.hasSelection || hasMixed;
        final hasStrokes = controller.hasSelectedStrokes;
        final hasImage = controller.hasSelectedDocumentImage;
        final hasShape = controller.hasSelectedDocumentShape;
        final imageLocked = controller.selectedDocumentImage?.locked ?? false;
        final shapeLocked = controller.selectedDocumentShape?.locked ?? false;
        final hasLockedObjects =
            controller.mixedDocumentSelectionHasLockedObjects;
        final hasEditable = hasMixed
            ? hasStrokes || !hasLockedObjects
            : hasStrokes ||
                  (hasImage && !imageLocked) ||
                  (hasShape && !shapeLocked);
        if (!hasSel && !hasImage && !hasShape) return const SizedBox.shrink();

        return Material(
          elevation: 1,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                SelectionActionButton(
                  icon: Icons.copy,
                  tooltip: '复制选中内容',
                  onTap: hasStrokes ? controller.copySelectedStrokes : null,
                ),
                SelectionActionButton(
                  icon: Icons.content_paste,
                  tooltip: '粘贴',
                  onTap: controller.pasteClipboard,
                ),
                if (hasMixed)
                  SelectionActionButton(
                    icon: hasLockedObjects ? Icons.lock : Icons.lock_open,
                    tooltip: hasLockedObjects
                        ? '解锁选中对象'
                        : '锁定选中对象，防止误触编辑',
                    onTap: controller.toggleSelectedDocumentObjectsLock,
                  )
                else ...[
                  if (hasImage)
                    SelectionActionButton(
                      icon: imageLocked ? Icons.lock : Icons.lock_open,
                      tooltip: imageLocked
                          ? '解除图片锁定'
                          : '锁定图片，防止误触编辑',
                      onTap: controller.toggleSelectedDocumentImageLock,
                    ),
                  if (hasShape)
                    SelectionActionButton(
                      icon: shapeLocked ? Icons.lock : Icons.lock_open,
                      tooltip: shapeLocked
                          ? '解除形状锁定'
                          : '锁定形状，防止误触编辑',
                      onTap: controller.toggleSelectedDocumentShapeLock,
                    ),
                ],
                SelectionActionButton(
                  icon: Icons.delete_outline,
                  tooltip: hasMixed
                      ? hasLockedObjects
                            ? '删除未锁定对象；锁定对象会保留'
                            : '删除选中对象'
                      : hasShape && shapeLocked
                      ? '形状已锁定，无法删除'
                      : imageLocked
                      ? '图片已锁定，无法删除'
                      : '删除选中内容',
                  onTap: hasMixed
                      ? controller.deleteSelectedDocumentObjects
                      : hasShape && !shapeLocked
                      ? controller.deleteSelectedDocumentShape
                      : hasImage && !imageLocked
                      ? controller.deleteSelectedDocumentImage
                      : hasStrokes
                      ? controller.deleteSelectedStrokes
                      : null,
                ),
                SelectionActionButton(
                  icon: Icons.close,
                  tooltip: '清除选区',
                  onTap: onClearSelection,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.zoom_in, size: 18),
                      Expanded(
                        child: Slider(
                          value: scaleValue.clamp(0.1, 5.0),
                          min: 0.1,
                          max: 5.0,
                          onChanged: hasEditable ? onScaleChanged : null,
                          onChangeEnd: hasEditable ? (_) => onTransformEnd() : null,
                        ),
                      ),
                      const Icon(Icons.zoom_out, size: 18),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.rotate_left, size: 18),
                      Expanded(
                        child: Slider(
                          value: rotateDegrees.clamp(0, 360),
                          max: 360,
                          onChanged: hasStrokes ? onRotateChanged : null,
                        ),
                      ),
                      const Icon(Icons.rotate_right, size: 18),
                    ],
                  ),
                ),
                Text(
                  hasMixed && controller.selectedDocumentObjectCount > 1
                      ? '已选中 ${controller.selectedDocumentObjectCount} 个对象${hasLockedObjects ? '（含锁定对象）' : ''}'
                      : hasShape
                      ? shapeLocked
                            ? '形状已锁定：解除锁定后可编辑'
                            : '已选中形状：可拖动、缩放、锁定或删除'
                      : hasImage
                      ? imageLocked
                            ? '图片已锁定：解除锁定后可编辑'
                            : '已选中图片：可拖动、缩放、锁定或删除'
                      : hasStrokes
                      ? '已选中 ${controller.selection.selectedStrokeIndices.length} 笔'
                      : '选区未命中内容（可拖动画布重新框选）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
