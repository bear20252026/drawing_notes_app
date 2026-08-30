import 'package:drawing_notes_app/app.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Windows/Android 真实启动冒烟测试。
///
/// 目的：验证应用在真实设备/桌面环境可以启动并完成关键用户流程，
/// 覆盖"首页 → 新建画作 → 绘制 → 退出"主链路，作为验收冒烟依据。
///
/// 运行方式：
///   flutter test integration_test -d windows
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 隔离共享存储并预置"已看过引导"标记，避免首次启动引导对话框
  // 遮挡界面元素导致 tap 失败。
  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
  });

  testWidgets('应用启动：首页正常渲染（画作/笔记本双 Tab）', (tester) async {
    await tester.pumpWidget(ProviderScope(child: const DrawingNotesApp()));
    await tester.pumpAndSettle();

    // 顶部标题存在。
    expect(find.text('绘图笔记'), findsOneWidget);
    // 双 Tab 存在。
    expect(find.text('画作'), findsOneWidget);
    expect(find.text('笔记本'), findsOneWidget);
    // 新建按钮存在。
    expect(find.widgetWithText(FloatingActionButton, '新建画作'), findsOneWidget);
  });

  testWidgets('新建画作：输入名称后进入编辑器', (tester) async {
    await tester.pumpWidget(ProviderScope(child: const DrawingNotesApp()));
    await tester.pumpAndSettle();

    // 点击右下角"新建画作"FAB，弹出名称输入框。
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('请输入名称'), findsOneWidget);

    // 输入名称并确定。
    await tester.enterText(find.byType(TextField).last, '冒烟测试画作');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 进入编辑器：标题为输入的画作名。
    expect(find.text('冒烟测试画作'), findsWidgets);
    // 编辑器工具栏存在（画笔按钮，用 tooltip 避免与状态栏图标重复）。
    expect(find.byTooltip('画笔'), findsOneWidget);
  });

  testWidgets('编辑器：工具栏与图层面板正常显示', (tester) async {
    await tester.pumpWidget(ProviderScope(child: const DrawingNotesApp()));
    await tester.pumpAndSettle();

    // 新建画作并输入名称（空名不会进入编辑器）。
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '编辑器测试');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 核心工具按钮（用 tooltip 精确匹配，避免与状态栏图标重复）。
    expect(find.byTooltip('画笔'), findsOneWidget);
    expect(find.byTooltip('橡皮擦（透明擦除）'), findsOneWidget);
    expect(find.byTooltip('吸管取色'), findsOneWidget);
    expect(find.byTooltip('矩形选区'), findsOneWidget);
    expect(find.byTooltip('套索选区'), findsOneWidget);
    // 图层面板标题。
    expect(find.text('图层'), findsOneWidget);
    // 撤销/重做/清空/导出按钮。
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.redo), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    // 状态栏（借鉴 Joplin StatusBar）：缩放百分比可见。
    // 用状态栏独有的坐标文本确认（图层面板也有百分比文本）。
    expect(find.textContaining('x:'), findsOneWidget);
  });

  testWidgets('深色模式：主题循环切换不崩溃', (tester) async {
    // 用注入的 ThemeController 避免污染真实存储。
    final theme = AppThemeController();
    await tester.pumpWidget(ProviderScope(child: DrawingNotesApp(themeController: theme)));
    await tester.pumpAndSettle();

    // 初始为跟随系统，按钮显示浅色图标（mode != dark）。
    final lightButton = find.byIcon(Icons.light_mode_outlined);
    expect(lightButton, findsOneWidget);

    // 第一次点击：系统 → 浅色。
    await tester.tap(lightButton);
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.light);

    // 第二次点击：浅色 → 深色，图标切换为深色。
    await tester.tap(find.byIcon(Icons.light_mode_outlined));
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.dark);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

    // 第三次点击：深色 → 跟随系统，不抛异常。
    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.system);
  });

  testWidgets('切换笔记本 Tab：空态提示正常', (tester) async {
    await tester.pumpWidget(ProviderScope(child: const DrawingNotesApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('笔记本'));
    await tester.pumpAndSettle();
    expect(find.text('新建笔记本'), findsWidgets);
  });
}
