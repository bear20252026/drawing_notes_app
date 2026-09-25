import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/app/app_shell.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/shared/widgets/glass_navigation_rail.dart';

/// M11 回归（v1.17.20 更新）：app_shell 宽屏侧栏为玻璃材质替换壳。
///
/// 历史锁定（M11）：NavigationRail 底色曾为「亮色 Apple 白 / 暗色刻意
/// 保留深蓝 #181F2E」。v1.17.20 导航域玻璃化收尾——侧栏换装
/// [GlassNavigationRail]（与窄屏 GlassNavigationBar 同配方家族）：
/// NavigationRail 材质三件套全透明，底色由玻璃壳（GlassSurface）提供，
/// M3 indicator（选中交互态）保留。本测试更新为锁定玻璃化行为：
/// - Rail 自身 Material 不再携带不透明底色；
/// - 玻璃壳存在且材质透明（避免玻璃叠玻璃回归）。
void main() {
  Future<void> pumpShell(WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        // 与 app.dart 相同：双 GlobalMaterialLocalizations 委托（mui + Flutter）。
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('zh'), Locale('en')],
        home: const AppShell(),
      ),
    );
    // AppShell 含常驻环境背景动画（ambient_background），不能 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Material railMaterial(WidgetTester tester) {
    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    return tester.widget<Material>(
      find.descendant(of: rail, matching: find.byType(Material)).first,
    );
  }

  void useWideView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('亮色模式：Rail 材质透明（底色由玻璃壳提供），亮暗共用玻璃', (
    tester,
  ) async {
    useWideView(tester);
    await pumpShell(tester, AppDesign.lightTheme());
    // 玻璃化后 Rail 自身不再提供不透明底色——透明三件套由
    // GlassNavigationRail 显式置定。
    expect(railMaterial(tester).color, Colors.transparent);
    expect(find.byType(GlassNavigationRail), findsOneWidget);
  });

  testWidgets('暗色模式：同样玻璃壳承载（单风格双模式，无暗色特判底色）', (
    tester,
  ) async {
    useWideView(tester);
    await pumpShell(tester, AppDesign.darkTheme());
    expect(railMaterial(tester).color, Colors.transparent);
    expect(find.byType(GlassNavigationRail), findsOneWidget);
  });
}
