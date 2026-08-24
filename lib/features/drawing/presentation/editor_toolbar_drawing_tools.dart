import 'package:material_ui/material_ui.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'editor_toolbar_helpers.dart';
import 'editor_toolbar_state.dart';

/// 绘图工具区（画笔/橡皮/吸管/选区/文字/形状/缩放）。
///
/// 从 [EditorToolbar] build 方法中拆分，降低主文件行数。
/// 不含任何状态或业务逻辑，纯展示层——所有状态与回调由
/// [EditorToolbarState] / [EditorToolbarActions] 传入。
class DrawingToolsSection extends StatelessWidget {
  const DrawingToolsSection({
    super.key,
    required this.state,
    required this.actions,
  });

  final EditorToolbarState state;
  final EditorToolbarActions actions;

  @override
  Widget build(BuildContext context) {
    final isEraser = state.isEraser;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _toolButton(
          context,
          icon: Icons.brush,
          tooltip: '画笔',
          selected: !isEraser && !state.eyedropperActive && !state.textToolActive,
          onTap: actions.selectBrush,
        ),
        _toolButton(
          context,
          icon: Icons.auto_fix_high,
          tooltip: '橡皮擦（透明擦除）',
          selected: isEraser && !state.eyedropperActive && !state.textToolActive,
          onTap: actions.selectEraser,
        ),
        if (isEraser)
          PopupMenuButton<VoidCallback>(
            tooltip: '标准形状擦除设置',
            icon: const Icon(Icons.shape_line_outlined, size: 20),
            onSelected: (callback) => callback(),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                checked: state.eraserCanEraseShapesStroke,
                value: () =>
                    actions.setEraserCanEraseShapesStroke(
                      !state.eraserCanEraseShapesStroke,
                    ),
                child: const Text('整笔模式擦除标准形状'),
              ),
              CheckedPopupMenuItem(
                checked: state.eraserCanEraseShapesPixel,
                value: () =>
                    actions.setEraserCanEraseShapesPixel(
                      !state.eraserCanEraseShapesPixel,
                    ),
                child: const Text('透明模式擦除标准形状'),
              ),
            ],
          ),
        _toolButton(
          context,
          icon: Icons.colorize,
          tooltip: '吸管取色',
          selected: state.eyedropperActive,
          onTap: actions.selectEyedropper,
        ),
        _toolButton(
          context,
          icon: Icons.crop_square,
          tooltip: '矩形选区',
          selected: state.selectionTool == SelectionTool.rect,
          onTap: actions.selectRect,
        ),
        _toolButton(
          context,
          icon: Icons.gesture,
          tooltip: '套索选区',
          selected: state.selectionTool == SelectionTool.lasso,
          onTap: actions.selectLasso,
        ),
        // 笔记模式专用工具
        if (state.showNoteTools) ...[
          _toolButton(
            context,
            icon: Icons.text_fields,
            tooltip: '文字工具：点击画布直接输入文字',
            selected: state.textToolActive,
            onTap: actions.selectText,
          ),
          _toolButton(
            context,
            icon: Icons.palette,
            tooltip: '宏：全部文字批量改色为当前颜色',
            selected: false,
            onTap: actions.recolorAllText,
          ),
          _toolButton(
            context,
            icon: Icons.timeline,
            tooltip: state.linkMode
                ? '连线中：点击两个元素创建连接'
                : '连线工具（依次点击两个元素）',
            selected: state.linkMode,
            onTap: actions.toggleLink,
          ),
          _toolButton(
            context,
            icon: Icons.menu_book,
            tooltip: AppLocalizations.of(context)?.editorPdfPreview ??
                '分页预览（按 A4 分页）',
            selected: false,
            onTap: actions.showPagination,
          ),
          _toolButton(
            context,
            icon: Icons.sticky_note_2_outlined,
            tooltip: '添加标签（便利贴样式，可拖动）',
            selected: false,
            onTap: actions.addStickyNote,
          ),
          _toolButton(
            context,
            icon: paperTypeIcon(state.paperType),
            tooltip: (() {
              final l10n = AppLocalizations.of(context);
              final name = paperTypeName(state.paperType, l10n);
              return l10n?.editorPaperTemplate(name) ??
                  '纸张模板：$name（点击切换）';
            })(),
            selected: false,
            onTap: actions.cyclePaper,
          ),
          _toolButton(
            context,
            icon: Icons.add_photo_alternate_outlined,
            tooltip: '插入图片',
            selected: false,
            onTap: actions.insertImage,
          ),
          // 形状工具
          PopupMenuButton<ShapeType>(
            tooltip: '形状工具（点击画布放置）',
            icon: Icon(
              state.activeShape != null
                  ? shapeTypeIcon(state.activeShape!)
                  : Icons.category_outlined,
              size: 20,
            ),
            onSelected: actions.onSelectShape,
            itemBuilder: (_) => [
              for (final s in ShapeType.values)
                PopupMenuItem(value: s, child: Text(shapeTypeName(s))),
            ],
          ),
          // 形状填充模式开关
          if (state.activeShape != null)
            IconButton(
              tooltip: state.shapeFillEnabled
                  ? (AppLocalizations.of(context)?.editorShapeFillOn ??
                      '形状填充：开')
                  : (AppLocalizations.of(context)?.editorShapeFillOff ??
                      '形状填充：关'),
              icon: Icon(
                state.shapeFillEnabled
                    ? Icons.format_color_fill
                    : Icons.format_color_reset,
                size: 20,
              ),
              isSelected: state.shapeFillEnabled,
              color: state.shapeFillEnabled
                  ? Theme.of(context).colorScheme.primary
                  : null,
              onPressed: () =>
                  actions.setShapeFillEnabled(!state.shapeFillEnabled),
            ),
          // 等间距分布
          PopupMenuButton<bool>(
            tooltip: '等间距分布',
            icon: const Icon(Icons.space_bar, size: 20),
            onSelected: actions.onDistribute,
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: Text('水平等间距分布')),
              PopupMenuItem(value: false, child: Text('垂直等间距分布')),
            ],
          ),
          // 框选工具
          IconButton(
            tooltip: '框选（拖动选中多个元素）',
            icon: const Icon(Icons.select_all, size: 20),
            isSelected: state.marqueeActive,
            color: state.marqueeActive
                ? Theme.of(context).colorScheme.primary
                : null,
            onPressed: actions.onToggleMarquee,
          ),
          // 图层顺序
          PopupMenuButton<int>(
            tooltip: '图层顺序',
            icon: const Icon(Icons.layers, size: 20),
            onSelected: actions.onReorder,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0, child: Text('置顶')),
              PopupMenuItem(value: 1, child: Text('置底')),
              PopupMenuItem(value: 2, child: Text('上移一层')),
              PopupMenuItem(value: 3, child: Text('下移一层')),
            ],
          ),
          // 网格
          IconButton(
            tooltip: '网格显示',
            icon: const Icon(Icons.grid_4x4, size: 20),
            isSelected: state.gridVisible,
            color: state.gridVisible
                ? Theme.of(context).colorScheme.primary
                : null,
            onPressed: actions.onToggleGrid,
          ),
          // 网格吸附
          IconButton(
            tooltip: '网格吸附',
            icon: const Icon(Icons.auto_fix_high, size: 20),
            isSelected: state.snapToGrid,
            color: state.snapToGrid
                ? Theme.of(context).colorScheme.primary
                : null,
            onPressed: actions.onToggleSnap,
          ),
          // 适应画布
          IconButton(
            tooltip: '适应画布',
            icon: const Icon(Icons.fit_screen, size: 20),
            onPressed: actions.onFitToScreen,
          ),
          // 缩放控件组
          IconButton(
            tooltip: '缩小',
            icon: const Icon(Icons.zoom_out, size: 20),
            onPressed: actions.onZoomOut,
          ),
          IconButton(
            tooltip: '放大',
            icon: const Icon(Icons.zoom_in, size: 20),
            onPressed: actions.onZoomIn,
          ),
          IconButton(
            tooltip: '100%',
            icon: const Icon(Icons.filter_1, size: 20),
            onPressed: actions.onZoomReset,
          ),
        ],
      ],
    );
  }
}

Widget _toolButton(
  BuildContext context, {
  required IconData icon,
  required String tooltip,
  required bool selected,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      isSelected: selected,
      color: selected ? Theme.of(context).colorScheme.primary : null,
      onPressed: onTap,
    ),
  );
}
