import 'package:material_ui/material_ui.dart';
import 'editor_toolbar_helpers.dart';
import 'editor_toolbar_state.dart';

/// 混排对象编辑控件（文字样式/形状样式/编辑/删除）。
///
/// 从 [EditorToolbar] build 方法中拆分，仅在有选中对象时渲染。
class ObjectEditSection extends StatelessWidget {
  const ObjectEditSection({
    super.key,
    required this.state,
    required this.actions,
  });

  final EditorToolbarState state;
  final EditorToolbarActions actions;

  @override
  Widget build(BuildContext context) {
    if (state.selectedItemId == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 选中文字块：快捷字号滑块 + 文字样式
        if (state.selectedTextItem != null) ...[
          const Icon(Icons.format_size, size: 18),
          SizedBox(
            width: 120,
            child: Slider(
              value: state.selectedTextItem!.fontSize.clamp(8, 200),
              min: 8,
              max: 200,
              onChanged: actions.onSelectedFontSize,
            ),
          ),
          Text(
            '${state.selectedTextItem!.fontSize.round()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Tooltip(
              message: '文字颜色',
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: actions.changeTextColor,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Color(state.selectedTextItem!.color),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black26),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '加粗 (Ctrl+B)',
            icon: const Icon(Icons.format_bold, size: 20),
            visualDensity: VisualDensity.compact,
            isSelected: state.selectedTextItem!.bold,
            color: state.selectedTextItem!.bold
                ? Theme.of(context).colorScheme.primary
                : null,
            onPressed: actions.toggleBold,
          ),
          IconButton(
            tooltip: '斜体 (Ctrl+I)',
            icon: const Icon(Icons.format_italic, size: 20),
            visualDensity: VisualDensity.compact,
            isSelected: state.selectedTextItem!.italic,
            color: state.selectedTextItem!.italic
                ? Theme.of(context).colorScheme.primary
                : null,
            onPressed: actions.toggleItalic,
          ),
          IconButton(
            tooltip: '下划线 (Ctrl+U)',
            icon: const Icon(Icons.format_underline, size: 20),
            visualDensity: VisualDensity.compact,
            isSelected: state.selectedTextItem!.underline,
            color: state.selectedTextItem!.underline
                ? Theme.of(context).colorScheme.primary
                : null,
            onPressed: actions.toggleUnderline,
          ),
          IconButton(
            tooltip: '删除线 (Ctrl+Shift+X)',
            icon: const Icon(Icons.strikethrough_s, size: 20),
            visualDensity: VisualDensity.compact,
            isSelected: state.selectedTextItem!.strikethrough,
            color: state.selectedTextItem!.strikethrough
                ? Theme.of(context).colorScheme.primary
                : null,
            onPressed: actions.toggleStrikethrough,
          ),
          IconButton(
            tooltip: alignTooltip(context, state.selectedTextItem!.align),
            icon: Icon(
              alignIcon(state.selectedTextItem!.align),
              size: 20,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: actions.cycleAlign,
          ),
        ],
        // 选中形状：样式控件
        if (state.selectedShape != null) ...[
          const Icon(Icons.line_weight, size: 18),
          SizedBox(
            width: 80,
            child: Slider(
              value: state.selectedShape!.strokeWidth.clamp(1, 20),
              min: 1,
              max: 20,
              onChanged: actions.onShapeStrokeWidth,
            ),
          ),
          const Icon(Icons.opacity, size: 18),
          SizedBox(
            width: 80,
            child: Slider(
              value: state.selectedShape!.fillColor != null ? 1.0 : 0.0,
              min: 0,
              max: 1,
              onChanged: actions.onShapeOpacity,
            ),
          ),
          IconButton(
            tooltip: '切换填充色',
            icon: Icon(
              state.selectedShape!.fillColor != null
                  ? Icons.format_color_fill
                  : Icons.format_color_reset,
              size: 20,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: actions.onShapeFillColor,
          ),
        ],
        if (state.selectedShape != null)
          IconButton(
            tooltip: '实线/虚线切换',
            icon: Icon(
              state.selectedShape!.dash ? Icons.more_horiz : Icons.remove,
              size: 20,
            ),
            isSelected: state.selectedShape!.dash,
            color: state.selectedShape!.dash
                ? Theme.of(context).colorScheme.primary
                : null,
            onPressed: actions.onToggleDash,
          ),
        IconButton(
          tooltip: '编辑文字',
          icon: const Icon(Icons.edit_outlined, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: actions.editText,
        ),
        IconButton(
          tooltip: '删除选中对象',
          icon: const Icon(Icons.delete_outline, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: actions.deleteSelected,
        ),
      ],
    );
  }
}
