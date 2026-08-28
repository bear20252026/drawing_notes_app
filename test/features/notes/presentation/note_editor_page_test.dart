import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/note_editor_page.dart';

void main() {
  final now = DateTime(2026, 8, 28);

  NoteBlockDoc makeDoc({
    required String id,
    String title = '',
    List<NoteBlock> body = const [],
  }) =>
      NoteBlockDoc(
        id: id,
        title: title,
        body: body,
        createdAt: now,
        updatedAt: now,
      );

  group('NoteEditorPage 渲染', () {
    testWidgets('初始渲染包含一个可编辑的文本块', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 标题栏 + 空段落 = 2 个 TextField
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('AppBar 包含可编辑标题字段', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      final appBarFinder = find.byType(AppBar);
      expect(appBarFinder, findsOneWidget);
      expect(
        find.descendant(of: appBarFinder, matching: find.byType(TextField)),
        findsWidgets,
      );
    });
  });

  group('NoteEditorPage 文档绑定', () {
    testWidgets('接收 document 时标题显示在 AppBar', (tester) async {
      final doc = makeDoc(id: 'doc-1', title: 'My Document');

      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      final appBarFinder = find.byType(AppBar);
      expect(
        find.descendant(
          of: appBarFinder,
          matching: find.widgetWithText(TextField, 'My Document'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('接收多块文档后显示所有块', (tester) async {
      final doc = makeDoc(
        id: 'doc-multi',
        title: 'Multi',
        body: [
          NoteBlock.textBlock('t1', text: 'Block One'),
          NoteBlock.textBlock('t2', text: 'Block Two'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // 标题栏 + 2 个内容块 = 3 个 TextField
      expect(find.byType(TextField), findsNWidgets(3));
    });
  });

  group('NoteEditorPage onSave 回调', () {
    testWidgets('dispose 时若提供 onSave 则传出 NoteBlockDoc',
        (tester) async {
      NoteBlockDoc? savedDoc;
      final doc = makeDoc(
        id: 'doc-save',
        title: 'Save Me',
        body: [NoteBlock.textBlock('t1', text: 'Content')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(
            document: doc,
            onSave: (d) => savedDoc = d,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 触发 dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(savedDoc, isNotNull);
      expect(savedDoc!.id, 'doc-save');
      expect(savedDoc!.title, 'Save Me');
      expect(savedDoc!.body.length, 1);
    });

    testWidgets('无 onSave 时 dispose 不崩溃', (tester) async {
      final doc = makeDoc(id: 'doc-nosave', title: 'No Save');

      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // 触发 dispose —— 不应抛异常
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    });
  });
}
