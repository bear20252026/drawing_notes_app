// FDC-01（第四轮审计 2026-10-15）：一个块有**两个真相**——`block.text` 与
// `props['spans']`，而只有前者会被打字更新。
//
// 实测链路：
//  · `_syncText`（`doc_editor_editing.dart:23`）只写 `text`，`props['spans']`
//    留在上一次点样式时的旧值；
//  · `_spansFromBlock`（同文件 :222-239）**无条件优先**读 `props['spans']`；
//  · `_updateSpans`（:257-265）再 `updateText(spans.plainText)` 写回。
// ⇒ 「先点粗体、再打一段字、再点斜体」这三次点击之后，第二次打的那一段
//    被陈旧 span 列表的 plainText 整体覆盖——**用户刚输入的内容静默消失**，
//    没有报错，撤销栈里也只剩「样式命令」。
// 同类：`_splitBlock`（:53）用 `copyWith` 把**整段** spans 也带进后半块，
// 于是新块的 span 列表描述的是前一块的文字。
//
// 修法方向：`text` 是唯一真相；`props['spans']` 只有在与其 plainText 对得上时
// 才是可信的样式载体，对不上就当「无 spans」按纯文本处理（样式退化为一次性，
// 内容永远赢）。
//
// 反向锁同样钉住：文字一致时样式必须仍然生效——把 spans 一律忽略不是修法。
//
// R46 之后样式入口默认是**禁用**的（`inlineStylesAreRendered = false`，标灰 + 说明），
// 这三条都要走那条入口才能造出 spans 形状 ⇒ 本文件在 setUp 里临时把判据开成 true、
// tearDown 还原。这不是绕过 R46：生产默认仍然点不动（由
// `doc_editor_style_entries_test.dart` 钉），这里保住的是**接上渲染那天**
// 「正文永远赢、样式不能当第二个真相」这条裁决不因入口重开而失守。
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_inline_span.dart';
import 'package:drawing_notes_app/features/doc/presentation/doc_editor.dart';

