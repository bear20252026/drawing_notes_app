import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/presentation/toolbar_state_mapper.dart';

/// 阶段五提取（2026-08-15）：工具栏状态映射纯函数可测性验证。
void main() {
  DrawingController controller() {
    final doc = DrawingDocument(id: 'toolbar_map', title: '映射测试');
    return DrawingController(doc);
  }

  const flags = ToolbarUiFlags(
    isNotebookMode: true,
    eyedropperActive: true,
    textToolActive: true,
    linkMode: true,
    shapeFillEnabled: true,
    marqueeActive: true,
    gridVisible: true,
    snapToGrid: true,
  );

  test('mapEditorToolbarState：画笔工具映射（controller 承载状态）', () {
    final c = controller();
    final state = mapEditorToolbarState(c, flags);

    expect(state.isEraser, isFalse);
    expect(state.showNoteTools, isTrue, reason: 'flags.isNotebookMode 透传');
    expect(state.eyedropperActive, isTrue);
    expect(state.linkMode, isTrue);
    expect(state.gridVisible, isTrue);
    expect(state.snapToGrid, isTrue);
    expect(state.selectionTool, c.selectionTool);
    expect(state.color, c.color);
    expect(state.paperType, c.document.paperType);
    expect(state.activeSize, c.brushSize);
  });

  test('mapEditorToolbarState：橡皮擦映射（activeSize 用 eraserSize）', () {
    final c = controller();
    c.tool = BrushType.eraser;
    final state = mapEditorToolbarState(c, flags);

    expect(state.isEraser, isTrue);
    expect(state.activeSize, c.eraserSize);
    expect(state.pixelEraser, c.eraserMode == EraserMode.pixel);
  });
}
