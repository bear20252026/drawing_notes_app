// V-01（审计 2026-09-27）键盘选中画布对象专项测试。
//
// 覆盖：Tab/Shift+Tab 轮选（含边界循环）、z 序选择顺序、选中后既有
// 键盘链路生效（Alt+方向键微调作探针、Delete 删除）、Esc 清除选中、
// 空画布放行焦点遍历。
//
// 探针设计：_selectedItemId 为页私有状态，测试经行为断言——Alt+方向键
// 微调只作用于当前选中对象，比对被移动物件坐标判定「谁被选中」。
// 画布模式（document 直入）下可选对象 = 文字块（与 overlay 渲染同源
// EditorOverlayItemPlan.forCanvas），zOrder 决定轮选顺序。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DrawingDocument buildDocument() {
    PageTextItem item(String id, int z, double x) =>
        PageTextItem(id: id, x: x, y: 100, text: '对象$id', zOrder: z);
    return DrawingDocument(
      id: 'kb1',
      title: '键盘选中',
      textItems: [item('A', 0, 100), item('B', 1, 200), item('C', 2, 300)],
    );
  }

  Future<void> pumpEditor(WidgetTester tester, DrawingDocument doc) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditorPage(document: doc)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  PageTextItem itemOf(DrawingDocument doc, String id) =>
      doc.textItems.firstWhere((t) => t.id == id);

  testWidgets('Tab 轮选按 z 序前进，Alt+方向键只作用于当前选中对象', (tester) async {
    final doc = buildDocument();
    await pumpEditor(tester, doc);

    // 无选中：Alt+右不动任何对象。
    final x0 = itemOf(doc, 'A').x;
    await tester.sendKeyEvent(LogicalKeyboardKey.alt, platform: 'windows');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(itemOf(doc, 'A').x, x0);

    // Tab → 选中 z 序第一个 A：Alt+右只微调 A（1px）。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(itemOf(doc, 'A').x, x0 + 1, reason: 'Tab 应选中 z 序第一个 A');
    expect(itemOf(doc, 'B').x, 200);
    expect(itemOf(doc, 'C').x, 300);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);

    // Tab → B。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(itemOf(doc, 'B').x, 201, reason: '第二次 Tab 应前进到 B');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
  });

  testWidgets('Shift+Tab 反向回退；Tab 到末尾后循环回首', (tester) async {
    final doc = buildDocument();
    await pumpEditor(tester, doc);

    // Tab → A → Tab → B → Shift+Tab 回 A。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(itemOf(doc, 'A').x, 101, reason: 'Shift+Tab 应回退到 A');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);

    // 从 A 继续 Tab：B → C（末尾）→ 循环回首 A。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(itemOf(doc, 'A').x, 102, reason: 'C 之后循环回首个对象 A');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
  });

  testWidgets('Delete 删除键盘选中的对象；Esc 清除选中', (tester) async {
    final doc = buildDocument();
    await pumpEditor(tester, doc);

    // Tab 选中 A → Delete：A 从文档移除（不可逆删除路径自此键盘可达）。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    // 删除走「淡出后移除」：移除延迟 = AppleMotion.dropdown（200ms），
    // 须 pump 过该时长才落到文档集合。
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      doc.textItems.any((t) => t.id == 'A'),
      isFalse,
      reason: 'Delete 应删除键盘选中的 A',
    );
    expect(doc.textItems.length, 2);

    // Tab 选中 B（剩余首个）→ Esc 清除 → Alt+右不动任何对象。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    final bx = itemOf(doc, 'B').x;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(itemOf(doc, 'B').x, bx, reason: 'Esc 后无选中，微调不生效');
    expect(itemOf(doc, 'C').x, 300);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
  });

  testWidgets('空画布：Tab 无对象可选，按键放行不崩溃', (tester) async {
    final doc = DrawingDocument(id: 'kb0', title: '空');
    await pumpEditor(tester, doc);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(doc.textItems, isEmpty);
  });
}
