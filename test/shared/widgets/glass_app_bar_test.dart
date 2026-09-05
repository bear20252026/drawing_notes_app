// 液态玻璃顶栏测试（Apple HIG：toolbars 属浮层，可用玻璃）。
//
// 覆盖：preferredSize 计算 / 布局行为与原生 AppBar 一致 / 背景全透明
// （避免叠色板）/ **红线：整棵树只允许一层 BackdropFilter，不得叠玻璃**。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/glass_app_bar.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

void main() {
  testWidgets('渲染标题与操作按钮，且无异常', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: GlassAppBar(
            title: Text('GLASS_TITLE'),
            actions: [Icon(Icons.search)],
          ),
          body: SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('GLASS_TITLE'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('preferredSize', () {
    test('无 bottom 时等于标准工具栏高度', () {
      const bar = GlassAppBar(title: Text('x'));
      expect(bar.preferredSize.height, kToolbarHeight);
    });

    test('带 bottom 时累加 bottom 高度', () {
      final bar = GlassAppBar(
        title: const Text('x'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: const SizedBox(),
        ),
      );
      expect(bar.preferredSize.height, kToolbarHeight + 56);
    });
  });

  testWidgets('内部 AppBar 背景全透明（玻璃由外层提供，不叠色板）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: GlassAppBar(title: Text('x')),
          body: SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.transparent);
    expect(appBar.surfaceTintColor, Colors.transparent);
    expect(appBar.elevation, 0);
    expect(appBar.scrolledUnderElevation, 0);
  });

  testWidgets('红线：整棵树只有一层 BackdropFilter，不得玻璃叠玻璃', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: GlassAppBar(
            title: const Text('x'),
            // bottom 插槽不得自带 GlassSurface——这里放一个普通容器验证。
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                alignment: Alignment.center,
                child: const Text('BOTTOM_PLAIN'),
              ),
            ),
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('BOTTOM_PLAIN'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('顶栏通栏不套圆角（圆角只用于浮动面板）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: GlassAppBar(title: Text('x')),
          body: SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    // 直接断言玻璃层的圆角输入——不查 ClipRRect，因为 L2/L3 走超椭圆
    // 会改用 ClipPath（ShapeBorderClipper），裁剪控件类型随档位变化。
    final glass = tester.widget<GlassSurface>(find.byType(GlassSurface));
    expect(glass.borderRadius, BorderRadius.zero);
  });

  testWidgets('减弱动效时退化为实色板仍可渲染', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            appBar: GlassAppBar(title: Text('REDUCED')),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('REDUCED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
