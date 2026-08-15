import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/features/drawing/presentation/editor_toolbar.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

/// 编辑器上下文工具条。
///
/// 仅展示当前任务必要的参数：未选中对象时显示画笔设置；选中文本或
/// 形状时显示对应属性。工具选择统一交给左侧工具条，低频功能收纳至
/// 主菜单与可展开的侧栏，避免横向工具栏挤压画布。
class EditorContextBar extends StatelessWidget {
  const EditorContextBar({
    super.key,
    required this.state,
    required this.actions,
  });

  final EditorToolbarState state;
  final EditorToolbarActions actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      borderRadius: BorderRadius.zero,
      sigma: 8,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          height: 52,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              final controls = state.selectedTextItem != null
                  ? _buildTextControls(context)
                  : state.selectedShape != null
                  ? _buildShapeControls(context)
                  : _buildDrawingControls(context);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: controls,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 12),
                      _buildModeHint(context),
                    ] else
                      Tooltip(
                        message: _modeDescription,
                        child: Icon(
                          _modeIcon,
                          size: 18,
                          color: _modeIsActive
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDrawingControls(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _colorButton(
          context,
          color: state.color,
          tooltip: AppLocalizations.of(context)?.editorStrokeColor ?? '笔触颜色',
          onPressed: actions.showColorPicker,
        ),
        const SizedBox(width: 8),
        const Icon(Icons.line_weight, size: 18),
        SizedBox(
          width: 132,
          child: Slider(
            value: state.activeSize.clamp(1, 100),
            min: 1,
            max: 100,
            label: '${state.activeSize.round()} px',
            onChanged: actions.onSizeChanged,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '${state.activeSize.round()} px',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        if (state.isEraser) ...[
          const SizedBox(width: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.format_paint_outlined, size: 18),
                label: Text('整笔'),
                tooltip: AppLocalizations.of(context)?.editorEraseStroke ?? '命中笔画即删除整条线',
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.auto_fix_high_outlined, size: 18),
                label: Text('透明'),
                tooltip: AppLocalizations.of(context)?.editorEraseTransparent ?? '以透明像素挖空当前图层',
              ),
            ],
            selected: {state.pixelEraser},
            onSelectionChanged: (selection) =>
                actions.setPixelEraserMode(selection.first),
          ),
        ],
        if (state.isHighlighter) ...[
          const SizedBox(width: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.save_outlined, size: 18),
                label: Text('保存'),
                tooltip: AppLocalizations.of(context)?.editorHighlightNormal ?? '作为普通高亮笔写入页面，可撤销、保存和导出',
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.gesture_rounded, size: 18),
                label: Text('自动消失'),
                tooltip: AppLocalizations.of(context)?.editorLaserTemporary ?? '仅短暂显示，约 4 秒后平滑淡出，不写入页面',
              ),
            ],
            selected: {state.temporaryMarkerEnabled},
            onSelectionChanged: (selection) =>
                actions.setTemporaryMarkerEnabled(selection.first),
          ),
        ],
      ],
    );
  }

  Widget _buildTextControls(BuildContext context) {
    final text = state.selectedTextItem!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.format_size, size: 18),
        SizedBox(
          width: 120,
          child: Slider(
            value: text.fontSize.clamp(8, 200),
            min: 8,
            max: 200,
            label: '${text.fontSize.round()}',
            onChanged: actions.onSelectedFontSize,
          ),
        ),
        SizedBox(width: 34, child: Text('${text.fontSize.round()}')),
        _colorButton(
          context,
          color: Color(text.color),
          tooltip: AppLocalizations.of(context)?.editorTextColor ?? '文字颜色',
          onPressed: actions.changeTextColor,
        ),
        _toggleButton(
          context,
          icon: Icons.format_bold,
          tooltip: AppLocalizations.of(context)?.editorBold ?? '加粗 (Ctrl+B)',
          selected: text.bold,
          onPressed: actions.toggleBold,
        ),
        _toggleButton(
          context,
          icon: Icons.format_italic,
          tooltip: AppLocalizations.of(context)?.editorItalic ?? '斜体 (Ctrl+I)',
          selected: text.italic,
          onPressed: actions.toggleItalic,
        ),
        _toggleButton(
          context,
          icon: Icons.format_underline,
          tooltip: AppLocalizations.of(context)?.editorUnderline ?? '下划线 (Ctrl+U)',
          selected: text.underline,
          onPressed: actions.toggleUnderline,
        ),
        _toggleButton(
          context,
          icon: alignIcon(text.align),
          tooltip: '对齐：${alignName(text.align)} (Ctrl+E)',
          selected: false,
          onPressed: actions.cycleAlign,
        ),
      ],
    );
  }

  Widget _buildShapeControls(BuildContext context) {
    final shape = state.selectedShape!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.line_weight, size: 18),
        SizedBox(
          width: 96,
          child: Slider(
            value: shape.strokeWidth.clamp(1, 20),
            min: 1,
            max: 20,
            label: '${shape.strokeWidth.round()} px',
            onChanged: actions.onShapeStrokeWidth,
          ),
        ),
        _toggleButton(
          context,
          icon: shape.fillColor != null
              ? Icons.format_color_fill
              : Icons.format_color_reset,
          tooltip: '切换填充色',
          selected: shape.fillColor != null,
          onPressed: actions.onShapeFillColor,
        ),
        _toggleButton(
          context,
          icon: shape.dash ? Icons.more_horiz : Icons.remove,
          tooltip: '实线 / 虚线',
          selected: shape.dash,
          onPressed: actions.onToggleDash,
        ),
        IconButton(
          tooltip: '删除选中对象',
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: actions.deleteSelected,
        ),
      ],
    );
  }

  String get _modeDescription => state.eyedropperActive
      ? '点击画布取色'
      : state.textToolActive
      ? '点击画布放置文字'
      : state.linkMode
      ? '依次选择两个元素建立连接'
      : state.isEraser
      ? (state.pixelEraser ? '透明像素擦除' : '整笔删除')
      : state.isHighlighter
      ? (state.temporaryMarkerEnabled ? '临时高亮：约 4 秒后自动消失' : '高亮笔：将保存到页面')
      : state.isLaser
      ? '激光指示器：释放后从起笔端逐段消退，不会保存'
      : '画笔';

  bool get _modeIsActive =>
      state.eyedropperActive || state.textToolActive || state.linkMode;

  IconData get _modeIcon => state.eyedropperActive
      ? Icons.colorize_outlined
      : state.textToolActive
      ? Icons.text_fields_rounded
      : state.linkMode
      ? Icons.link_rounded
      : state.isEraser
      ? Icons.auto_fix_high_outlined
      : state.isLaser
      ? Icons.gesture_rounded
      : Icons.brush_outlined;

  Widget _buildModeHint(BuildContext context) => Text(
    _modeDescription,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: _modeIsActive ? Theme.of(context).colorScheme.primary : null,
    ),
  );

  Widget _colorButton(
    BuildContext context, {
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggleButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      isSelected: selected,
      color: selected ? Theme.of(context).colorScheme.primary : null,
      onPressed: onPressed,
    );
  }
}
