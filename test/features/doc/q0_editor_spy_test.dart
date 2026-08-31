// Q0 定位：DocEditor 单元级——enterText 后 onDirty/onSave 是否触发。
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/doc_editor.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

void main() {
  testWidgets('DocEditor：enterText → onDirty → saveNow → onSave 含文本', (
    tester,
  ) async {
    var dirtyCalls = 0;
    NoteBlockDoc? saved;
    final doc = NoteBlockDoc(
      id: 'spy',
      title: '',
      body: [NoteBlock.textBlock('b1', text: '')],
      createdAt: DateTime(2026, 8, 31),
      updatedAt: DateTime(2026, 8, 31),
    );
    await tester.pumpWidget(
      m.MaterialApp(
        home: m.Scaffold(
          body: DocEditor(
            document: doc,
            showChrome: false,
            onDirty: () => dirtyCalls++,
            onSave: (d) => saved = d,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byType(m.TextField).last;
    await tester.enterText(field, '定位文本');
    await tester.pump(const Duration(milliseconds: 600)); // 合帧窗口
    await tester.pump(const Duration(milliseconds: 1500)); // 防抖窗口

    // 手动 saveNow 模拟调度器调用。
    final state = tester.state<DocEditorState>(find.byType(DocEditor));
    final snapshot = state.saveNow();

    // ignore: avoid_print
    print(
      'DIRTY_CALLS=$dirtyCalls '
      'SAVED=${saved != null} '
      'SNAPSHOT_BODY=${snapshot.body.first.text}',
    );
    expect(dirtyCalls, greaterThan(0), reason: '输入应触发 onDirty');
    expect(snapshot.body.first.text, '定位文本', reason: '快照应含输入文本');
  });
}
