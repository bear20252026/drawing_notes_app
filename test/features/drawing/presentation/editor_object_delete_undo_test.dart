// EUI-02（第四轮审计 2026-10-15）：Delete 键删掉的混排对象必须撤得回来。
//
// 审计原文：`editor_page_editing.dart` 的 `_deleteSelectedItem` 全文无
// `GlassDialog.confirm`、也无 `_commitSnapshot`——200ms 淡出后直接
// `EditorPageObjectMutation.remove`，紧接着 `_notifyChanged()` 排自动保存
// ⇒ 误删既不可撤销，又立刻被写进盘。
//
// 对照证据（同一条用户意图的两套实现）：浮动选择条的删除
// （`selection_bar.dart:165`）走 `controller.deleteSelectedDocumentObjects`，
// 那条会 push `DocumentObjectsSnapshotCommand`，删完能撤。
//
// 处置选择（写下来免得下一轮再判一遍）：**不加模态确认**。画布里删除是高频
// 动作，正确形状是「删得掉也撤得回」，而不是每次按 Delete 弹一次窗。
//
// 覆盖面说明：独立画布模式（`EditorPage(document:)`）可选对象只有文字块
// （`EditorOverlayItemPlan.forCanvas` 同源），所以四条集合的成对恢复由
// `test/features/drawing/application/mixed_objects_snapshot_command_test.dart`
// 单独钉；本文件钉的是**键盘链路真的接上了**。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpEditor(WidgetTester tester, DrawingDocument doc) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        home: EditorPage(document: doc),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  DrawingDocument threeTexts(String id) => DrawingDocument(
    id: id,
    title: '撤销删除',
    textItems: [
      PageTextItem(id: 'A', x: 100, y: 100, text: '对象A', zOrder: 0),
      PageTextItem(id: 'B', x: 200, y: 100, text: '对象B', zOrder: 1),
      PageTextItem(id: 'C', x: 300, y: 100, text: '对象C', zOrder: 2),
    ],
  );

  Future<void> deleteFirstText(WidgetTester tester, DrawingDocument doc) async {
    await pumpEditor(tester, doc);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    // 删除走「淡出后移除」：移除延迟 = AppleMotion.dropdown（200ms）。
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      doc.textItems.map((t) => t.id),
      isNot(contains('A')),
      reason: '前置条件：Delete 确实删掉了 A',
    );
  }

  testWidgets('Tab 选中 → Delete → Ctrl+Z：对象按原顺序回到文档', (tester) async {
    final doc = threeTexts('undo1');
    await deleteFirstText(tester, doc);
    expect(doc.textItems.map((t) => t.id), ['B', 'C'], reason: '删除只该动命中的那一个');

    await press(tester, LogicalKeyboardKey.keyZ);

    expect(doc.textItems.map((t) => t.id), [
      'A',
      'B',
      'C',
    ], reason: 'Ctrl+Z 必须把删掉的对象按原顺序放回（EUI-02）');
  });

  testWidgets('重做把撤销回来的对象再删一次，不牵连其余', (tester) async {
    final doc = threeTexts('undo2');
    await deleteFirstText(tester, doc);
    await press(tester, LogicalKeyboardKey.keyZ);
    expect(doc.textItems.map((t) => t.id), ['A', 'B', 'C']);

    await press(tester, LogicalKeyboardKey.keyY);

    expect(doc.textItems.map((t) => t.id), [
      'B',
      'C',
    ], reason: 'redo 是对称的那半：Ctrl+Y 该把 A 再删掉');
  });

  testWidgets('删除→撤销→再删除：同一命令不因重入丢历史条目', (tester) async {
    final doc = threeTexts('undo3');
    await deleteFirstText(tester, doc);
    await press(tester, LogicalKeyboardKey.keyZ);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump(const Duration(milliseconds: 300));
    expect(doc.textItems.map((t) => t.id), ['B', 'C']);

    await press(tester, LogicalKeyboardKey.keyZ);

    expect(doc.textItems.map((t) => t.id), [
      'A',
      'B',
      'C',
    ], reason: '第二次删除同样要撤得回来（撤销栈里两条都在）');
  });
}
