// M11 契约测试：块编辑器「浮动选区工具条」（AFFiNE 一致性）。
//
// 行为：聚焦块内出现非折叠文本选区 → 浮动工具条出现（复制块图标唯一标识）；
// 选区折叠 → 工具条消失；「复制块」动作复制当前块并聚焦新块。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/doc_editor.dart';

void main() {
  final now = DateTime(2026, 8, 28);

  NoteBlockDoc makeDoc() => NoteBlockDoc(
    id: 'doc-st',
    title: 'ST',
    body: const [
      NoteBlock(id: 'b1', type: NoteBlockType.text, text: 'Hello world'),
    ],
    createdAt: now,
    updatedAt: now,
  );

  Future<TextEditingController> focusBodyField(WidgetTester tester) async {
    // 找到正文块对应的 TextField（controller.text 匹配），点击聚焦。
    final fields = find.byType(TextField);
    for (var i = 0; i < tester.widgetList<TextField>(fields).length; i++) {
      final field = tester.widget<TextField>(fields.at(i));
      if (field.controller?.text == 'Hello world') {
        await tester.tap(fields.at(i));
        await tester.pump();
        return field.controller!;
      }
    }
    fail('未找到正文块输入框');
  }

  testWidgets('非折叠选区唤出浮动工具条，折叠后消失', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DocEditor(document: makeDoc())));
    await tester.pumpAndSettle();

    // 初始无浮动工具条（复制块图标不存在）。
    expect(find.byIcon(Icons.content_copy_rounded), findsNothing);

    final controller = await focusBodyField(tester);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();

    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

    // 折叠选区 → 工具条消失。
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    expect(find.byIcon(Icons.content_copy_rounded), findsNothing);
  });

  testWidgets('复制块：在当前块后插入副本并聚焦', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DocEditor(document: makeDoc())));
    await tester.pumpAndSettle();

    final controller = await focusBodyField(tester);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.content_copy_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Hello world'), findsNWidgets(2));
  });
}
