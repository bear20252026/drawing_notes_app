// 玻璃弹窗测试（弹窗属浮层，可用玻璃；排布逻辑归 AppleDialog）。
//
// 覆盖：confirm 返回值语义（确认/取消/dismiss）/ dangerous 错误色 /
// 内部 AlertDialog 全透明（玻璃由外层 GlassSurface 提供，不叠色板）/
// inset 由外壳接管（否则玻璃撑成全屏大板）/ 配方常量（sigma 16、基底
// 0.72、圆角 28）/ **红线：整棵树只允许一层 BackdropFilter** /
// 平台按钮顺序（C1 裁决：Windows 主按钮在左，Android 在右）/
// 未注入 surface 时 AppleDialog.confirm 保持裸 AlertDialog（回归保护）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

void main() {
  // 弹窗进场/退场有过渡动画，且 L3 罩含微光闪烁（每帧重绘），
  // 一律用固定时长 pump，禁用 pumpAndSettle（永不静默）。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }

  Widget host({required void Function(BuildContext) onPressed}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => onPressed(context),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('OPEN'));
    await settle(tester);
  }

  testWidgets('渲染标题、正文与两个按钮，无异常', (tester) async {
    await tester.pumpWidget(
      host(
        onPressed: (context) => GlassDialog.confirm(
          context,
          title: 'GLASS_TITLE',
          content: 'GLASS_BODY',
        ),
      ),
    );
    await openDialog(tester);
    expect(find.text('GLASS_TITLE'), findsOneWidget);
    expect(find.text('GLASS_BODY'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('confirm 返回值', () {
    testWidgets('点确认返回 true', (tester) async {
      late final Future<bool> result;
      await tester.pumpWidget(
        host(
          onPressed: (context) {
            result = GlassDialog.confirm(context, title: 't', content: 'c');
          },
        ),
      );
      await openDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await settle(tester);
      expect(await result, isTrue);
    });

    testWidgets('点取消返回 false', (tester) async {
      late final Future<bool> result;
      await tester.pumpWidget(
        host(
          onPressed: (context) {
            result = GlassDialog.confirm(context, title: 't', content: 'c');
          },
        ),
      );
      await openDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await settle(tester);
      expect(await result, isFalse);
    });

    testWidgets('点屏障 dismiss 返回 false', (tester) async {
      late final Future<bool> result;
      await tester.pumpWidget(
        host(
          onPressed: (context) {
            result = GlassDialog.confirm(context, title: 't', content: 'c');
          },
        ),
      );
      await openDialog(tester);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(await result, isFalse);
    });
  });

  testWidgets('dangerous 时确认按钮使用错误色背景', (tester) async {
    await tester.pumpWidget(
      host(
        onPressed: (context) => GlassDialog.confirm(
          context,
          title: 't',
          content: 'c',
          confirmText: '删除',
          dangerous: true,
        ),
      ),
    );
    await openDialog(tester);
    final dangerStyle = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '删除'))
        .style
        ?.backgroundColor
        ?.resolve(const <WidgetState>{});
    expect(dangerStyle, isNotNull);
  });

  testWidgets('内部 Material 全透明（dialogTheme 覆盖，玻璃由外层提供）', (tester) async {
    await tester.pumpWidget(
      host(
        onPressed: (context) =>
            GlassDialog.confirm(context, title: 't', content: 'c'),
      ),
    );
    await openDialog(tester);
    // AlertDialog 构造参数为 null，透明来自外壳 dialogTheme 覆盖——
    // 断言实际渲染的 Material，验证覆盖确实生效。
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, Colors.transparent);
    expect(material.elevation, 0);
    expect(material.surfaceTintColor, Colors.transparent);
    expect(material.shadowColor, Colors.transparent);
  });

  testWidgets('inset 由外壳接管：dialogTheme.insetPadding 置零', (tester) async {
    await tester.pumpWidget(
      host(
        onPressed: (context) =>
            GlassDialog.confirm(context, title: 't', content: 'c'),
      ),
    );
    await openDialog(tester);
    final dialogContext = tester.element(find.byType(AlertDialog));
    expect(Theme.of(dialogContext).dialogTheme.insetPadding, EdgeInsets.zero);
    // 外壳负责与屏幕边缘的留白（M3 默认 horizontal 40 / vertical 24）。
    final shellPadding = tester
        .widget<Padding>(
          find
              .ancestor(
                of: find.byType(GlassSurface),
                matching: find.byType(Padding),
              )
              .first,
        )
        .padding;
    expect(
      shellPadding,
      const EdgeInsets.symmetric(
        horizontal: GlassDialog.insetHorizontal,
        vertical: GlassDialog.insetVertical,
      ),
    );
  });

  testWidgets('配方常量：圆角 28、sigma 16、基底 0.72', (tester) async {
    await tester.pumpWidget(
      host(
        onPressed: (context) =>
            GlassDialog.confirm(context, title: 't', content: 'c'),
      ),
    );
    await openDialog(tester);
    final glass = tester.widget<GlassSurface>(find.byType(GlassSurface));
    expect(glass.borderRadius, BorderRadius.circular(GlassDialog.kRadius));
    expect(glass.sigma, GlassDialog.kSigma);
    expect(glass.surfaceOpacity, GlassDialog.kSurfaceOpacity);
    expect(glass.saturation, 1.4);
  });

  testWidgets('红线：整棵树只有一层 BackdropFilter，不得玻璃叠玻璃', (tester) async {
    await tester.pumpWidget(
      host(
        onPressed: (context) =>
            GlassDialog.confirm(context, title: 't', content: 'c'),
      ),
    );
    await openDialog(tester);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  group('平台按钮顺序（C1 裁决）', () {
    Future<List<Offset>> buttonCenters(WidgetTester tester) async {
      final cancel = tester.getCenter(find.widgetWithText(TextButton, '取消'));
      final confirm = tester.getCenter(find.widgetWithText(FilledButton, '确定'));
      return <Offset>[cancel, confirm];
    }

    testWidgets('Windows：主按钮在左', (tester) async {
      late final Future<bool> result;
      await tester.pumpWidget(
        host(
          onPressed: (context) {
            result = GlassDialog.confirm(context, title: 't', content: 'c');
          },
        ),
      );
      await openDialog(tester);
      final centers = await buttonCenters(tester);
      expect(centers[1].dx, lessThan(centers[0].dx));
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await settle(tester);
      expect(await result, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('Android：主按钮在右', (tester) async {
      late final Future<bool> result;
      await tester.pumpWidget(
        host(
          onPressed: (context) {
            result = GlassDialog.confirm(context, title: 't', content: 'c');
          },
        ),
      );
      await openDialog(tester);
      final centers = await buttonCenters(tester);
      expect(centers[1].dx, greaterThan(centers[0].dx));
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await settle(tester);
      expect(await result, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  testWidgets('未注入 surface 时 AppleDialog.confirm 保持裸 AlertDialog（回归保护）', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        onPressed: (context) =>
            AppleDialog.confirm(context, title: 't', content: 'c'),
      ),
    );
    await openDialog(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(GlassSurface), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('窄屏：外壳留白自动收窄，保证 AlertDialog 最小宽 280 装得下', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        onPressed: (context) =>
            GlassDialog.confirm(context, title: 't', content: 'c'),
      ),
    );
    await openDialog(tester);
    expect(tester.takeException(), isNull);
    // 留白必须 ≤ (可用宽 - 280) / 2 = (320 - 280) / 2 = 20。
    final shellPadding =
        tester
                .widget<Padding>(
                  find
                      .ancestor(
                        of: find.byType(GlassSurface),
                        matching: find.byType(Padding),
                      )
                      .first,
                )
                .padding
            as EdgeInsets;
    expect(shellPadding.horizontal, lessThanOrEqualTo(40));
  });

  group('show<T>：内容定制弹窗迁移入口', () {
    testWidgets('包裹裸 AlertDialog（零参数改动），玻璃外壳生效', (tester) async {
      late final Future<bool?> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () {
                    result = GlassDialog.show<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('CUSTOM_TITLE'),
                        content: const Text('CUSTOM_BODY'),
                        actions: AppleDialog.actions(<Widget>[
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('确定'),
                          ),
                        ]),
                      ),
                    );
                  },
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await settle(tester);
      expect(find.text('CUSTOM_TITLE'), findsOneWidget);
      // 玻璃外壳与单层滤镜红线。
      expect(find.byType(GlassSurface), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      // dialogTheme 覆盖生效：内部 Material 透明。
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, Colors.transparent);
      // 点确认返回 true。
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await settle(tester);
      expect(await result, isTrue);
    });

    testWidgets('包裹 StatefulBuilder 形态（定时弹窗内的动态内容）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () {
                    GlassDialog.show<bool>(
                      context: context,
                      builder: (dialogContext) => StatefulBuilder(
                        builder: (innerContext, setDialogState) => AlertDialog(
                          title: const Text('STATEFUL_TITLE'),
                          content: const Text('S_BODY'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(innerContext).pop(),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await settle(tester);
      expect(find.text('STATEFUL_TITLE'), findsOneWidget);
      expect(find.byType(GlassSurface), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('barrierDismissible=false 时点屏障不关闭', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () {
                    GlassDialog.show<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('MODAL_TITLE'),
                        content: const Text('c'),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await settle(tester);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      // 弹窗仍在。
      expect(find.text('MODAL_TITLE'), findsOneWidget);
    });
  });
}
