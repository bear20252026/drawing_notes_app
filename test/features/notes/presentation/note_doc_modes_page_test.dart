// NoteDocModesPage 双模宿主 widget 测试。
// 覆盖：默认页面模式、切换到无限画布（拆分帧）、切回页面（合并+onSave）、
// 页面模式返回收口。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/note_doc_modes_page.dart';

NoteBlockDoc buildDoc() {
  return NoteBlockDoc(
    id: 'modes-doc',
    title: '双模文档',
    body: [
      NoteBlock.headingBlock('h1', level: 1, text: '一级标题'),
      NoteBlock.textBlock('p1', text: '正文段落一'),
      NoteBlock.textBlock('p2', text: '正文段落二'),
    ],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  testWidgets('默认进入页面模式，显示模式切换条', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: NoteDocModesPage(document: buildDoc())),
    );

    expect(find.text('页面'), findsOneWidget);
    expect(find.text('无限画布'), findsOneWidget);
    // 页面模式下应显示标题（注意：NoteEditorPage 内部也有 title TextField）
    expect(find.text('双模文档'), findsWidgets);
  });

  testWidgets('切换到无限画布后渲染 note 帧内容，切回页面合并并触发 onSave', (tester) async {
    NoteBlockDoc? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: NoteDocModesPage(
          document: buildDoc(),
          onSave: (d) => saved = d,
        ),
      ),
    );

    // 切到无限画布
    await tester.tap(find.text('无限画布'));
    await tester.pumpAndSettle();

    // 应按 heading 拆出 2 个 note 帧：帧1=[一级标题, 正文段落一]、帧2=[正文段落二]
    // 帧内容由 NoteFramePreview 渲染为文本
    expect(find.text('一级标题'), findsWidgets);
    expect(find.text('正文段落一'), findsWidgets);
    expect(find.text('正文段落二'), findsWidgets);

    // 切回页面模式 → 合并并 onSave
    await tester.tap(find.text('页面'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.body.length, 3); // 与原始一致
    expect(
      saved!.body.map((b) => b.text).toList(),
      ['一级标题', '正文段落一', '正文段落二'],
    );
  });

  testWidgets('页面模式返回时通过 onSave 收口最新文档', (tester) async {
    NoteBlockDoc? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<NoteBlockDoc>(
                      builder: (_) => NoteDocModesPage(
                        document: buildDoc(),
                        onSave: (d) => saved = d,
                      ),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 触发返回
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.body.length, 3);
    expect(saved!.id, 'modes-doc');
  });
}
