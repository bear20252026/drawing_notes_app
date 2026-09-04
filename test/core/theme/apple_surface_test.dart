// 表面层级（发丝线 / 海拔）与焦点环令牌测试（2026-09-04）。
//
// 数值权威：`DESIGN.md`（根目录）——
// - :395「Soft hairline | 1px rgba(0,0,0,0.08) border」
// - :402「Apple uses exactly one drop-shadow … never to cards, never to
//   buttons, never to text」
// - :395「Product shadow | rgba(0, 0, 0, 0.22) 3px 5px 30px 0」
// - :300「(Focus Blue) is reserved for the keyboard focus ring on buttons
//   (`outline: 2px solid`)」
//
// 钉住这些数值的理由：发丝线现在被 `CardTheme` / `DividerTheme` 统一使用，
// 一旦透明度漂移，全 App 的卡片边界会一起变重或变没，且很难一眼定位。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/theme/apple_elevation.dart';
import 'package:drawing_notes_app/core/theme/apple_focus.dart';

void main() {
  group('AppleHairline', () {
    test('亮色 = 8% 黑（DESIGN.md:395 明文）', () {
      final c = AppleHairline.colorFor(Brightness.light);
      expect(c, Colors.black.withValues(alpha: 0.08));
    });

    test('深色 = 12% 白（深底上的等效亮度差）', () {
      final c = AppleHairline.colorFor(Brightness.dark);
      expect(c, Colors.white.withValues(alpha: 0.12));
    });

    test('线宽恒为 1', () {
      expect(AppleHairline.width, 1);
    });

    test('主题层注入的 CardTheme 用的就是发丝线', () {
      final theme = AppDesign.lightTheme();
      final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(
        shape.side.color,
        AppleHairline.colorFor(Brightness.light),
        reason: '卡片此前用 outlineVariant（≈18% 灰），比规范重一倍',
      );
      expect(shape.side.width, AppleHairline.width);
    });

    test('DividerTheme 与卡片边界共用同一条发丝线', () {
      final theme = AppDesign.lightTheme();
      expect(
        theme.dividerTheme.color,
        AppleHairline.colorFor(Brightness.light),
      );
      expect(theme.dividerTheme.thickness, AppleHairline.width);
    });
  });

  group('AppleElevation', () {
    test('flat（内容层）无阴影 —— 卡片/按钮/文字一律不加（DESIGN.md:502）', () {
      expect(AppleElevation.flat, isEmpty);
    });

    test('overlay 就是系统里唯一那条真阴影', () {
      expect(AppleElevation.overlay, hasLength(1));
      final s = AppleElevation.overlay.single;
      expect(s.color, const Color(0x38000000)); // 22%
      expect(s.blurRadius, 30);
      expect(s.offset, const Offset(3, 5));
    });

    test('raised 比 overlay 浅（浮层不该用模态级阴影）', () {
      final raised = AppleElevation.raised.single;
      final overlay = AppleElevation.overlay.single;
      expect(raised.color.a, lessThan(overlay.color.a));
      expect(raised.blurRadius, lessThan(overlay.blurRadius));
    });

    test('对话框走 overlay 档', () {
      final theme = AppDesign.lightTheme();
      expect(theme.dialogTheme.elevation, AppleElevation.overlayLevel);
      expect(theme.dialogTheme.shadowColor, AppleElevation.overlayColor);
    });
  });

  group('AppleFocus', () {
    test('描边 2px + Focus Blue（DESIGN.md:300 / :8）', () {
      expect(AppleFocus.width, 2);
      expect(AppleFocus.color, const Color(0xFF0071E3));
      expect(AppleFocus.colorFor(Brightness.light), AppleColor.focusBlue);
    });

    test(
      'Focus Blue 与 AppleColor 保持同值（apple_focus 不得 import '
      'apple_design，靠本断言守住单一事实来源）',
      () {
        expect(AppleFocus.color, AppleColor.focusBlue);
        expect(AppleFocus.colorFor(Brightness.dark), AppleColor.actionBlueOnDark);
      },
    );

    test('深色模式换更亮的一档', () {
      expect(
        AppleFocus.colorFor(Brightness.dark),
        AppleColor.actionBlueOnDark,
      );
    });

    test('输入框聚焦边框 = 2px Focus Blue（此前是 1.5px primary）', () {
      final theme = AppDesign.lightTheme();
      final focused = theme.inputDecorationTheme.focusedBorder!
          as OutlineInputBorder;
      expect(focused.borderSide.width, AppleFocus.width);
      expect(focused.borderSide.color, AppleFocus.colorFor(Brightness.light));
    });
  });

  group('AppleFocusRing 行为', () {
    BoxBorder? ringOf(WidgetTester tester) {
      final box = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      for (final b in box) {
        final d = b.decoration;
        if (d is BoxDecoration && d.border != null) return d.border;
      }
      return null;
    }

    testWidgets('未聚焦时不画环', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.lightTheme(),
          home: Scaffold(
            body: AppleFocusRing(
              borderRadius: AppleRadius.md,
              child: SizedBox(
                width: 120,
                height: 44,
                child: TextButton(
                  focusNode: node,
                  onPressed: () {},
                  child: const Text('A'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(ringOf(tester), isNull);
    });

    testWidgets('聚焦后出现 2px Focus Blue 环', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.lightTheme(),
          home: Scaffold(
            body: AppleFocusRing(
              borderRadius: AppleRadius.md,
              child: SizedBox(
                width: 120,
                height: 44,
                child: TextButton(
                  focusNode: node,
                  onPressed: () {},
                  child: const Text('A'),
                ),
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pumpAndSettle();

      final ring = ringOf(tester);
      expect(ring, isNotNull);
      expect(ring!.top.width, AppleFocus.width);
      expect(ring.top.color, AppleColor.focusBlue);
    });

    testWidgets('enabled=false 时即使聚焦也不画环', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.lightTheme(),
          home: Scaffold(
            body: AppleFocusRing(
              enabled: false,
              child: SizedBox(
                width: 120,
                height: 44,
                child: TextButton(
                  focusNode: node,
                  onPressed: () {},
                  child: const Text('A'),
                ),
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(ringOf(tester), isNull);
    });
  });
}
