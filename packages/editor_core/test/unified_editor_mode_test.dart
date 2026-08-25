import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Saber 借鉴——UnifiedEditorMode 统一编辑器模式测试（纯逻辑——不搞崩）。
void main() {
  test('默认模式：note（分页——笔记端）', () {
    const state = UnifiedEditorState();
    expect(state.mode, UnifiedEditorMode.note);
    expect(state.pagedEnabled, true);
    expect(state.infiniteCanvasEnabled, false);
    expect(state.showSidebar, true);
    expect(state.showLayerPanel, true);
  });

  test('switchMode：note → whiteboard（特殊功能切换——无限画布）', () {
    const state = UnifiedEditorState();
    final whiteboard = state.switchMode(UnifiedEditorMode.whiteboard);
    expect(whiteboard.mode, UnifiedEditorMode.whiteboard);
    expect(whiteboard.isWhiteboard, true);
    expect(whiteboard.pagedEnabled, false); // 画板无分页。
    expect(whiteboard.infiniteCanvasEnabled, true); // 画板无限画布。
  });

  test('switchMode：whiteboard → note（分页——笔记端）', () {
    var state = const UnifiedEditorState().switchMode(UnifiedEditorMode.whiteboard);
    state = state.switchMode(UnifiedEditorMode.note);
    expect(state.mode, UnifiedEditorMode.note);
    expect(state.isNote, true);
    expect(state.pagedEnabled, true); // 笔记分页。
    expect(state.infiniteCanvasEnabled, false); // 笔记无无限画布。
  });

  test('note()/whiteboard()：静态工厂', () {
    final note = UnifiedEditor.note();
    expect(note.isNote, true);
    expect(UnifiedEditor.isPaged(note), true);
    expect(UnifiedEditor.isInfinite(note), false);

    final whiteboard = UnifiedEditor.whiteboard();
    expect(whiteboard.isWhiteboard, true);
    expect(UnifiedEditor.isPaged(whiteboard), false);
    expect(UnifiedEditor.isInfinite(whiteboard), true);
  });

  test('sharesCore：所有模式共用核心（用户核心要求）', () {
    // 笔记/画板共用：文档/渲染/工具/加密——避免重复维护。
    expect(UnifiedEditor.sharesCore(UnifiedEditor.note()), true);
    expect(UnifiedEditor.sharesCore(UnifiedEditor.whiteboard()), true);
  });

  test('copyWith：不可变 + 相等性', () {
    const state = UnifiedEditorState();
    final updated = state.copyWith(showSidebar: false, showLayerPanel: false);
    expect(state.showSidebar, true); // 原实例不变。
    expect(updated.showSidebar, false);
    expect(updated.showLayerPanel, false);
    // 相等性按 mode。
    const other = UnifiedEditorState(mode: UnifiedEditorMode.note);
    expect(state, other);
  });

  test('UnifiedEditorMode 枚举', () {
    expect(UnifiedEditorMode.values.length, 2);
    expect(UnifiedEditorMode.note.name, 'note');
    expect(UnifiedEditorMode.whiteboard.name, 'whiteboard');
  });
}
