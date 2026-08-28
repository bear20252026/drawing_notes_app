import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/selection_action_button.dart';

/// 选区派生状态（把超大 build 的判定逻辑拆到同名语义的小方法）。
typedef _SelectionState = ({
  bool hasMixed,
  bool hasStrokes,
  bool hasImage,
  bool hasShape,
  bool hasLockedObjects,
  bool imageLocked,
  bool shapeLocked,
});

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

  /// 从 controller 派生统一的选区布尔状态。
  _SelectionState _deriveState() {
    return (
      hasMixed: !isNotebookMode && controller.hasMixedDocumentObjectSelection,
      hasStrokes: controller.hasSelectedStrokes,
      hasImage: controller.hasSelectedDocumentImage,
      hasShape: controller.hasSelectedDocumentShape,
      hasLockedObjects: controller.mixedDocumentSelectionHasLockedObjects,
      imageLocked: controller.selectedDocumentImage?.locked ?? false,
      shapeLocked: controller.selectedDocumentShape?.locked ?? false,
    );
  }

  /// 是否有可编辑内容（决定滑块是否可交互）。
  bool _hasEditable(_SelectionState s) {
    if (s.hasMixed) return s.hasStrokes || !s.hasLockedObjects;
    return s.hasStrokes ||
        (s.hasImage && !s.imageLocked) ||
        (s.hasShape && !s.shapeLocked);
  }

  /// 复制/粘贴按钮。
  Widget _buildClipboardButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectionActionButton(
          icon: Icons.copy,
          tooltip: '复制选中内容',
          onTap: controller.hasSelectedStrokes
              ? controller.copySelectedStrokes
              : null,
        ),
        SelectionActionButton(
          icon: Icons.content_paste,
          tooltip: '粘贴',
          onTap: controller.pasteClipboard,
        ),
      ],
    );
  }

  /// 混合选中时锁定/解锁整组对象的按钮。
  Widget _buildMixedLockButton(_SelectionState s) {
    return SelectionActionButton(
      icon: s.hasLockedObjects ? Icons.lock : Icons.lock_open,
      tooltip: s.hasLockedObjects ? '解锁选中对象' : '锁定选中对象，防止误触编辑',
      onTap: controller.toggleSelectedDocumentObjectsLock,
    );
  }

  /// 单一类型选中（图片/形状）的锁定/解锁按钮。
  Widget _buildSingleLockButtons(_SelectionState s) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s.hasImage)
          SelectionActionButton(
            icon: s.imageLocked ? Icons.lock : Icons.lock_open,
            tooltip: s.imageLocked ? '解除图片锁定' : '锁定图片，防止误触编辑',
            onTap: controller.toggleSelectedDocumentImageLock,
          ),
        if (s.hasShape)
          SelectionActionButton(
            icon: s.shapeLocked ? Icons.lock : Icons.lock_open,
            tooltip: s.shapeLocked ? '解除形状锁定' : '锁定形状，防止误触编辑',
            onTap: controller.toggleSelectedDocumentShapeLock,
          ),
      ],
    );
  }

  /// 删除按钮的 tooltip 文案。
  String _deleteTooltip(_SelectionState s) {
    if (s.hasMixed) {
      return s.hasLockedObjects ? '删除未锁定对象；锁定对象会保留' : '删除选中对象';
    }
    if (s.hasShape && s.shapeLocked) {
      return '形状已锁定，无法删除';
    }
    if (s.imageLocked) {
      return '图片已锁定，无法删除';
    }
    return '删除选中内容';
  }

  /// 删除按钮的动作（按类型分发；锁定对象不提供删除）。
  VoidCallback? _deleteAction(_SelectionState s) {
    if (s.hasMixed) {
      return controller.deleteSelectedDocumentObjects;
    }
    if (s.hasShape && !s.shapeLocked) {
      return controller.deleteSelectedDocumentShape;
    }
    if (s.hasImage && !s.imageLocked) {
      return controller.deleteSelectedDocumentImage;
    }
    if (s.hasStrokes) {
      return controller.deleteSelectedStrokes;
    }
    return null;
  }

  /// 删除按钮。
  Widget _buildDeleteButton(_SelectionState s) {
    return SelectionActionButton(
      icon: Icons.delete_outline,
      tooltip: _deleteTooltip(s),
      onTap: _deleteAction(s),
    );
  }

  /// 当前选区状态文案。
  Widget _buildStatusText(BuildContext context, _SelectionState s) {
    final String text;
    if (s.hasMixed && controller.selectedDocumentObjectCount > 1) {
      text =
          '已选中 ${controller.selectedDocumentObjectCount} 个对象'
          '${s.hasLockedObjects ? '（含锁定对象）' : ''}';
    } else if (s.hasShape) {
      text = s.shapeLocked ? '形状已锁定：解除锁定后可编辑' : '已选中形状：可拖动、缩放、锁定或删除';
    } else if (s.hasImage) {
      text = s.imageLocked ? '图片已锁定：解除锁定后可编辑' : '已选中图片：可拖动、缩放、锁定或删除';
    } else if (s.hasStrokes) {
      text = '已选中 ${controller.selection.selectedStrokeIndices.length} 笔';
    } else {
      text = '选区未命中内容（可拖动画布重新框选）';
    }
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = _deriveState();
        final hasSel = controller.hasSelection || s.hasMixed;
        final hasEditable = _hasEditable(s);
        if (!hasSel && !s.hasImage && !s.hasShape) {
          return const SizedBox.shrink();
        }

        return Material(
          elevation: 1,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                _buildClipboardButtons(),
                if (s.hasMixed)
                  _buildMixedLockButton(s)
                else
                  _buildSingleLockButtons(s),
                _buildDeleteButton(s),
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
                          onChangeEnd: hasEditable
                              ? (_) => onTransformEnd()
                              : null,
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
                          min: 0,
                          max: 360,
                          onChanged: s.hasStrokes ? onRotateChanged : null,
                        ),
                      ),
                      const Icon(Icons.rotate_right, size: 18),
                    ],
                  ),
                ),
                _buildStatusText(context, s),
              ],
            ),
          ),
        );
      },
    );
  }
}
