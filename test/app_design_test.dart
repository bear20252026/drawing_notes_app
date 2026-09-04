import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDesign', () {
    test(
      'light theme provides content-first surfaces and accessible controls',
      () {
        final theme = AppDesign.lightTheme();

        expect(theme.useMaterial3, isTrue);
        expect(theme.scaffoldBackgroundColor, AppDesign.lightCanvas);
        expect(theme.cardTheme.elevation, 0);
        expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
        expect(
          theme.filledButtonTheme.style?.minimumSize?.resolve({}),
          const Size(44, 44),
        );
        expect(
          theme.iconButtonTheme.style?.minimumSize?.resolve({}),
          const Size(44, 44),
        );
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.tabBarTheme.dividerColor, Colors.transparent);
      },
    );

    test('dark theme uses a distinct canvas and keeps semantic surfaces', () {
      final light = AppDesign.lightTheme();
      final dark = AppDesign.darkTheme();

      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, AppDesign.darkCanvas);
      expect(dark.colorScheme.surface, AppDesign.darkSurface);
      expect(dark.colorScheme.primary, isNot(light.colorScheme.primary));
      expect(dark.inputDecorationTheme.filled, isTrue);
    });

    test('motion and layout tokens stay intentionally compact', () {
      expect(AppDesign.quickMotion, const Duration(milliseconds: 140));
      expect(AppDesign.standardMotion, const Duration(milliseconds: 200));
      expect(AppDesign.pagePadding, 20);
      expect(AppDesign.cardRadius, 18);
      // 12 → 11（AppleRadius.md）：DESIGN.md:511 明令「Don't mix radii
      // grammars」，刻度只有 xs5/sm8/md11/lg18/pill，12 是凭空造的中间值。
      expect(AppDesign.controlRadius, AppleRadius.md);
    });

    test('圆角令牌严格对齐 DESIGN.md:420-427 刻度', () {
      expect(AppDesign.cardRadius, AppleRadius.lg); // 18
      expect(AppDesign.controlRadius, AppleRadius.md); // 11
    });
  });
}
