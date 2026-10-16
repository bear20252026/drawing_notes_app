// TST2-08 / TST2-09 的 CI 可见第二落点（第四轮审计 2026-10-16）。
//
// 缘起：这三条命题以前**只有 `integration_test/feature_test.dart` 一个落点**，
// 而 `integration_test` 不在 CI 覆盖范围内——`ci.yml` 跑的是 `flutter test`
// （只吃 `test/`），`release-build.yml` 打 tag 时也只跑 `smoke_test.dart -d windows`。
// 于是「图层面板默认关闭 / 顶栏开关能打开它 / 新建图层是一条可撤销的历史记录」
// 这三件事在每一次合并门禁上都是**没人验**的状态；而 `grep -rl LayerPanel test/`
// 实测为 **0 个文件**，连提及都没有。
//
// 顺带把另一条同族的空洞补上：那条用例名里写着「不崩溃」，历史上从没真的建过图层
// （integration 侧后来改成了硬断言，但同样不在 CI 上跑）。这里钉的是**内容级**结果：
// 图层数 +1 → Ctrl+Z → 回到原值，而不是「点下去没抛异常」。
//
// 反向锁（第三条用例）：窄屏（<600dp）顶栏**不放**这枚开关，它收进主菜单——
// 这条钉的是「顶栏低频开关的窄屏收纳」本身，别把它改成「哪找都一样」。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/drawing/presentation/layer_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpEditor(
    WidgetTester tester,
    DrawingDocument document, {
    Size screen = const Size(1280, 900),
    VoidCallback? onChanged,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EditorPage(document: document, onChanged: onChanged),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('图层面板默认不渲染；顶栏「显示图层」开关把它打开', (tester) async {
    final document = DrawingDocument(id: 'lp1', title: '图层显隐');
    await pumpEditor(tester, document);

    expect(
      find.byType(LayerPanel),
      findsNothing,
      reason: '初值 false（`_layersVisible` 不读盘）——「常驻渲染」那种旧行为不能回来',
    );

    final toggle = find.byTooltip('显示图层');
    expect(
      toggle,
      findsOneWidget,
      reason: '宽屏顶栏必须有这枚开关，否则上面那句 findsNothing 只是进不去而已',
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '打开面板不该抛异常');
    expect(
      find.byType(LayerPanel),
      findsOneWidget,
      reason: '开关必须真的改变渲染结果，不是只换个 tooltip 字样',
    );
  });

  testWidgets('面板里点「新建图层」必须真加一层，且 Ctrl+Z 能撤回来', (tester) async {
    final document = DrawingDocument(id: 'lp2', title: '图层内容级');
    var notifications = 0;
    await pumpEditor(
      tester,
      document,
      onChanged: () => notifications++,
    );
    await tester.tap(find.byTooltip('显示图层'));
    await tester.pumpAndSettle();

    final before = document.layers.length;
    expect(
      find.byTooltip('新建图层'),
      findsOneWidget,
      reason: '面板都渲染出来了，按钮必须找得到（找不到就是这条落点空跑）',
    );
    await tester.tap(find.byTooltip('新建图层'));
    await tester.pumpAndSettle();

    expect(
      document.layers.length,
      before + 1,
      reason: '点一下就在文档里真加一层——「没抛异常」不算通过',
    );
    expect(
      notifications,
      greaterThan(0),
      reason:
          '图层操作还必须**通知上级落盘**（`editor_page_body.dart` 那句「onChanged 必传」的接线）。'
          '只改文档不通知，界面看起来一切正常，退出时却什么都没存下来。',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      document.layers.length,
      before,
      reason: '新建图层必须是一条可撤销的历史记录；撤销不回来就是撤销栈没接上',
    );
  });

  testWidgets('反向锁：窄屏（390dp）顶栏不放这枚开关——它收进主菜单', (tester) async {
    final document = DrawingDocument(id: 'lp3', title: '窄屏收纳');
    await pumpEditor(tester, document, screen: const Size(390, 844));

    expect(tester.takeException(), isNull, reason: '窄屏画板编辑器不该溢出或崩');
    expect(
      find.byTooltip('显示图层'),
      findsNothing,
      reason:
          '顶栏低频开关在 <600dp 收进主菜单（editor_page_appbar.dart 的窄屏分支）。'
          '若这枚开关在窄屏也出现，这条断言红——那说明低频开关的窄屏收纳被改掉了，'
          '需要重新裁一次 390dp 的顶栏空间，而不是直接把本用例改掉。',
    );
  });
}
