// 玻璃 FAB 测试（FAB 属浮层，可用玻璃；交互行为归原生 FAB）。
//
// 覆盖：circular / extended 渲染 / onPressed 回调 / heroTag 透传
// （all_docs 与 home 同 IndexedStack 共存靠显式 tag 避 hero 冲突）/
// FAB 材质全透明（玻璃由外层 GlassSurface 提供，不叠色板）/
// 配方常量（sigma 16、基底 0.72、圆角 28）/ 红线：整棵树一层
// BackdropFilter（玻璃壳自身裁剪，FAB ink 不新增模糊层）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/glass_fab.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

void main() {
  // L3 罩含微光闪烁（每帧重绘），固定时长 pump，禁用 pumpAndSettle。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }

  Widget host(Widget fab) => MaterialApp(
    home: Scaffold(floatingActionButton: fab, body: const SizedBox.shrink()),
  );

  testWidgets('圆形：渲染 icon，onPressed 触发，无异常', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      host(GlassFab(onPressed: () => pressed++, child: const Icon(Icons.add))),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    expect(pressed, 1);
  });

  testWidgets('extended：渲染 icon + label，onPressed 触发', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      host(
        GlassFab.extended(
          onPressed: () => pressed++,
          icon: const Icon(Icons.add),
          label: const Text('NEW_CANVAS'),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('NEW_CANVAS'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    expect(pressed, 1);
  });

  testWidgets('heroTag 透传到内部 FAB（hero 冲突防护依赖显式 tag）', (tester) async {
    await tester.pumpWidget(
      host(
        GlassFab(
          onPressed: () {},
          heroTag: 'glassFabTestTag',
          child: const Icon(Icons.add),
        ),
      ),
    );
    await settle(tester);
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.heroTag, 'glassFabTestTag');
  });

  testWidgets('内部 FAB 材质全透明（玻璃壳提供基底，不叠色板）', (tester) async {
    await tester.pumpWidget(
      host(
        GlassFab.extended(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('X'),
        ),
      ),
    );
    await settle(tester);
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.backgroundColor, Colors.transparent);
    expect(fab.elevation, 0);
    expect(fab.highlightElevation, 0);
    expect(fab.hoverElevation, 0);
    expect(fab.focusElevation, 0);
  });

  testWidgets('配方常量与玻璃弹窗同家族', (tester) async {
    expect(GlassFab.kSigma, 16);
    expect(GlassFab.kSurfaceOpacity, 0.72);
    expect(GlassFab.kRadius, 28);
  });

  testWidgets('红线：整棵树只允许一层 BackdropFilter', (tester) async {
    await tester.pumpWidget(
      host(GlassFab(onPressed: () {}, child: const Icon(Icons.add))),
    );
    await settle(tester);
    expect(
      find.byType(BackdropFilter),
      findsOneWidget,
      reason: 'GlassSurface 自带唯一模糊层；FAB ink/state layer 不允许再加',
    );
  });

  testWidgets('GlassSurface 边界裁剪为胶囊圆角（kRadius）', (tester) async {
    await tester.pumpWidget(
      host(GlassFab(onPressed: () {}, child: const Icon(Icons.add))),
    );
    await settle(tester);
    final surface = tester.widget<GlassSurface>(find.byType(GlassSurface));
    expect(
      surface.borderRadius,
      const BorderRadius.all(Radius.circular(GlassFab.kRadius)),
    );
  });
}
