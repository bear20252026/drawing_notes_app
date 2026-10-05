// AR-1（审计 2026-10-05）回归：画布编辑器必须有可用的「插入图片」入口。
//
// 缘起：旧横栏 editor_toolbar.dart 随 `247f3b1` 整文件删除后，`_insertImage` 只剩
// `EditorToolbarActions.insertImage` 这个全 lib 无人读取的字段，而 arb 键与首启引导
// 文案仍在宣称「图片按钮插入」——静态文案门禁全绿，真机必红。
// `integration_test/toolbar_test.dart` 里那条用例能证明缺口，但 integration_test
// **不在 CI 覆盖内**（`flutter test` 不含它），所以入口本身钉在单元层：
// ① 按钮渲染出来且回调真被调用（不依赖文件选择插件）；
// ② 装配后的页面里入口可达；
// ③ 键盘可激活（AGENTS.md §3 三输入硬要求）。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_left_toolbar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/wait_until.dart';

void main() {
  /// 仅用于验证工具条本体：其余工具回调是空实现，只观察图片动作被调用几次。
  ///
  /// `DrawingController` 构造即起临时墨迹 tick（drawing_controller.dart:64 注释），
  /// 而 binding 的「无悬挂 Timer」不变式在测试体结束时就校验——`addTearDown` 太晚。
  /// 故控制器由测试体自持，并在用例末尾显式拆树 + dispose。
  Widget toolbarHost({
    required DrawingController controller,
    required VoidCallback onInsertImage,
  }) => MaterialApp(
    home: Scaffold(
      body: EditorLeftToolbar(
        controller: controller,
        eyedropperActive: false,
        textToolActive: false,
        marqueeActive: false,
        linkMode: false,
        handActive: false,
        onHand: () {},
        activeShape: null,
        onBrush: () {},
        onPencil: () {},
        onHighlighter: () {},
        onLaser: () {},
        onEraser: () {},
        onEyedropper: () {},
        onRectSelect: () {},
        onMarquee: () {},
        onText: () {},
        onShape: (_) {},
        onLink: () {},
        onInsertImage: onInsertImage,
      ),
    ),
  );

  DrawingController newController() =>
      DrawingController(
        DrawingDocument(id: 'insert_img_doc', title: '插入图片回归'),
      );

  Future<void> teardownToolbar(WidgetTester tester, DrawingController controller) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
  }

  Future<void> pumpEditorPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EditorPage(
            document: DrawingDocument(
              id: 'insert_img_page_doc',
              title: '插入图片页面装配',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpUntil(
      () => find.byType(EditorLeftToolbar).evaluate().isNotEmpty,
    );
  }

  testWidgets('入口存在且真被接线：点击「插入图片」调用回调一次', (tester) async {
    var calls = 0;
    final controller = newController();
    await tester.pumpWidget(
      toolbarHost(controller: controller, onInsertImage: () => calls++),
    );

    final button = find.byTooltip('插入图片');
    expect(button, findsOneWidget);
    // 动作项不是工具态：不得包在选中底色（Action Blue 容器）里。
    expect(
      find.descendant(of: button, matching: find.byType(IconButton)),
      findsOneWidget,
    );

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    await teardownToolbar(tester, controller);
  });

  testWidgets('键盘可激活：Tab 遍历能停靠并按空格触发（AGENTS.md §3）', (tester) async {
    var calls = 0;
    final controller = newController();
    await tester.pumpWidget(
      toolbarHost(controller: controller, onInsertImage: () => calls++),
    );

    final button = find.descendant(
      of: find.byTooltip('插入图片'),
      matching: find.byType(IconButton),
    );
    expect(button, findsOneWidget);
    final imageElement = tester.element(button);

    // IconButton 的 FocusNode 由 InkResponse 内部创建、不对外暴露，本仓
    // Flutter 3.47 的 WidgetTester 也没有 getFocus 类 API ⇒ 走公开遍历：
    // 从图片按钮元素的祖先 FocusScope 起 nextFocus，直到停靠点落在按钮子树里。
    final scope = FocusScope.of(imageElement);
    var reached = false;
    for (var i = 0; i < 40 && !reached; i++) {
      scope.nextFocus();
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused is! Element) continue;
      focused.visitAncestorElements((ancestor) {
        if (ancestor != imageElement) return true;
        reached = true;
        return false;
      });
    }
    expect(reached, isTrue, reason: '插入图片按钮必须 Tab 可达');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(calls, 1);
    await teardownToolbar(tester, controller);
  });

  testWidgets('页面装配后入口仍在（防接线被再次重构丢掉）', (tester) async {
    await pumpEditorPage(tester);

    final button = find.byTooltip('插入图片');
    expect(button, findsOneWidget);

    // 浮动玻璃岛在短画布上可滚动，先滚入可视区（同 editor_shortcuts_text_guard_test）。
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    // 单测环境没有 file_selector 实现，_insertImage 的 catch 兜住并给出提示；
    // 这里只要求异常不外泄、页面仍然存活——不断言提示文案（改文案会连带炸红）。
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(EditorLeftToolbar), findsOneWidget);
  });
}
