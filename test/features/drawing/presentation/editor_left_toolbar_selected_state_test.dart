// 工具条「选中态」编码的第二个落点（2026-10-15）。
//
// 起因是一条红了五天没人发现的缺陷：这条编码此前**只**写在
// `integration_test/toolbar_test.dart` 里，而 CI 从不跑 `integration_test`。
// 2026-10-09 那批触觉改动（`71da1ea`）在 `Tooltip` 与蓝底之间插了一层
// `GestureDetector`，而断言按「公开 Tooltip 的直接子节点是不是 `Container`」判 ⇒
// 真机 5 条当场红，`flutter analyze` 与七条云端编排全绿——它们都看不见这条命题。
//
// 本文件把同一条命题搬到 `flutter test` 看得见的地方，并刻意**不依赖中转层数**：
// 选中态有两份，两份同时要求——① `Semantics(properties.selected: true)`（读屏用户
// 得到的那一份，P1-9 加的），② `AppleColor.actionBlue` 那块蓝底（用户看得见的那一份，
// 见 `editor_left_toolbar.dart` 的 `_tool`）。
//
// 再加三条集成测试里没有的整体约束：
// - 整个工具条**同时只能有一个**语义选中、**只能有一个**蓝底——否则「所有工具都画成
//   选中」这种回归在逐条判选中/未选中时可能一侧仍为真；
// - 互斥：`tool == pen` 但吸管激活时，画笔**不得**算选中。这正是 `_tool` 那串
//   `&& selectionTool == none && !eyedropperActive && …` 存在的全部理由，此前无守卫；
// - 点击真换档：选中态跟着控制器走。
//
// ⚠️ 装配必须复刻宿主的**重建纪律**，不是随便 pump 一个 StatelessWidget 就算数：
// 真实宿主 `EditorPage` 的 `_selectWritingTool`（`editor_page_tools.dart:100`）把
// 「写 `controller.tool`」和 `setState` 放在同一个动作里，于是整棵工具条会重建。
// 这一点有产品侧原因：`EditorLeftToolbar.build` 在 `ListenableBuilder` **外面**算了
// `isEraser`（`editor_left_toolbar.dart:77`），橡皮擦那一格的选中值靠宿主重建才刷新，
// 而其余几格读的是 builder 内的实时值。所以本文件的每个选档回调都同时
// 「写控制器 + 触发重建」；少了后半步，测的就不是用户拿到的那个形状。
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_left_toolbar.dart';

