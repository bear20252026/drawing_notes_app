// M12.7 回归：反向链接（双链索引 + 编辑器追加引用）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/application/doc_link_index.dart';
import 'package:drawing_notes_app/features/doc/doc_editor.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';

NoteBlockDoc _doc(String id, String title, List<String> texts) {
  return NoteBlockDoc(
    id: id,
    title: title,
    body: [
      for (final t in texts)
        NoteBlock.textBlock('b_${t.hashCode}_$id', text: t),
    ],
    createdAt: DateTime(2026, 8, 31),
    updatedAt: DateTime(2026, 8, 31, 12),
  );
}

void main() {
  group('双链索引（纯逻辑）', () {
    test('extractOutLinks 提取 [[标题]] 并去重', () {
      final doc = _doc('a', 'A', ['见 [[设计稿]] 和 [[会议记录]]', '再提一次 [[设计稿]]']);
      expect(extractOutLinks(doc), ['设计稿', '会议记录']);
    });

    test('backlinksOf：标题匹配 + 不含自身 + 更新时间倒序', () {
      final target = _doc('t', '设计稿', ['正文']);
      final newer = _doc('n', '新笔记', ['引用了 [[设计稿]]']);
      final older = _doc('o', '旧笔记', ['也引用 [[设计稿]]']);
      // 让 older 更新时间更晚 → 应排在前面
      final olderLater = NoteBlockDoc(
        id: older.id,
        title: older.title,
        body: older.body,
        createdAt: older.createdAt,
        updatedAt: DateTime(2026, 8, 31, 18),
      );
      final unrelated = _doc('u', '无关', ['没有链接']);

      final result = backlinksOf(target, [
        target,
        newer,
        olderLater,
        unrelated,
      ]);
      expect(result.map((d) => d.id), ['o', 'n']); // 倒序 + 无自身 + 无无关
    });

    test('outgoingLinksOf：按标题解析出链目标', () {
      final target = _doc('t', '设计稿', ['正文']);
      final source = _doc('s', '汇总', ['链接 [[设计稿]] 与 [[不存在]]']);
      final out = outgoingLinksOf(source, [source, target]);
      expect(out, hasLength(1));
      expect(out.single.id, 't');
    });

    test('formatDocLink 语法', () {
      expect(formatDocLink(_doc('x', '我的笔记', [])), '[[我的笔记]]');
    });
  });

  testWidgets('appendPageLink：追加 [[标题]] 块并进入保存链', (tester) async {
    final doc = _doc('a', 'A', ['第一段']);
    final target = _doc('b', '设计稿', ['正文']);
    var dirty = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocEditor(
            document: doc,
            showChrome: false,
            onDirty: () => dirty = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<DocEditorState>(find.byType(DocEditor));
    expect(state.currentDoc.body, hasLength(1));

    state.appendPageLink(target);
    await tester.pumpAndSettle();

    expect(state.currentDoc.body, hasLength(2));
    expect(state.currentDoc.body.last.text, '[[设计稿]]');
    expect(dirty, isTrue, reason: '追加引用应标记脏状态（驱动宿主自动保存）');
  });
}
