import 'package:drawing_notes_app/app.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Windows 真实启动冒烟测试（2026-09-06 重写对齐当前 IA）。
///
/// 目的：验证应用在真实桌面环境可以启动并完成关键用户流程：
/// 启动渲染 → 切换顶层标签 → 新建无限画布进入编辑器。
/// 布局无关：断言只依赖 NavigationRail/NavigationBar 共有的导航文案。
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

  testWidgets('应用启动：外壳与顶层导航正常渲染', (tester) async {
    await tester.pumpWidget(ProviderScope(child: const DrawingNotesApp()));
    await tester.pumpAndSettle();

    // 4 个顶层目的地在 Rail（宽）与底部导航（窄）两种布局下都存在。
    expect(find.text('全部文档'), findsWidgets);
    expect(find.text('画布·笔记'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('切换到画布·笔记：新建入口可见', (tester) async {
    await tester.pumpWidget(ProviderScope(child: const DrawingNotesApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('画布·笔记').first);
    await tester.pumpAndSettle();

    // 新建画布入口（画布 tab 的主行动按钮）。
    expect(find.text('新建画布'), findsWidgets);
  });

  testWidgets('新建无限画布：进入编辑器（工具栏在位）', (tester) async {
    await tester.pumpWidget(ProviderScope(child: const DrawingNotesApp()));
    await tester.pumpAndSettle();

    // 画布·笔记 → 新建画布 → 弹两选项 → 新建无限画布。
    await tester.tap(find.text('画布·笔记').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建画布').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建无限画布'));
    await tester.pumpAndSettle();

    // 命名对话框：输入名称并确定。
    await tester.enterText(find.byType(TextField).last, '冒烟测试画作');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 编辑器：标题为输入的画作名，核心工具在位。
    expect(find.text('冒烟测试画作'), findsWidgets);
    expect(find.byTooltip('画笔 (P)'), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.redo), findsOneWidget);
  });

  testWidgets('设置页可达：密码体系区块渲染', (tester) async {
    final theme = AppThemeController();
    await tester.pumpWidget(
      ProviderScope(child: DrawingNotesApp(themeController: theme)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();

    expect(find.text('密码体系'), findsOneWidget);
    expect(find.text('通用'), findsOneWidget);
  });
}
