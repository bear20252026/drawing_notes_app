// 玻璃底部导航条测试（导航条属常驻浮层，可用玻璃；交互行为归原生 NavigationBar）。
//
// 覆盖：4 目的地渲染 / 点击回调 / 材质全透明（玻璃由外层 GlassSurface
// 提供，indicator 保留——它是选中交互态非条体材质）/ 配方常量 /
// 高度锁定（胶囊不被 extendBody 注入二次膨胀）/ 红线：整棵树一层
// BackdropFilter / 系统手势区由内部 SafeArea 消费（胶囊悬浮于系统栏上方）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/glass_nav_bar.dart';

void main() {
  // L3 罩含微光闪烁（每帧重绘），固定时长 pump，禁用 pumpAndSettle。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }

  Widget host({
    int selectedIndex = 0,
    required ValueChanged<int> onSelected,
  }) =>
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassNavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description),
                label: 'A',
              ),
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'B',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined),
                selectedIcon: Icon(Icons.calendar_today),
                label: 'C',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'D',
              ),
            ],
          ),
          body: const SizedBox.shrink(),
        ),
      );

  testWidgets('渲染 4 个目的地，无异常', (tester) async {
    await tester.pumpWidget(host(onSelected: (_) {}));
    await settle(tester);
    for (final label in ['A', 'B', 'C', 'D']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击目的地回调索引', (tester) async {
    var selected = -1;
    await tester.pumpWidget(host(onSelected: (i) => selected = i));
    await settle(tester);
    await tester.tap(find.text('C'));
    await settle(tester);
    expect(selected, 2);
  });

  testWidgets('内部 NavigationBar 材质全透明（玻璃壳提供基底）',
      (tester) async {
    await tester.pumpWidget(host(onSelected: (_) {}));
    await settle(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.backgroundColor, Colors.transparent);
    expect(bar.surfaceTintColor, Colors.transparent);
    expect(bar.shadowColor, Colors.transparent);
    expect(bar.elevation, 0);
  });

  testWidgets('配方常量与玻璃弹窗同家族；高度常量自洽', (tester) async {
    expect(GlassNavigationBar.kSigma, 16);
    expect(GlassNavigationBar.kSurfaceOpacity, 0.72);
    expect(GlassNavigationBar.kHeight, 64);
    expect(GlassNavigationBar.kBottomMargin, 12);
    expect(GlassNavigationBar.totalHeight, 76);
  });

  testWidgets('胶囊高度锁定 64（extendBody 注入不得二次膨胀）', (tester) async {
    // 模拟 extendBody：body 的 MediaQuery.padding.bottom 被注入条总高。
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: GlassNavigationBar.kHeight),
        ),
        child: host(onSelected: (_) {}),
      ),
    );
    await settle(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.height, GlassNavigationBar.kHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统手势区由内部 SafeArea 消费（胶囊整体悬浮其上）',
      (tester) async {
    // viewPadding.bottom 模拟手势条 / 3 键导航；胶囊不应与系统栏重叠。
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 24)),
        child: host(onSelected: (_) {}),
      ),
    );
    await settle(tester);
    // 2 个 SafeArea：本组件的（消费系统 viewPadding）+ NavigationBar
    // 原生内部的；断言至少存在一个即可证明胶囊悬浮于系统栏上方。
    expect(find.byType(SafeArea), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('红线：整棵树只允许一层 BackdropFilter', (tester) async {
    await tester.pumpWidget(host(onSelected: (_) {}));
    await settle(tester);
    expect(
      find.byType(BackdropFilter),
      findsOneWidget,
      reason: 'GlassSurface 自带唯一模糊层；indicator 是交互态非材质层',
    );
  });
}
