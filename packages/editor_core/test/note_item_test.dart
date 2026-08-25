import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——NoteItem 便签块测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('NoteItem：copyWith 不可变', () {
    const note = NoteItem(id: 'n1', content: 'hello', x: 10, y: 20);
    final updated = note.copyWith(content: 'world', backgroundColor: '#FFCDD2');
    expect(note.content, 'hello'); // 原实例不变。
    expect(note.backgroundColor, '#FFF9C4'); // 默认黄便签。
    expect(updated.content, 'world');
    expect(updated.backgroundColor, '#FFCDD2');
  });

  test('NoteItem：默认值（AFFiNE 风格——黄便签 200x150）', () {
    const note = NoteItem(id: 'n1', content: 'hi', x: 0, y: 0);
    expect(note.width, 200);
    expect(note.height, 150);
    expect(note.backgroundColor, '#FFF9C4');
  });

  test('CreateNoteCommand：创建便签到图层 + 撤销', () {
    const doc = DocumentV2(id: 'doc1', pageCount: 1, layers: [
      LayerV2(id: 'l1', name: 'Layer 1'),
    ]);
    final reducer = DocumentReducer(doc);
    const note = NoteItem(id: 'n1', content: 'sticky', x: 10, y: 20);

    final newState = reducer.execute(
      const CreateNoteCommand(layerId: 'l1', note: note),
    );
    expect(newState.layers.first.notes.length, 1);
    expect(newState.layers.first.notes.first.content, 'sticky');

    final undone = reducer.undo();
    expect(undone!.layers.first.notes.length, 0);
  });

  test('RemoveNoteCommand：移除便签', () {
    const doc = DocumentV2(id: 'doc1', pageCount: 1, layers: [
      LayerV2(id: 'l1', name: 'Layer 1', notes: [
        NoteItem(id: 'n1', content: 'a', x: 0, y: 0),
        NoteItem(id: 'n2', content: 'b', x: 0, y: 0),
      ]),
    ]);
    final reducer = DocumentReducer(doc);
    final newState = reducer.execute(
      const RemoveNoteCommand(layerId: 'l1', noteId: 'n1'),
    );
    expect(newState.layers.first.notes.length, 1);
    expect(newState.layers.first.notes.first.id, 'n2');
  });
}
