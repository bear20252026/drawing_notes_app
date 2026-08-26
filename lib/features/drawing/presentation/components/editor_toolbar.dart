/// 编辑器工具栏 — 独立 Widget。
///
/// 从 editor_page_tools.dart 拆分出的独立组件。
/// 负责：
/// - 工具选择（画笔/橡皮/文字/形状/选择/手型）
/// - 颜色选择
/// - 线宽选择
///
/// 通过回调向上传递工具选择事件。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_design.dart';
import '../controllers/editor_state.dart';

/// 编辑器工具栏。
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.editorState,
    required this.selectedColor,
    required this.strokeWidth,
    this.onToolSelected,
    this.onColorSelected,
    this.onStrokeWidthSelected,
    this.onToggleGrid,
    this.onToggleSnap,
  });

  /// 编辑器状态。
  final EditorState editorState;

  /// 当前选中的颜色。
  final Color selectedColor;

  /// 当前线宽。
  final double strokeWidth;

  /// 工具选择回调。
  final void Function(String toolId)? onToolSelected;

  /// 颜色选择回调。
  final void Function(Color color)? onColorSelected;

  /// 线宽选择回调。
  final void Function(double width)? onStrokeWidthSelected;

  /// 网格切换回调。
  final VoidCallback? onToggleGrid;

  /// 吸附切换回调。
  final VoidCallback? onToggleSnap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppDesign.surfaceTile1 : AppDesign.canvas;

    return Container(
      width: 56,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          right: BorderSide(
            color: isDark
                ? AppDesign.bodyMuted.withValues(alpha: 0.2)
                : AppDesign.dividerSoft,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // 画笔工具
          _ToolButton(
            icon: Icons.edit_rounded,
            tooltip: '画笔',
            isActive: !editorState.eyedropperActive &&
                !editorState.textToolActive &&
                !editorState.handToolActive &&
                editorState.activeShapeTool == null,
            onTap: () => onToolSelected?.call('pen'),
          ),
          // 文字工具
          _ToolButton(
            icon: Icons.text_fields_rounded,
            tooltip: '文字',
            isActive: editorState.textToolActive,
            onTap: () => onToolSelected?.call('text'),
          ),
          // 形状工具
          _ToolButton(
            icon: Icons.category_rounded,
            tooltip: '形状',
            isActive: editorState.activeShapeTool != null,
            onTap: () => onToolSelected?.call('shape'),
          ),
          // 选择工具
          _ToolButton(
            icon: Icons.near_me_rounded,
            tooltip: '选择',
            isActive: editorState.selectionDone,
            onTap: () => onToolSelected?.call('select'),
          ),
          // 手型工具
          _ToolButton(
            icon: Icons.pan_tool_rounded,
            tooltip: '平移',
            isActive: editorState.handToolActive,
            onTap: () => onToolSelected?.call('hand'),
          ),
          // 取色器
          _ToolButton(
            icon: Icons.colorize_rounded,
            tooltip: '取色器',
            isActive: editorState.eyedropperActive,
            onTap: () => onToolSelected?.call('eyedropper'),
          ),
          const Divider(height: 16),
          // 网格
          _ToolButton(
            icon: Icons.grid_on_rounded,
            tooltip: '网格',
            isActive: editorState.gridVisible,
            onTap: onToggleGrid,
          ),
          // 吸附
          _ToolButton(
            icon: Icons.grid_4x4_rounded,
            tooltip: '吸附',
            isActive: editorState.snapToGrid,
            onTap: onToggleSnap,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? AppDesign.appleBlue : AppDesign.appleBlue;
    final inactiveColor =
        isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48;

    return Semantics(
      button: true,
      label: tooltip,
      selected: isActive,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesign.roundedMd),
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isActive
                ? activeColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDesign.roundedMd),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive ? activeColor : inactiveColor,
          ),
        ),
      ),
    );
  }
}
