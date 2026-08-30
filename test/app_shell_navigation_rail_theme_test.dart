import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/app/app_shell.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';

/// M11 回归：app_shell NavigationRail 底色遵循「双模式单风格」。
///
/// 背景：交接报告 §10.1 曾记录"app_shell 最左导航栏亮色下仍为深蓝底"。
/// 经实测（M11 探针）该问题在 master 上已不复现——material_ui
/// NavigationRail 默认 backgroundColor = colorScheme.surface，
/// 亮色为 Apple 白，暗色为刻意保留的深蓝。本测试锁定该行为，
/// 防止主题改动（尤其 material_ui 方言下的组件默认值）导致退化。
void main() {
  Future<void> pumpShell(WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        // 与 app.dart 相同：双 GlobalMaterialLocalizations 委托（mui + Flutter）。
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
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

  testWidgets('亮色模式：NavigationRail 底色为 Apple 白 #FFFFFF', (tester) async {
    useWideView(tester);
    await pumpShell(tester, AppDesign.lightTheme());
    expect(railMaterial(tester).color, const Color(0xFFFFFFFF));
  });

  testWidgets('暗色模式：NavigationRail 底色为深蓝 #181F2E（刻意保留）', (tester) async {
    useWideView(tester);
    await pumpShell(tester, AppDesign.darkTheme());
    expect(railMaterial(tester).color, const Color(0xFF181F2E));
  });
}