void main() {
  setUp(() => inlineStylesAreRendered = true);
  tearDown(() => inlineStylesAreRendered = false);

  NoteBlockDoc docWith(List<NoteBlock> body, {String id = 'fdc01'}) => NoteBlockDoc(
    id: id,
    title: '',
    body: body,
    createdAt: DateTime(2026, 10, 1),
    updatedAt: DateTime(2026, 10, 1),
  );

  Future<DocEditorState> mount(
    WidgetTester tester,
    NoteBlockDoc doc, {
    bool showChrome = false,
  }) async {
    await tester.pumpWidget(
      m.MaterialApp(
        home: m.Scaffold(
          body: DocEditor(document: doc, showChrome: showChrome, onDirty: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return tester.state<DocEditorState>(find.byType(DocEditor));
  }

  /// 聚焦最后一个块并返回它的 TextEditingController（打字走的就是这条真链路）。
  Future<m.TextEditingController> focusLastBlock(WidgetTester tester) async {
    await tester.tap(find.byType(m.TextField).last);
    await tester.pump(const Duration(milliseconds: 100));
    final editable = tester.state<m.EditableTextState>(
      find.byType(m.EditableText).last,
    );
    return editable.widget.controller;
  }

  Future<void> select(
    WidgetTester tester,
    m.TextEditingController controller,
    int start,
    int end,
  ) async {
    controller.selection = m.TextSelection(baseOffset: start, extentOffset: end);
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 底部工具条与「选中后浮出的胶囊工具条」都有同一枚按钮（都调 `_toggleBold`
  /// 等同一套逻辑），`find.byTooltip('粗体')` 因此恒歧义；overlay 在树尾，
  /// `.last` 取到的就是浮出的那一枚。
  Future<void> tapStyle(WidgetTester tester, m.IconData icon) async {
    await tester.tap(find.byIcon(icon).last);
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('FDC-01 打字与 spans 的两个真相', () {
    testWidgets('点粗体 → 再打一段字 → 再点斜体 ⇒ 新打的字必须还在（内容赢）', (tester) async {
      final state = await mount(
        tester,
        docWith([NoteBlock.textBlock('b1', text: '第一段')]),
      );

      final controller = await focusLastBlock(tester);
      await select(tester, controller, 0, 3);
      await tapStyle(tester, m.Icons.format_bold);

      // 样式那一步本身要成立（也确认 spans 真的落进了 props）。
      final afterBold = state.currentDoc.body.single;
      expect(afterBold.text, '第一段');
      expect(afterBold.props['spans'], isA<List<Object?>>(), reason: '点过粗体就该有 span 载体');

      // 打字：走真实的 onChanged → `_syncText` 只写 text。
      await tester.enterText(find.byType(m.TextField).last, '第一段后来打的字');
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        state.currentDoc.body.single.text,
        '第一段后来打的字',
        reason: '前置条件：打字已进模型',
      );

      // 第二次样式操作：读的是陈旧 spans，写回时会把整段新字覆盖掉。
      await select(tester, controller, 3, 8);
      await tapStyle(tester, m.Icons.format_italic);

      expect(
        state.currentDoc.body.single.text,
        '第一段后来打的字',
        reason: '样式切换不得改写正文——用户刚打的字被静默抹掉是数据丢失',
      );
    });

    testWidgets('反向锁：文字与 spans 一致时，样式仍要逐段生效且不被后一次抹掉', (tester) async {
      final state = await mount(
        tester,
        docWith([NoteBlock.textBlock('b1', text: '甲乙丙丁')]),
      );

      final controller = await focusLastBlock(tester);
      await select(tester, controller, 0, 2);
      await tapStyle(tester, m.Icons.format_bold);
      await select(tester, controller, 2, 4);
      await tapStyle(tester, m.Icons.format_italic);

      final spans = (state.currentDoc.body.single.props['spans'] as List).cast<
        Map<String, dynamic>
      >();
      final textByStyle = [
        for (final s in spans) '${s['text']}:${s['bold'] == true ? 'B' : ''}${s['italic'] == true ? 'I' : ''}',
      ];
      expect(
        textByStyle,
        ['甲乙:B', '丙丁:I'],
        reason: '两次样式都要留下——修法不能退化成「干脆不记样式」',
      );
      expect(
        spans.map((s) => s['text']).join(),
        '甲乙丙丁',
        reason: 'spans 的拼接必须与正文逐字相等，否则它就是第二个真相',
      );
    });

    testWidgets('块自带「spans 描述的不是自己的文字」（拆分留下的形状）⇒ 正文赢', (tester) async {
      // `_splitBlock` 用 copyWith 把整段 spans 带进后半块，所以盘上会出现
      // 「text=后，而 spans 说 前后」这种块。这里直接构造该形状，不模拟回车。
      final styled = <Map<String, dynamic>>[
        {'text': '前后', 'bold': true},
      ];
      final state = await mount(
        tester,
        docWith([
          NoteBlock(
            id: 'b1',
            type: NoteBlockType.text,
            text: '前后',
            props: {'spans': styled},
          ),
          NoteBlock(
            id: 'b2',
            type: NoteBlockType.text,
            text: '后',
            props: {'spans': styled},
          ),
        ]),
      );

      final lastController = await focusLastBlock(tester);
      expect(state.currentDoc.body.last.id, 'b2', reason: '前置条件：聚焦的是后半块');
      await tester.enterText(
        find.byType(m.TextField).last,
        '${lastController.text}新字',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await select(tester, lastController, 0, lastController.text.length);
      await tapStyle(tester, m.Icons.format_italic);

      expect(
        state.currentDoc.body.last.text,
        '后新字',
        reason: '后半块的 spans 描述的是前一块的文字，不能被当作它的正文',
      );
      expect(
        state.currentDoc.body.first.text,
        '前后',
        reason: '动后半块不该回头改前半块',
      );
    });
  });
}
