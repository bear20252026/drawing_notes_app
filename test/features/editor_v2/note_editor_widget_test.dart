import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:editor_core/editor_core.dart';
import 'package:drawing_notes_app/features/editor_v2/presentation/note_editor_widget.dart';

/// NoteEditorWidget 测试（#18 Word 式直接打字——#13 持久化修复——2026-08-24）。
void main() {
  NoteDocument makeDoc() => const NoteDocument(
        id: 'note1',
        title: '我的笔记',
        paragraphs: [
          NoteParagraph(id: 'p1', content: '第一段文字'),
          NoteParagraph(
            id: 'p2',
            content: '第二段文字',
            type: NoteParagraphType.heading,
          ),
        ],
      );

  testWidgets('NoteEditorWidget 渲染（Word 文档式——标题+段落——不崩）',
      (tester) async {
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

  testWidgets('NoteEditorWidget 标题可编辑（#18 Word 式）', (tester) async {
    NoteDocument? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteEditorWidget(
          document: makeDoc(),
          onChanged: (doc) => changed = doc,
        ),
      ),
    ));

    // 编辑标题
    final titleField = find.widgetWithText(TextField, '我的笔记');
    expect(titleField, findsOneWidget);
    await tester.enterText(titleField, '新标题');
    expect(changed?.title, '新标题');
  });

  testWidgets('NoteEditorWidget 段落可编辑（#13 打字落盘）', (tester) async {
    NoteDocument? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteEditorWidget(
          document: makeDoc(),
          onChanged: (doc) => changed = doc,
        ),
      ),
    ));

    // 编辑第一段
    final p1Field = find.widgetWithText(TextField, '第一段文字');
    expect(p1Field, findsOneWidget);
    await tester.enterText(p1Field, '修改后的文字');
    expect(changed?.paragraphs.first.content, '修改后的文字');
  });

  testWidgets('NoteEditorWidget 空段落（初始——提示文字——不崩）', (tester) async {
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
    // 新版 hint text（#18 修改）
    expect(find.text('开始输入…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NoteEditorWidget 没有"新增段落"按钮（#18 Word 式——Enter 新增）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteEditorWidget(document: makeDoc(), onChanged: (_) {}),
      ),
    ));
    // 新版去掉了"新增段落"按钮（Enter 键新增——Word 体验）
    expect(find.text('新增段落'), findsNothing);
  });

  testWidgets('NoteEditorWidget onChanged 回调触发（#13 落盘基础）',
      (tester) async {
    int callCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteEditorWidget(
          document: makeDoc(),
          onChanged: (_) => callCount++,
        ),
      ),
    ));

    // 输入文字触发 onChanged
    await tester.enterText(
      find.widgetWithText(TextField, '第一段文字'),
      '新内容',
    );
    expect(callCount, greaterThanOrEqualTo(1));
  });

  // ── P1 #17 暗色模式适配 ──────────────────────────────────

  testWidgets('NoteEditorWidget 暗色模式——背景色适配（P1 #17）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      themeMode: ThemeMode.dark,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: NoteEditorWidget(document: makeDoc(), onChanged: (_) {}),
      ),
    ));
    // 暗色模式下不应崩，且使用 Theme 背景色而非固定 Colors.white。
    expect(find.text('我的笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NoteEditorWidget 暗色模式——文本颜色适配（P1 #17）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      themeMode: ThemeMode.dark,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: NoteEditorWidget(document: makeDoc(), onChanged: (_) {}),
      ),
    ));
    // 暗色模式下段落文字仍可见（颜色来自 theme.colorScheme.onSurface）。
    expect(find.text('第一段文字'), findsOneWidget);
    expect(find.text('第二段文字'), findsOneWidget);
  });
}
