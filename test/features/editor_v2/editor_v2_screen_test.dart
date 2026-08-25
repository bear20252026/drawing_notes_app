import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/editor_v2/presentation/editor_v2_screen.dart';

/// 批次 F 集成测试（CUJ-01 UI 层——EditorV2Screen 渲染——不崩验证）。
///
/// 验证：无限画布 + 工具栏 + 画布集成到 EditorV2Screen 后——
/// 渲染正常（无异常——不搞崩——AFFiNE/Saber 借鉴的渐进集成）。
void main() {
  testWidgets('EditorV2Screen 渲染（CUJ-01——无限画布/工具栏/画布集成——不崩）', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: EditorV2Screen(documentId: 'test-doc')),
    ));
    // 使用 pump 替代 pumpAndSettle，避免 AnimatedSwitcher 持续动画导致超时
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 工具栏存在（Draw/Select/形状工具）。
    expect(find.byTooltip('Draw'), findsOneWidget);
    expect(find.byTooltip('Select'), findsOneWidget);
    expect(find.byTooltip('Erase'), findsOneWidget);

    // 画布存在（CustomPaint——CanvasPainterV2 + InfiniteCanvasWidget 包装）。
    expect(find.byType(CustomPaint), findsWidgets);

    // AppBar 标题存在（documentId 未在 StorageService 中注册 → 显示'无标题'）。
    expect(find.text('无标题'), findsOneWidget);

    // 无异常（不崩——集成验证）。
    expect(tester.takeException(), isNull);
  });

  testWidgets('EditorV2Screen 侧边栏（AFFiNE 页面设计借鉴——页面导航——不崩）', (tester) async {
    // 设定移动端视口（iPhone 15 宽度 393 逻辑像素），
    // 使 context.isMobile == true，触发 Drawer。
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: EditorV2Screen(documentId: 'test-doc')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 打开侧边栏（Drawer——AFFiNE 侧边栏页面导航）。
    // AppBar 可能溢出，使用 warnIfMissed: false + force tap。
    final menuIcon = find.byIcon(Icons.menu);
    if (menuIcon.evaluate().isNotEmpty) {
      await tester.tap(menuIcon, warnIfMissed: false);
    } else {
      // 如果没有 menu icon（drawer 未启用），直接打开 drawer
      final scaffold = find.byType(Scaffold).first;
      final state = tester.state<ScaffoldState>(scaffold);
      state.openDrawer();
    }
    await tester.pump(const Duration(milliseconds: 500));

    // 侧边栏内容（页面管理 + 页面 1 + 新建/删除）。
    expect(find.text('页面管理'), findsOneWidget);
    expect(find.text('页面 1'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // 无异常（不崩）。
    expect(tester.takeException(), isNull);
  });
}
