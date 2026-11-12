// f8 键盘等价：文字宽度手柄——三处手柄里唯一没有测试的一路。
//
// `resize_handles_test.dart` 钉的是 8 向缩放与线性端点；文字宽度手柄的宿主
// 逻辑在 `editor_page_text_overlays.dart`，且比另外两个多一条「会话基准」
// 链路（聚焦取锚点 → 相对累加 → 失焦清空）。本文件钉的就是这条链路。
//
// 为什么这条链路值得单独钉：宽度是**相对锚点**累加的（`anchor.width + Δ`），
// 而 `onPanUpdate` 回的 Δ 是**增量**——指针路径每次只给「自上一事件以来的
// 位移」，键盘路径给的是固定步进。两者都要求「下一次从上一次的结果继续」，
// 所以锚点必须随每次应用推进。不推进的话：
//   - 连按两次方向键只会重复同一个宽度（键盘等价入口白装）；
//   - 指针拖拽一移动就弹回会话起点（这个 bug 在 f8 之前就存在，被 88c48cdd
//     原样继承了，因为合并控件时只改了回调签名、没动算法）。
// 两条路径共用这一份算法，所以这里两个方向都钉。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/core/theme/apple_focus.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/shared/widgets/canvas_drag_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 装一个带文字块的画布页（独立画作模式）。
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

  /// 点选文字块，让宽度手柄出现（`_onItemTap` → `_selectedItemId`）。
  ///
  /// 必须 pump 过一整个双击窗口：文字块的 GestureDetector 同时挂了
  /// `onTap` 与 `onDoubleTap`，单次点按要等双击超时（300ms）被判给单击
  /// 一方才会触发。只 pump 100ms 的话 arena 还悬着，选中根本没发生。
  Future<void> selectText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 把视口变换钉成 scale=1 / offset=0：此时「屏幕 1px == 画布 1px」，
  /// 断言里的算术（8 / 32 / 累加）不受测试窗口尺寸影响——否则画布会自动
  /// 适配视口（本机 800×600 窗口下 scale≈0.298），步长会被换成 26.83。
  ///
  /// 必须在选中**之后**做：选中靠的是自然适配下的命中，改完变换对象在
  /// 视图里的位置就变了。
  Future<void> pinViewTransform(WidgetTester tester, DrawingDocument doc) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorPage)),
      listen: false,
    );
    final controller = container.read(drawingControllerProvider(doc));
    controller.viewScale = 1;
    controller.viewOffset = Offset.zero;
    controller.tickFrame();
    await tester.pump();
  }

  /// 取宽度手柄的 Focus 节点。
  ///
  /// 取法与 `resize_handles_test.dart` 同源：`CanvasDragHandle` 内部是两层
  /// Focus，外层自己（可聚焦、收按键），内层是 `AppleFocusRing` 的观察节点
  /// （`canRequestFocus: false`）。AppleFocusRing 的**元素自身**位于它内部
  /// 那个 Focus 之上，所以 `Focus.maybeOf` 找到的第一个 `_FocusInheritedScope`
  /// 正是手柄节点。
  ///
  /// 必须先限定在 `CanvasDragHandle` 内：编辑器里还有别的 AppleFocusRing
  /// （按钮、工具条），直接 `find.byType` 会命中多个。
  FocusNode handleFocus(WidgetTester tester) {
    final ring = find.descendant(
      of: find.byType(CanvasDragHandle),
      matching: find.byType(AppleFocusRing),
    );
    expect(ring, findsOneWidget, reason: '宽度手柄内必须有一个焦点环');
    final node = Focus.maybeOf(tester.element(ring));
    expect(node, isNotNull, reason: '宽度手柄必须挂在焦点树上');
    return node!;
  }

  testWidgets('文字宽度手柄：聚焦后方向键累加宽度，字号等比跟随', (tester) async {
    final doc = DrawingDocument(id: 't1', title: '探针');
    final item = PageTextItem(
      id: 'txt1',
      x: 120,
      y: 120,
      text: '宽度探针',
      width: 300,
      fontSize: 24,
    );
    doc.textItems.add(item);
    await pumpEditor(tester, doc);
    await selectText(tester, '宽度探针');
    await pinViewTransform(tester, doc);

    expect(
      find.byType(CanvasDragHandle),
      findsOneWidget,
      reason: '选中且有宽度时手柄必须出现',
    );

    final node = handleFocus(tester);
    node.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // scale=1 / rotation=0 ⇒ 画布增量 = 屏幕增量 = keyStep(8)。
    expect(item.width, closeTo(308, 0.001), reason: '一次右键 = 一个步长');
    // 字号随宽度等比缩放（24 × 308/300）。
    expect(item.fontSize, closeTo(24 * 308 / 300, 0.001));

    // Shift 加速档：32px（`CanvasDragHandle.keyStepFast`）。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      item.width,
      closeTo(340, 0.001),
      reason: 'Shift 档 32px，且必须从上一次的结果继续（锚点已推进）',
    );
    expect(item.fontSize, closeTo(24 * 340 / 300, 0.001));

    // 反向：左箭头回到 332。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(item.width, closeTo(332, 0.001));
  });

  testWidgets('文字宽度手柄：指针拖拽与键盘同算法——增量累加，不弹回锚点', (tester) async {
    final doc = DrawingDocument(id: 't4', title: '探针');
    final item = PageTextItem(
      id: 'txt4',
      x: 120,
      y: 120,
      text: '宽度探针四',
      width: 300,
      fontSize: 24,
    );
    doc.textItems.add(item);
    await pumpEditor(tester, doc);
    await selectText(tester, '宽度探针四');
    await pinViewTransform(tester, doc);

    final handle = find.byType(CanvasDragHandle);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    // 先喂过 kPanSlop（36px）：前两次移动只用于让 pan 收纳指针。
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    final anchored = item.width!;

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(
      item.width,
      closeTo(anchored + 20, 0.001),
      reason: '第一次增量落在会话锚点上',
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(
      item.width,
      closeTo(anchored + 40, 0.001),
      reason: '第二次必须从第一次的结果继续，而不是回到锚点',
    );
    expect(
      item.fontSize / item.width!,
      closeTo(24 / 300, 0.000001),
      reason: '字号/宽度比值守恒（等比缩放的不变量）',
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('文字宽度手柄：失焦清空会话基准，之后再按不生效', (tester) async {
    final doc = DrawingDocument(id: 't2', title: '探针');
    final item = PageTextItem(
      id: 'txt2',
      x: 120,
      y: 120,
      text: '宽度探针二',
      width: 300,
      fontSize: 24,
    );
    doc.textItems.add(item);
    await pumpEditor(tester, doc);
    await selectText(tester, '宽度探针二');
    await pinViewTransform(tester, doc);

    final node = handleFocus(tester);
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(item.width, closeTo(308, 0.001));

    // 失焦 = 会话结束（锚点清空）。此后按键不再改宽度；页面级也**不该**
    // 改位置——普通方向键只服务 Alt+方向键（微调位置，见
    // `editor_page_shortcuts.dart` 的 `_nudgeSelected` 分支）。
    node.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(item.width, closeTo(308, 0.001));
    expect(item.x, 120);
    expect(item.y, 120);
  });

  testWidgets('文字宽度手柄：Tab 离开手柄，不被页面级轮选截走', (tester) async {
    final doc = DrawingDocument(id: 't3', title: '探针');
    final item = PageTextItem(
      id: 'txt3',
      x: 120,
      y: 120,
      text: '宽度探针三',
      width: 300,
      fontSize: 24,
    );
    doc.textItems.add(item);
    await pumpEditor(tester, doc);
    await selectText(tester, '宽度探针三');
    await pinViewTransform(tester, doc);

    final node = handleFocus(tester);
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);

    // 页面级 V-01 把 Tab 当「轮选画布对象」；手柄必须自己吞掉并转发，
    // 否则键盘用户在手柄上按 Tab 会跳去轮选对象，再也回不到手柄。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(node.hasFocus, isFalse, reason: '一次 Tab 必须离开手柄');
  });
}
