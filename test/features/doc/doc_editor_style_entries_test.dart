// 行内样式入口的「标灰 + 说明」处置（FDC-03，业主 2026-10-17 选这一档）。
//
// 现状（台账 §30/§31 逐条回读过）：`props['spans']` 有写侧、**没有任何读者**——
// 块编辑面每块是一个 `TextField`（`doc_editor_blocks.dart:494`），Markdown/HTML/PDF
// 导出也都不读 spans ⇒ 用户点粗体之后界面与导出都看不见，但改动会落盘。
// 处置是「禁用 + 把原因说在 tooltip 里」，数据与入口代码都保留；判据只有一份
// （`inlineStylesAreRendered`），两个入口都从 `styleEntryEnabled` / `styleEntryTooltip` 取。
//
// 本文件钉三件事：① 判据今天确实是 false（改成 true 时要回来更新登记，见理由）；
// ② 两个入口**都**接在这份判据上（不许哪一处自己写 `enabled: true`）；
// ③ 真机上四个样式按钮点不动、而同一工具条上的「复制块」照常能点（灰不能顺手把
//    别的能力一起关掉）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_inline_span.dart';
import 'package:drawing_notes_app/features/doc/presentation/doc_editor.dart';

const List<String> _entryFiles = <String>[
  'lib/features/doc/presentation/doc_editor_toolbar.dart',
  'lib/features/doc/presentation/doc_editor_selection.dart',
];

/// 四个样式动作（工具条与浮动选择条同名）。
const List<String> _styleHandlers = <String>[
  '_toggleBold',
  '_toggleItalic',
  '_toggleUnderline',
  '_insertLink',
];

void main() {
  test('判据今天为 false：接上渲染那天要连着改这条登记', () {
    expect(
      inlineStylesAreRendered,
      isFalse,
      reason: '改成 true 之前请先确认：块编辑面已不是单一样式的 TextField，'
          '且导出侧真的读 spans。两处入口会自动恢复可点。',
    );
  });

  test('两个入口都接在同一份判据上（不许各自写 enabled）', () {
    for (final path in _entryFiles) {
      final source = File(path).readAsStringSync();
      final handlers = _styleHandlers.where(source.contains).toList();
      expect(
        handlers.length,
        _styleHandlers.length,
        reason: '$path 里少了 '
            '${_styleHandlers.where((h) => !handlers.contains(h)).toList()} ——'
            '入口被挪走/改名了，这条门禁就看不见现场了，请同步本用例',
      );
      expect(
        source,
        contains('styleEntryEnabled'),
        reason: '$path 挂着四个样式动作却没引用共享判据 ⇒ 又在本地写死一份开关',
      );
      expect(
        source,
        contains('styleEntryTooltip'),
        reason: '$path 的样式按钮必须走共享文案（禁用时要把原因说清）',
      );
    }
    // 分母下限：扫描面本身不能是空的（R8~R14 那一族的口径）。
    expect(_entryFiles.length, 2);
    for (final path in _entryFiles) {
      expect(File(path).existsSync(), isTrue, reason: '扫描根错了 ⇒ 上面的判据会空集通过');
    }
  });

  testWidgets('浮动工具条：四个样式按钮点不动，同一条上的「复制块」照常能点', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 28);
    await tester.pumpWidget(
      MaterialApp(
        home: DocEditor(
          document: NoteBlockDoc(
            id: 'doc-style',
            title: 'ST',
            body: const [
              NoteBlock(
                id: 'b1',
                type: NoteBlockType.text,
                text: 'Hello world',
              ),
            ],
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 聚焦正文块并拖出一个非折叠选区 ⇒ 浮动工具条出现。
    final fields = find.byType(TextField);
    TextEditingController? body;
    for (var i = 0; i < tester.widgetList<TextField>(fields).length; i++) {
      final field = tester.widget<TextField>(fields.at(i));
      if (field.controller?.text == 'Hello world') {
        await tester.tap(fields.at(i));
        await tester.pump();
        body = field.controller;
      }
    }
    expect(body, isNotNull, reason: '没找到正文块输入框 ⇒ 本用例造不出选区，是空跑的');
    body!.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();

    // 浮动条与底部工具条**共用同一批图标**（`Icons.link` 两边都有）⇒ 必须先按
    // 「和复制块同一条 Row」把浮动工具条那棵子树圈出来，否则 findsOneWidget 直接红
    // （第一版就这么红的：Found 2 widgets with icon …）。
    final bar = find.ancestor(
      of: find.byIcon(Icons.content_copy_rounded),
      matching: find.byType(Row),
    );
    Finder inBar(IconData icon) => find.descendant(
      of: bar,
      matching: find.byIcon(icon),
    );
    expect(inBar(Icons.format_bold), findsOneWidget, reason: '圈错子树 ⇒ 下面的断言都是空的');

    InkWell inkAround(Finder target) =>
        tester
            .element(target)
            .findAncestorWidgetOfExactType<InkWell>()!;

    for (final icon in const [
      Icons.format_bold,
      Icons.format_italic,
      Icons.format_underline,
      Icons.link,
    ]) {
      expect(inBar(icon), findsOneWidget, reason: '$icon 入口还在（只是该被禁用）');
      expect(inkAround(inBar(icon)).onTap, isNull, reason: '$icon 必须点不动（样式无读者）');
    }
    // 同一条工具条上的其它能力不许被一起关掉。
    expect(inkAround(find.byIcon(Icons.content_copy_rounded)).onTap, isNotNull);

    // tooltip 要说清原因，不能只写功能名（`Tooltip.of` 这个 API 不存在——直接读那个 widget）。
    final tip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: inBar(Icons.format_bold),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tip.message, contains('暂不参与渲染'));
  });

  test('共享判据：可点性只由「有没有目标 × 样式是否渲染」决定', () {
    // 组合表：目标 × 渲染状态四种都要覆盖，缺一种就可能被写成恒 true。
    expect(styleEntryEnabled(hasTarget: true), inlineStylesAreRendered);
    expect(styleEntryEnabled(hasTarget: false), isFalse);
    // 兜底句（没有 l10n 时用的那份）必须与 arb 的 styleUnwiredTip 同义——
    // 中英两份键的对称由 l10n 门禁管，这里只钉「说清原因」这件事。
    expect('粗体（暂不参与渲染，导出也不会带上）', contains('暂不参与渲染'));
  });
}
