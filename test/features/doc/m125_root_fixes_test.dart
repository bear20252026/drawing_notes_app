// M12.5 回归：三项根修的契约测试。
// 1) Markdown 导出转换（AFFiNE Export 对齐）
// 2) buildAllDocs 跨 kind 去重（同一逻辑笔记的双标签分叉）
// 3) IME 组合期按键放行（中文输入根修）

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/doc/application/doc_export_io.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc_markdown.dart';
import 'package:drawing_notes_app/features/doc/doc_editor.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

NoteBlockDoc _doc({String title = '测试文档', List<NoteBlock>? body}) {
  return NoteBlockDoc(
    id: 'doc1',
    title: title,
    body: body ?? [NoteBlock.textBlock('b1', text: '')],
    createdAt: DateTime(2026, 8, 31, 10),
    updatedAt: DateTime(2026, 8, 31, 10),
  );
}

void main() {
  group('Markdown 导出转换', () {
    test('标题/待办/列表/引用/代码/分割线', () {
      final doc = _doc(
        body: [
          NoteBlock.headingBlock('h1', level: 2, text: '第二章'),
          NoteBlock.todoBlock('t1', text: '买牛奶', checked: true),
          NoteBlock.todoBlock('t2', text: '写周报'),
          NoteBlock.bulletBlock('u1', text: '圆点项'),
          NoteBlock.orderedBlock('o1', text: '第一步'),
          NoteBlock.quoteBlock('q1', text: '引用内容'),
          NoteBlock.codeBlock('c1', text: 'print(1)'),
          NoteBlock.dividerBlock('d1'),
          NoteBlock.textBlock('p1', text: '正文段落'),
        ],
      );
      final md = noteBlockDocToMarkdown(doc);
      expect(md, contains('# 测试文档'));
      expect(md, contains('## 第二章'));
      expect(md, contains('- [x] 买牛奶'));
      expect(md, contains('- [ ] 写周报'));
      expect(md, contains('- 圆点项'));
      expect(md, contains('1. 第一步'));
      expect(md, contains('> 引用内容'));
      expect(md, contains('```\nprint(1)\n```'));
      expect(md, contains('---'));
      expect(md, contains('正文段落'));
    });

    test('文件名安全化', () {
      expect(sanitizeFileName('a/b:c*d?"<>|'), isNot(contains('/')));
      expect(sanitizeFileName('   '), '未命名');
    });
  });

  group('buildAllDocs 跨 kind 去重（双标签分叉根修）', () {
    final now = DateTime(2026, 8, 31, 10);
    test('同 id 的 note+blockdoc 只保留 blockdoc 行', () {
      final page = NotebookPage(
        id: 'pg1',
        title: '同一笔记',
        document: DrawingDocument(id: 'doc_pg1', title: '同一笔记'),
      );
      final nb = Notebook(id: 'nb1', title: '笔记本', pages: [page]);
      final blockMeta = BlockDocMeta(
        id: 'pg1',
        title: '同一笔记（已编辑）',
        folder: '',
        createdAt: now,
        updatedAt: now,
      );
      final result = buildAllDocs(
        docs: const [],
        notebooks: [nb],
        blockDocs: [blockMeta],
        now: now,
      );
      // 修复前：两行（kind=note + kind=blockdoc）；修复后：单行 blockdoc。
      expect(result.docs, hasLength(1));
      expect(result.docs.single.kind, AllDocKind.blockdoc);
      expect(result.docs.single.id, 'pg1');
    });

    test('不同 id 的 note 与 blockdoc 各自保留', () {
      final page = NotebookPage(
        id: 'pg2',
        title: '普通页面',
        document: DrawingDocument(id: 'doc_pg2', title: '普通页面'),
      );
      final nb = Notebook(id: 'nb1', title: '笔记本', pages: [page]);
      final blockMeta = BlockDocMeta(
        id: 'bd1',
        title: '打字笔记',
        folder: '',
        createdAt: now,
        updatedAt: now,
      );
      final result = buildAllDocs(
        docs: const [],
        notebooks: [nb],
        blockDocs: [blockMeta],
        now: now,
      );
      expect(result.docs, hasLength(2));
      expect(
        result.docs.map((d) => d.kind),
        containsAll([AllDocKind.note, AllDocKind.blockdoc]),
      );
    });
  });

  group('IME 组合期按键放行', () {
    testWidgets('组合中按 Enter 不分块；组合结束后正常分块', (tester) async {
      final doc = _doc(body: [NoteBlock.textBlock('b1', text: '')]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DocEditor(document: doc, showChrome: false)),
        ),
      );
      await tester.pumpAndSettle();

      // 聚焦正文块（.last = 正文块；.first 是标题框）→ 打开输入连接。
      final blockFieldFinder = find.byType(TextField).last;
      await tester.tap(blockFieldFinder);
      await tester.pumpAndSettle();

      // 经真实输入管线注入"拼音组合中"的编辑值（composing 非空）。
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'nihao',
          composing: TextRange(start: 0, end: 5),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(state.currentDoc.body.first.text, 'nihao');

      // 组合期 Enter：应被交还输入法（确认候选词），不得触发分块。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        state.currentDoc.body.length,
        1,
        reason: '组合期 Enter 不得分块（应交还输入法确认候选）',
      );

      // 组合结束（composing 清空）后 Enter：正常分块。
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'nihao', composing: TextRange.empty),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        state.currentDoc.body.length,
        greaterThanOrEqualTo(2),
        reason: '非组合期 Enter 应正常分块',
      );
    });
  });
}