void main() {
  const penTip = '画笔 (P)';
  const eraserTip = '橡皮擦 (E)';
  const eyedropperTip = '吸管工具';

  /// 与 `editor_insert_image_entry_test.dart` 同一装配：不给本地化代理，
  /// `AppLocalizations.of(context)` 返回 null ⇒ 工具条走 arb 缺失时的中文兜底串，
  /// 与集成测试里 `find.byTooltip` 命中的是同一批字面量。
  ///
  /// [rebuild] 是宿主那半边动作（真实实现里就是 `setState`）：选档 = 写控制器 + 重建。
  Widget host(
    DrawingController controller, {
    required void Function() rebuild,
    bool eyedropperActive = false,
  }) => MaterialApp(
    home: Scaffold(
      body: EditorLeftToolbar(
        controller: controller,
        eyedropperActive: eyedropperActive,
        textToolActive: false,
        marqueeActive: false,
        linkMode: false,
        handActive: false,
        onHand: rebuild,
        activeShape: null,
        onBrush: () {
          controller.tool = BrushType.pen;
          rebuild();
        },
        onPencil: () {
          controller.tool = BrushType.pencil;
          rebuild();
        },
        onHighlighter: () {
          controller.tool = BrushType.marker;
          rebuild();
        },
        onLaser: () {
          controller.tool = BrushType.laser;
          rebuild();
        },
        onEraser: () {
          controller.tool = BrushType.eraser;
          rebuild();
        },
        onEyedropper: rebuild,
        onRectSelect: rebuild,
        onMarquee: rebuild,
        onText: rebuild,
        onShape: (_) => rebuild(),
        onLink: rebuild,
        onInsertImage: () {},
      ),
    ),
  );

  /// 拆树再 dispose：`DrawingController` 构造即起计时器
  /// （`LayerRenderCacheCoordinator.touchActivity`，30s），而 binding 的
  /// 「无悬挂 Timer」不变式在**测试体结束处**校验 ⇒ `addTearDown` 太晚，
  /// 必须在用例末尾显式收尾（兄弟测试 `editor_insert_image_entry_test.dart` 同款）。
  Future<void> unmount(WidgetTester tester, DrawingController controller) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
  }

  /// 选中态的语义那一侧：带 `properties.selected == true` 的 `Semantics`。
  Finder selectedSemantics() => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.selected == true,
  );

  /// 选中态的视觉那一侧：Action Blue 底色块。工具条里合法出现位置只有两处
  /// （`_tool` 的选中分支、形状菜单的选中分支），本装配下 `activeShape == null`，
  /// 所以「恰好一块」是可实现、可判定的约束。
  Finder accentBlocks() => find.byWidgetPredicate((w) {
    if (w is! Container) return false;
    final d = w.decoration;
    return d is BoxDecoration && d.color == AppleColor.actionBlue;
  });

  /// 某个工具自己是不是选中：它的 `Semantics` 祖先被标为选中，**且**蓝底落在同一子树里。
  bool toolSelected(WidgetTester tester, String tooltip) {
    final marked = find.ancestor(
      of: find.byTooltip(tooltip),
      matching: selectedSemantics(),
    );
    if (marked.evaluate().isEmpty) return false;
    return find
        .descendant(of: marked, matching: accentBlocks())
        .evaluate()
        .isNotEmpty;
  }

  testWidgets('初始：只有画笔是选中态，且全条只有一个语义标记与一块蓝底', (
    tester,
  ) async {
    final controller = DrawingController(
      DrawingDocument(id: 'sel_state_initial', title: '选中态回归'),
    );
    await tester.pumpWidget(
      StatefulHost(builder: (rebuild) => host(controller, rebuild: rebuild)),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip(penTip), findsOneWidget);
    expect(find.byTooltip(eraserTip), findsOneWidget);
    expect(toolSelected(tester, penTip), isTrue, reason: '默认工具就是画笔');
    expect(toolSelected(tester, eraserTip), isFalse);
    // 整体约束：不是「这一个看起来选中」，而是「只有这一个选中」。
    expect(selectedSemantics(), findsOneWidget);
    expect(accentBlocks(), findsOneWidget);

    await unmount(tester, controller);
  });

  testWidgets('点橡皮擦：选中的是哪一个跟着控制器走，且仍然只有一个', (
    tester,
  ) async {
    final controller = DrawingController(
      DrawingDocument(id: 'sel_state_tap', title: '选中态回归'),
    );
    await tester.pumpWidget(
      StatefulHost(builder: (rebuild) => host(controller, rebuild: rebuild)),
    );
    await tester.pumpAndSettle();
    expect(controller.tool, BrushType.pen);

    await tester.tap(find.byTooltip(eraserTip));
    await tester.pumpAndSettle();

    expect(controller.tool, BrushType.eraser, reason: '回调确实写了控制器');
    expect(
      toolSelected(tester, eraserTip),
      isTrue,
      reason: '蓝底与语义都要落到橡皮擦这一格',
    );
    expect(toolSelected(tester, penTip), isFalse);
    expect(selectedSemantics(), findsOneWidget);
    expect(accentBlocks(), findsOneWidget);

    // 再点回画笔：退出选中的必须是橡皮擦（选中值不能停在旧快照上）。
    await tester.tap(find.byTooltip(penTip));
    await tester.pumpAndSettle();
    expect(toolSelected(tester, eraserTip), isFalse);
    expect(toolSelected(tester, penTip), isTrue);
    expect(selectedSemantics(), findsOneWidget);

    await unmount(tester, controller);
  });

  testWidgets('互斥：吸管激活时控制器仍是 pen，画笔那格也必须退出选中态', (
    tester,
  ) async {
    final controller = DrawingController(
      DrawingDocument(id: 'sel_state_mutex', title: '互斥回归'),
    );
    var eyedropperActive = false;
    await tester.pumpWidget(
      StatefulHost(
        builder: (rebuild) => host(
          controller,
          rebuild: () => rebuild(),
          eyedropperActive: eyedropperActive,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      toolSelected(tester, penTip),
      isTrue,
      reason: '先确认基线：pen 且无其他模式 ⇒ 选中',
    );

    // 宿主侧的真实形状：吸管是页面持有的一个独立模式位，控制器工具类型不变。
    eyedropperActive = true;
    await tester.pumpWidget(
      StatefulHost(
        builder: (rebuild) => host(
          controller,
          rebuild: () => rebuild(),
          eyedropperActive: eyedropperActive,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.tool, BrushType.pen, reason: '吸管不改工具类型');
    expect(
      toolSelected(tester, penTip),
      isFalse,
      reason: '另一档模式激活时 pen 那格必须退出选中——这是 `_tool` 那串互斥条件的全部意义',
    );
    expect(toolSelected(tester, eyedropperTip), isTrue);
    expect(selectedSemantics(), findsOneWidget);
    expect(accentBlocks(), findsOneWidget);

    await unmount(tester, controller);
  });
}

/// 一个只提供 `setState` 闭包的宿主，等价于 `EditorPage` 的 `_applyState`：
/// 工具条的选中态有两半来源（控制器 + 页面持有的模式位），宿主重建是它的一部分。
class StatefulHost extends StatefulWidget {
  const StatefulHost({required this.builder, super.key});

  final Widget Function(void Function() rebuild) builder;

  @override
  State<StatefulHost> createState() => _StatefulHostState();
}

class _StatefulHostState extends State<StatefulHost> {
  @override
  Widget build(BuildContext context) =>
      widget.builder(() => setState(() {}));
}
