import 'package:material_ui/material_ui.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/features/drawing/application/plugin_registry.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';

/// 编辑器工具栏（架构重构 R2：从 editor_page 外移，回调参数化）。
///
/// 设计原则（见 docs/ARCHITECTURE_REVISION.md）：
/// - 本组件**只负责工具栏 UI 布局**，不含业务逻辑；
/// - 所有状态经 [EditorToolbarState] 传入（只读）；
/// - 所有操作经 [EditorToolbarActions] 回调返回（由 editor_page 实现）；
/// - 不读写文件、不直接操作引擎——纯展示层。
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.state,
    required this.actions,
    required this.brushes,
  });

  final EditorToolbarState state;
  final EditorToolbarActions actions;
  final List<BrushExtension> brushes;

  @override
  Widget build(BuildContext context) {
    final isEraser = state.isEraser;
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            _toolButton(
              context,
              icon: Icons.brush,
              tooltip: '画笔',
              selected:
                  !isEraser && !state.eyedropperActive && !state.textToolActive,
              onTap: actions.selectBrush,
            ),
            // 笔刷扩展菜单（B3：由插件注册表驱动）
            PopupMenuButton<String>(
              tooltip: '笔刷（插件扩展）',
              icon: const Icon(Icons.brush_outlined, size: 20),
              onSelected: actions.onBrushSelected,
              itemBuilder: (_) => [
                for (final b in brushes)
                  PopupMenuItem(value: b.id, child: Text(b.name)),
              ],
            ),
            _toolButton(
              context,
              icon: Icons.auto_fix_high,
              tooltip: '橡皮擦（透明擦除）',
              selected:
                  isEraser && !state.eyedropperActive && !state.textToolActive,
              onTap: actions.selectEraser,
            ),
            // 橡皮擦形状擦除开关（问题3）：整笔/透明模式各自决定
            // 是否擦除标准直线/图案，两个按钮可独立开关。
            if (isEraser)
              PopupMenuButton<VoidCallback>(
                tooltip: '标准形状擦除设置',
                icon: const Icon(Icons.shape_line_outlined, size: 20),
                onSelected: (callback) => callback(),
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    checked: state.eraserCanEraseShapesStroke,
                    value: () => actions.setEraserCanEraseShapesStroke(
                      !state.eraserCanEraseShapesStroke,
                    ),
                    child: const Text('整笔模式擦除标准形状'),
                  ),
                  CheckedPopupMenuItem(
                    checked: state.eraserCanEraseShapesPixel,
                    value: () => actions.setEraserCanEraseShapesPixel(
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
            // 笔记模式专用工具（Phase 5）
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
                tooltip: state.linkMode ? '连线中：点击两个元素创建连接' : '连线工具（依次点击两个元素）',
                selected: state.linkMode,
                onTap: actions.toggleLink,
              ),
              _toolButton(
                context,
                icon: Icons.menu_book,
                tooltip:
                    AppLocalizations.of(context)?.editorPdfPreview ??
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
                  return l10n?.editorPaperTemplate(name) ?? '纸张模板：$name（点击切换）';
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
              // 形状工具（矩形/椭圆/菱形/箭头/直线，借鉴 Excalidraw 图形工具）
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
              // 形状填充模式开关（问题4）：开启后新建形状默认带填充色。
              if (state.activeShape != null)
                IconButton(
                  tooltip: state.shapeFillEnabled
                      ? (AppLocalizations.of(context)?.editorShapeFillOn ??
                            '形状填充：开（新建形状默认填充）')
                      : (AppLocalizations.of(context)?.editorShapeFillOff ??
                            '形状填充：关（新建形状默认填充）'),
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
              // 等间距分布（水平/垂直，借鉴 Excalidraw 对齐/分布工具）
              PopupMenuButton<bool>(
                tooltip: '等间距分布',
                icon: const Icon(Icons.space_bar, size: 20),
                onSelected: actions.onDistribute,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: true, child: Text('水平等间距分布')),
                  PopupMenuItem(value: false, child: Text('垂直等间距分布')),
                ],
              ),
              // 框选工具（矩形框选多元素，借鉴 Excalidraw 多选）
              IconButton(
                tooltip: '框选（拖动选中多个元素）',
                icon: const Icon(Icons.select_all, size: 20),
                isSelected: state.marqueeActive,
                color: state.marqueeActive
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onPressed: actions.onToggleMarquee,
              ),
              // 图层顺序（置顶/置底/上移/下移，借鉴 Excalidraw 图层操作）
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
              // 网格显示开关（借鉴 Excalidraw 画布导航）
              IconButton(
                tooltip: '网格显示',
                icon: const Icon(Icons.grid_4x4, size: 20),
                isSelected: state.gridVisible,
                color: state.gridVisible
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onPressed: actions.onToggleGrid,
              ),
              // 网格吸附开关（借鉴 Excalidraw）
              IconButton(
                tooltip: '网格吸附',
                icon: const Icon(Icons.auto_fix_high, size: 20),
                isSelected: state.snapToGrid,
                color: state.snapToGrid
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onPressed: actions.onToggleSnap,
              ),
              // 适应画布（Fit to Screen，借鉴 Excalidraw 导航）
              IconButton(
                tooltip: '适应画布',
                icon: const Icon(Icons.fit_screen, size: 20),
                onPressed: actions.onFitToScreen,
              ),
              // 缩放控件组（放大/缩小/100%，借鉴 Excalidraw 缩放导航）
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
            // 当前颜色选择圆点
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Tooltip(
                message: '选择颜色',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: actions.showColorPicker,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: state.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 粗细滑块
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  const Icon(Icons.line_weight, size: 18),
                  Expanded(
                    child: Slider(
                      value: state.activeSize.clamp(1, 100),
                      min: 1,
                      max: 100,
                      onChanged: actions.onSizeChanged,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${state.activeSize.round()}px',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            // 混排对象编辑按钮（有选中对象时显示）
            if (state.selectedItemId != null) ...[
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
                // 文字颜色
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
              // 选中形状：样式控件（线宽/透明度/填充色，借鉴 Excalidraw 样式面板）
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
              // 选中形状：实线/虚线切换（借鉴 Excalidraw 线样式面板）
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
            // 模式提示文本
            if (state.eyedropperActive)
              Text(
                '点击画布取色',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            else if (state.textToolActive)
              Text(
                '点击画布放置文字',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            else
              Text(
                isEraser ? '橡皮擦' : '画笔',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
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
}

/// 工具栏只读状态（由 editor_page 在监听 controller 后构造传入）。
class EditorToolbarState {
  const EditorToolbarState({
    required this.isEraser,
    this.isHighlighter = false,
    this.isLaser = false,
    this.temporaryMarkerEnabled = false,
    required this.activeSize,
    required this.showNoteTools,
    required this.eyedropperActive,
    required this.textToolActive,
    required this.selectionTool,
    required this.linkMode,
    required this.color,
    required this.paperType,
    this.selectedItemId,
    this.selectedTextItem,
    this.activeShape,
    this.selectedShape,
    this.shapeFillEnabled = false,
    this.marqueeActive = false,
    this.pixelEraser = false,
    this.eraserCanEraseShapesStroke = true,
    this.eraserCanEraseShapesPixel = true,
    this.gridVisible = false,
    this.snapToGrid = false,
  });

  final bool isEraser;

  /// 当前是否为高亮笔、激光工具，以及高亮笔是否以临时墨迹模式书写。
  final bool isHighlighter;
  final bool isLaser;
  final bool temporaryMarkerEnabled;

  final double activeSize;
  final bool showNoteTools;
  final bool eyedropperActive;
  final bool textToolActive;
  final SelectionTool selectionTool;
  final bool linkMode;
  final Color color;
  final PaperType paperType;
  final String? selectedItemId;
  final PageTextItem? selectedTextItem;

  /// 当前激活的形状工具（null = 未激活，借鉴 Excalidraw 图形工具）。
  final ShapeType? activeShape;

  /// 选中的形状元素（选中形状时显示样式控件）。
  final PageShapeItem? selectedShape;

  /// 形状填充模式开关（问题4）：开启后新建形状默认带填充色。
  final bool shapeFillEnabled;

  /// 框选工具是否激活（矩形框选多元素，借鉴 Excalidraw 多选）。
  final bool marqueeActive;

  /// 橡皮擦为 true 时以透明像素挖空；false 时命中整笔删除。
  final bool pixelEraser;

  /// 标准形状擦除开关（问题3）：整笔模式是否可擦除标准直线/图案。
  final bool eraserCanEraseShapesStroke;

  /// 标准形状擦除开关（问题3）：透明模式是否可擦除标准直线/图案。
  final bool eraserCanEraseShapesPixel;

  /// 网格显示开关（借鉴 Excalidraw 画布导航）。
  final bool gridVisible;

  /// 网格吸附开关（拖动吸附 20px 网格，借鉴 Excalidraw）。
  final bool snapToGrid;
}

/// 工具栏操作回调集（由 editor_page 实现，闭包内执行业务逻辑）。
class EditorToolbarActions {
  const EditorToolbarActions({
    required this.selectBrush,
    required this.selectEraser,
    required this.setPixelEraserMode,
    required this.setEraserCanEraseShapesStroke,
    required this.setEraserCanEraseShapesPixel,
    required this.setTemporaryMarkerEnabled,
    required this.selectEyedropper,
    required this.selectRect,
    required this.selectLasso,
    required this.selectText,
    required this.recolorAllText,
    required this.toggleLink,
    required this.showPagination,
    required this.addStickyNote,
    required this.cyclePaper,
    required this.insertImage,
    required this.showColorPicker,
    required this.onSizeChanged,
    required this.onSelectedFontSize,
    required this.changeTextColor,
    required this.toggleBold,
    required this.toggleItalic,
    required this.toggleUnderline,
    required this.toggleStrikethrough,
    required this.cycleAlign,
    required this.editText,
    required this.deleteSelected,
    required this.onBrushSelected,
    required this.onSelectShape,
    required this.setShapeFillEnabled,
    required this.onDistribute,
    required this.onShapeStrokeWidth,
    required this.onShapeOpacity,
    required this.onShapeFillColor,
    required this.onToggleMarquee,
    required this.onReorder,
    required this.onToggleGrid,
    required this.onToggleSnap,
    required this.onFitToScreen,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onToggleDash,
  });

  final VoidCallback selectBrush;
  final VoidCallback selectEraser;

  /// 橡皮擦模式：false=命中整笔删除，true=透明像素挖空。
  final ValueChanged<bool> setPixelEraserMode;

  /// 整笔模式是否可擦除标准形状（问题3）。
  final ValueChanged<bool> setEraserCanEraseShapesStroke;

  /// 透明模式是否可擦除标准形状（问题3）。
  final ValueChanged<bool> setEraserCanEraseShapesPixel;

  /// 临时高亮笔开关：启用后墨迹平滑淡出且不写入文档。
  final ValueChanged<bool> setTemporaryMarkerEnabled;

  final VoidCallback selectEyedropper;
  final VoidCallback selectRect;
  final VoidCallback selectLasso;
  final VoidCallback selectText;
  final VoidCallback recolorAllText;
  final VoidCallback toggleLink;
  final VoidCallback showPagination;
  final VoidCallback addStickyNote;
  final VoidCallback cyclePaper;
  final VoidCallback insertImage;
  final VoidCallback showColorPicker;
  final ValueChanged<double> onSizeChanged;
  final ValueChanged<double> onSelectedFontSize;
  final VoidCallback changeTextColor;
  final VoidCallback toggleBold;
  final VoidCallback toggleItalic;
  final VoidCallback toggleUnderline;
  final VoidCallback toggleStrikethrough;
  final VoidCallback cycleAlign;
  final VoidCallback editText;
  final VoidCallback deleteSelected;
  final ValueChanged<String> onBrushSelected;

  /// 选择形状工具（矩形/椭圆/菱形/箭头/直线，借鉴 Excalidraw）。
  final ValueChanged<ShapeType> onSelectShape;

  /// 形状填充模式开关（问题4）：新建形状是否默认填充。
  final ValueChanged<bool> setShapeFillEnabled;

  /// 等间距分布（true=水平，false=垂直，借鉴 Excalidraw 对齐/分布）。
  final ValueChanged<bool> onDistribute;

  /// 选中形状：调整线宽。
  final ValueChanged<double> onShapeStrokeWidth;

  /// 选中形状：调整透明度（0.0~1.0）。
  final ValueChanged<double> onShapeOpacity;

  /// 选中形状：切换/选择填充色（借鉴 Excalidraw 样式面板）。
  final VoidCallback onShapeFillColor;

  /// 框选工具开关（矩形框选多个混排对象，借鉴 Excalidraw 多选）。
  final VoidCallback onToggleMarquee;

  /// 图层顺序操作（0=置顶/1=置底/2=上移/3=下移，借鉴 Excalidraw 图层操作）。
  final ValueChanged<int> onReorder;

  /// 网格显示开关（借鉴 Excalidraw 画布导航）。
  final VoidCallback onToggleGrid;

  /// 网格吸附开关（拖动吸附 20px 网格，借鉴 Excalidraw）。
  final VoidCallback onToggleSnap;

  /// 适应画布（Fit to Screen）。
  final VoidCallback onFitToScreen;

  /// 缩放控件：放大（借鉴 Excalidraw 缩放导航）。
  final VoidCallback onZoomIn;

  /// 缩放控件：缩小。
  final VoidCallback onZoomOut;

  /// 缩放控件：恢复 100%。
  final VoidCallback onZoomReset;

  /// 选中形状：实线/虚线切换（借鉴 Excalidraw 线样式面板）。
  final VoidCallback onToggleDash;
}

/// 纸张模板类型对应的图标。
IconData paperTypeIcon(PaperType type) => switch (type) {
  PaperType.blank => Icons.crop_portrait,
  PaperType.grid => Icons.grid_on,
  PaperType.lined => Icons.subject,
  PaperType.dot => Icons.more_horiz,
};

/// 纸张模板类型的中文名。
/// 纸张模板本地化名称（国际化收尾 2026-08-16；l10n 为空回落中文）。
String paperTypeName(PaperType type, AppLocalizations? l10n) => switch (type) {
  PaperType.blank => l10n?.paperBlank ?? '空白',
  PaperType.grid => l10n?.paperGrid ?? '网格',
  PaperType.lined => l10n?.paperLined ?? '横线',
  PaperType.dot => l10n?.paperDot ?? '点阵',
};

/// 文字对齐方式对应的图标。
IconData alignIcon(TextAlignType align) => switch (align) {
  TextAlignType.left => Icons.format_align_left,
  TextAlignType.center => Icons.format_align_center,
  TextAlignType.right => Icons.format_align_right,
};

/// 对齐工具提示（本地化——国际化收尾 2026-08-16）。
String alignTooltip(BuildContext context, TextAlignType align) {
  final l10n = AppLocalizations.of(context);
  final name = switch (align) {
    TextAlignType.left => l10n?.alignLeft ?? '左对齐',
    TextAlignType.center => l10n?.alignCenter ?? '居中',
    TextAlignType.right => l10n?.alignRight ?? '右对齐',
  };
  return l10n?.editorAlignTooltip(name) ?? '对齐：$name (Ctrl+E)';
}

/// 形状类型对应的图标（借鉴 Excalidraw 图形工具）。
IconData shapeTypeIcon(ShapeType type) => switch (type) {
  ShapeType.rect => Icons.crop_square,
  ShapeType.ellipse => Icons.circle_outlined,
  ShapeType.diamond => Icons.diamond_outlined,
  ShapeType.arrow => Icons.arrow_forward,
  ShapeType.line => Icons.remove,
};

/// 形状类型的中文名。
String shapeTypeName(ShapeType type) => switch (type) {
  ShapeType.rect => '矩形',
  ShapeType.ellipse => '椭圆',
  ShapeType.diamond => '菱形',
  ShapeType.arrow => '箭头',
  ShapeType.line => '直线',
};
