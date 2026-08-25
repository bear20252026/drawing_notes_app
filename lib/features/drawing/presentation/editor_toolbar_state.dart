import 'package:flutter/material.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';

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
