// 编辑器保存态订阅的**成对性**回归锁（2026-10-12，批次 DN wave 2 被云端打红的那类）。
//
// 症状：页面 dispose 里的兜底 flush 同步派发 `savingState`，命中一个「本该早被摘掉」
// 的监听 ⇒ 元素已 defunct ⇒ `framework.dart:5353: _lifecycleState != defunct`，
// 云端全量一次红 20 条（editor_keyboard_select / editor_page_390dp_overflow /
// paged_canvas_open_rasterize / reading_inversion / command_palette …）。
//
// 成因**不是**缺 `mounted` 判断（回调里本来就有）。真因是那两个回调住在 extension
// `_EditorPagePersistence` 中，而 extension 成员的代次每次求值都新分配一个闭包，
// 于是 `removeListener(_onSavingStateChanged)` 摘掉的是**另一个对象**——订阅永不解除，
// 老 State（连同画布控制器）被 notifier 强引用住。修法是把监听收口成 State 字段。
//
// 可证伪性由突变自证保证：把两处 removeListener 改回方法代次，本用例当场变红。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('退出编辑器时，保存态派发不得打到已卸载的页面', (tester) async {
    final doc = DrawingDocument(
      id: 'listener_pairing',
      title: '订阅成对性',
      textItems: [
        PageTextItem(id: 'A', x: 100, y: 100, text: '对象A', zOrder: 0),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: EditorPage(document: doc))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 造一次**真实改动**（Tab 选中 + Alt+右微调）：干净退出会在 `_disposed` 处早退、
    // 那条路上根本没有派发，用例就成了恒真断言——必须有这一步把兜底 flush 逼出来。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt, platform: 'windows');
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.arrowRight,
      platform: 'windows',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pump();
    expect(doc.textItems.single.x, isNot(100), reason: '改动确实发生了');

    // 卸载页面。若监听未解除，dispose 内的 `savingState.value = true` 会同步派发并
    // 在 defunct 元素上 setState——flutter_test 在用例结束时把未处理异常判红。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });
}
