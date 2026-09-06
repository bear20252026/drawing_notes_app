// U3 性能批次测试（2026-09-02）：
// - P0-7：`_hasUnpersistedPageContent` 判定的域语义（跳过无谓重加密）。
// - P1-9：_syncText 静默模型同步 + 装饰刷新合帧的行为等价性。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/doc/domain/clone_ref.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/doc_editor.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page.dart';

/// P0-7 判定的镜像实现（notebook_view_page 私有 getter 的语义契约）：
/// 非克隆页且内容相对最近版本快照有变化 → 需要落盘。
bool hasUnpersistedPageContent(List<NotebookPage> pages) =>
    pages.any((p) => p.cloneOf == null && p.hasChangedSinceLatestVersion);

NotebookPage emptyPage({String id = 'p', bool clone = false}) => NotebookPage(
  id: id,
  title: '页',
  document: DrawingDocument(id: 'doc-$id', title: '画布'),
  cloneOf: clone ? const CloneRef(notebookId: 'nb-src', pageId: 'src') : null,
);

NotebookPage pageWithText({String id = 'p', bool clone = false}) {
  final page = emptyPage(id: id, clone: clone);
  page.textItems.add(PageTextItem(id: 'text-$id', x: 0, y: 0, text: '手写批注'));
  return page;
}

/// U3 测试基准时间（NoteBlockDoc 构造必填）。
final _now = DateTime(2026, 9, 2);

void main() {
  group('U3 P0-7 未落盘内容判定', () {
    test('空笔记本（无页面）→ 无需保存', () {
      expect(hasUnpersistedPageContent(const []), isFalse);
    });

    test('页面均为空内容（刚打开未修改）→ 无需保存', () {
      expect(
        hasUnpersistedPageContent([emptyPage(id: 'a'), emptyPage(id: 'b')]),
        isFalse,
      );
    });

    test('任一普通页内容有变化 → 需要保存', () {
      expect(
        hasUnpersistedPageContent([emptyPage(id: 'a'), pageWithText(id: 'b')]),
        isTrue,
      );
    });

    test('克隆页内容变化不计入（内容在源页，本页保存不写其快照）', () {
      expect(
        hasUnpersistedPageContent([pageWithText(id: 'c', clone: true)]),
        isFalse,
      );
    });

    test('克隆页 + 普通页混合：普通页变化仍触发保存', () {
      expect(
        hasUnpersistedPageContent([
          pageWithText(id: 'clone', clone: true),
          pageWithText(id: 'normal'),
        ]),
        isTrue,
      );
    });
  });

  group('U3 P1-9 编辑器静默同步 + 装饰刷新', () {
    testWidgets('击键后模型即时更新、脏标记翻转、onDirty 边沿触发一次', (tester) async {
      final doc = NoteBlockDoc(
        id: 'u3-doc',
        title: '标题',
        body: [NoteBlock.textBlock('t1', text: '原文')],
        createdAt: _now,
        updatedAt: _now,
      );
      var dirtyCount = 0;
      NoteBlockDoc? saved;

      await tester.pumpWidget(
        MaterialApp(
          home: DocEditor(
            document: doc,
            onDirty: () => dirtyCount++,
            onSave: (d) => saved = d,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 标题 + 1 个内容块 = 2 个 TextField；向内容块输入。
      await tester.enterText(find.byType(TextField).last, '原文更多内容');
      await tester.pump();

      // P1-9：静默模型同步——currentDoc 即时反映最新文本（不等 200ms 合帧）。
      final state = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(state.currentDoc.body.first.text, '原文更多内容');

      // dirty 翻转触发一次整树重建 → AppBar 出现「未保存」角标。
      expect(find.text('未保存'), findsOneWidget);
      // onDirty 边沿触发一次（自动保存启动信号不受影响）。
      expect(dirtyCount, 1);

      // 装饰刷新合帧（200ms）后无异常，文本保持一致。
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.currentDoc.body.first.text, '原文更多内容');
      expect(dirtyCount, 1);

      // dispose 走 onSave（原有契约不回归）。
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.body.first.text, '原文更多内容');
    });

    testWidgets('已保存后再次输入：脏角标重新出现（false→true 翻转路径）', (tester) async {
      final doc = NoteBlockDoc(
        id: 'u3-doc2',
        title: 'T',
        body: [NoteBlock.textBlock('t1', text: 'A')],
        createdAt: _now,
        updatedAt: _now,
      );

      await tester.pumpWidget(
        MaterialApp(
          // 提供 onSave → AppBar 出现保存按钮（_manualSave 路径）。
          home: DocEditor(document: doc, onSave: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'AB');
      await tester.pump();
      expect(find.text('未保存'), findsOneWidget);

      // 点保存按钮（_manualSave：setState 清脏 + 记录签名）→ 角标消失
      // （true→false 翻转路径）。
      await tester.tap(find.byIcon(Icons.save));
      await tester.pump();
      expect(find.text('未保存'), findsNothing);

      // 再次输入 → 翻转回脏。
      await tester.enterText(find.byType(TextField).last, 'ABC');
      await tester.pump();
      expect(find.text('未保存'), findsOneWidget);
    });
  });
}
