import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:editor_core/editor_core.dart';
import 'package:drawing_notes_app/features/editor_v2/presentation/note_editor_widget.dart';

/// AFFiNE Page 借鉴——NoteEditorWidget 测试（Widget——不崩）。
void main() {
  NoteDocument makeDoc() => const NoteDocument(
        id: 'note1',
        title: '我的笔记',
        paragraphs: [
          NoteParagraph(id: 'p1', content: '第一段文字'),
          NoteParagraph(id: 'p2', content: '第二段文字', type: NoteParagraphType.heading),
        ],
      );

  testWidgets('NoteEditorWidget 渲染（Word 文档式——段落显示——不崩）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteEditorWidget(document: makeDoc(), onChanged: (_) {}),
      ),
    ));
    expect(find.text('我的笔记'), findsOneWidget); // 标题。
    expect(find.text('第一段文字'), findsOneWidget);
    expect(find.text('第二段文字'), findsOneWidget);
    expect(tester.takeException(), isNull); // 不崩。
  });

  testWidgets('NoteEditorWidget 新增段落按钮（Word 式——不崩）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteEditorWidget(document: makeDoc(), onChanged: (_) {}),
      ),
    ));
    expect(find.text('新增段落'), findsOneWidget);
    await tester.tap(find.text('新增段落'));
    await tester.pump();
    expect(tester.takeException(), isNull); // 点击后不崩。
  });

  testWidgets('NoteEditorWidget 空段落（初始——提示打字——不崩）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteEditorWidget(
          document: const NoteDocument(
            id: 'note2',
            title: '新笔记',
            paragraphs: [NoteParagraph(id: 'p1', content: '')],
          ),
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('开始打字……（Word 文档式）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
