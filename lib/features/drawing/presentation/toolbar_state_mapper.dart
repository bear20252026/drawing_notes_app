import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_toolbar.dart';

/// 工具栏 UI 标志（状态提升：State 私有字段聚合为纯数据传入映射函数）。
///
/// 阶段五提取（2026-08-15）：_buildContextBar 的 state 组装（23 数据源）
/// 拆分——controller 承载的 11 个状态留在映射函数内读取，State 私有的
/// 12 个字段聚合为本纯数据类传入（useDesigner 状态映射 + state hoisting
/// 模式：widget 接收状态、映射归属独立纯函数）。
class ToolbarUiFlags {
  const ToolbarUiFlags({
    required this.isNotebookMode,
    required this.eyedropperActive,
    required this.textToolActive,
    required this.linkMode,
    this.selectedItemId,
    this.selectedTextItem,
    this.activeShape,
    this.selectedShape,
    required this.shapeFillEnabled,
    required this.marqueeActive,
    required this.gridVisible,
    required this.snapToGrid,
  });

  final bool isNotebookMode;
  final bool eyedropperActive;
  final bool textToolActive;
  final bool linkMode;
  final String? selectedItemId;
  final PageTextItem? selectedTextItem;
  final ShapeType? activeShape;
  final PageShapeItem? selectedShape;
  final bool shapeFillEnabled;
  final bool marqueeActive;
  final bool gridVisible;
  final bool snapToGrid;
}

/// controller 状态 + UI 标志 → 工具栏只读状态（纯映射，可单测）。
EditorToolbarState mapEditorToolbarState(
  DrawingController controller,
  ToolbarUiFlags flags,
) {
  final isEraser = controller.tool == BrushType.eraser;
  return EditorToolbarState(
    isEraser: isEraser,
    isHighlighter: controller.tool == BrushType.marker,
    isLaser: controller.tool == BrushType.laser,
    temporaryMarkerEnabled: controller.temporaryMarkerEnabled,
    activeSize: isEraser ? controller.eraserSize : controller.brushSize,
    showNoteTools: flags.isNotebookMode,
    eyedropperActive: flags.eyedropperActive,
    textToolActive: flags.textToolActive,
    selectionTool: controller.selectionTool,
    linkMode: flags.linkMode,
    color: controller.color,
    paperType: controller.document.paperType,
    selectedItemId: flags.selectedItemId,
    selectedTextItem: flags.selectedTextItem,
    activeShape: flags.activeShape,
    selectedShape: flags.selectedShape,
    shapeFillEnabled: flags.shapeFillEnabled,
    marqueeActive: flags.marqueeActive,
    pixelEraser: controller.eraserMode == EraserMode.pixel,
    eraserCanEraseShapesStroke: controller.eraserCanEraseShapesStroke,
    eraserCanEraseShapesPixel: controller.eraserCanEraseShapesPixel,
    gridVisible: flags.gridVisible,
    snapToGrid: flags.snapToGrid,
  );
}
