import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——InlineEditState 行内编辑测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('InlineEditState：初始 idle 状态', () {
    const state = InlineEditState();
    expect(state.phase, InlineEditPhase.idle);
    expect(state.isEditing, false);
    expect(state.hasChanges, false);
  });

  test('InlineEditState：startEditing（idle → editing）', () {
    const idle = InlineEditState();
    final editing = idle.startEditing('elem1', 'Hello', TextFormat.boldStyle);
    expect(editing.phase, InlineEditPhase.editing);
    expect(editing.isEditing, true);
    expect(editing.elementId, 'elem1');
    expect(editing.content, 'Hello');
    expect(editing.originalContent, 'Hello');
    expect(editing.format.bold, true);
    expect(editing.cursor.offset, 5); // 光标在末尾。
  });

  test('InlineEditState：insertText（输入字符）', () {
    final editing = const InlineEditState().startEditing('e1', 'Hello', TextFormat());
    final inserted = editing.insertText(' World');
    expect(inserted.content, 'Hello World');
    expect(inserted.cursor.offset, 11);
    expect(inserted.hasChanges, true);
  });

  test('InlineEditState：deleteBackward（退格删除）', () {
    final editing = const InlineEditState().startEditing('e1', 'Hello', TextFormat());
    final deleted = editing.deleteBackward();
    expect(deleted.content, 'Hell');
    expect(deleted.cursor.offset, 4);
  });

  test('InlineEditState：deleteBackward 边界（光标在 0）', () {
    final editing = const InlineEditState()
        .startEditing('e1', 'Hello', TextFormat())
        .moveCursor(0);
    final deleted = editing.deleteBackward();
    expect(deleted.content, 'Hello'); // 不变。
  });

  test('InlineEditState：moveCursor（光标移动）', () {
    final editing = const InlineEditState().startEditing('e1', 'Hello', TextFormat());
    final moved = editing.moveCursor(2);
    expect(moved.cursor.offset, 2);
    // 越界——clamp 到边界。
    expect(editing.moveCursor(100).cursor.offset, 5);
    expect(editing.moveCursor(-1).cursor.offset, 0);
  });

  test('InlineEditState：toggleBold/toggleItalic（格式切换）', () {
    final editing = const InlineEditState().startEditing('e1', 'Hello', TextFormat());
    final bold = editing.toggleBold();
    expect(bold.format.bold, true);
    final boldItalic = bold.toggleItalic();
    expect(boldItalic.format.bold, true);
    expect(boldItalic.format.italic, true);
  });

  test('InlineEditState：commit（editing → committing）', () {
    final editing = const InlineEditState().startEditing('e1', 'Hello', TextFormat());
    final committed = editing.commit();
    expect(committed.phase, InlineEditPhase.committing);
    expect(committed.hasChanges, false); // 内容未变。
  });

  test('InlineEditState：abort（editing → aborting——恢复原值）', () {
    final editing = const InlineEditState().startEditing('e1', 'Hello', TextFormat.boldStyle);
    final inserted = editing.insertText(' World');
    expect(inserted.hasChanges, true);
    final aborted = inserted.abort();
    expect(aborted.phase, InlineEditPhase.aborting);
    expect(aborted.content, 'Hello'); // 恢复原值。
    expect(aborted.format.bold, true); // 恢复原格式。
  });

  test('InlineEditState：finish（committing/aborting → idle）', () {
    final committed = const InlineEditState()
        .startEditing('e1', 'Hello', TextFormat())
        .commit();
    final finished = committed.finish();
    expect(finished.phase, InlineEditPhase.idle);
  });

  test('CursorPosition：hasSelection/selectionLength', () {
    const noSelection = CursorPosition(offset: 5);
    expect(noSelection.hasSelection, false);
    expect(noSelection.selectionLength, 0);
    const withSelection = CursorPosition(offset: 2, selectionEnd: 7);
    expect(withSelection.hasSelection, true);
    expect(withSelection.selectionLength, 5);
  });

  test('InlineEditState：相等性', () {
    final a = const InlineEditState().startEditing('e1', 'Hello', TextFormat());
    final b = const InlineEditState().startEditing('e1', 'Hello', TextFormat());
    expect(a, b);
  });
}
