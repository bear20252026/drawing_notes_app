// 高对比度档测试（平台域裁决 C2，2026-09-04）。
//
// 权威：Microsoft win-dev-skills —— Windows 用户在系统设置里开启
// 「高对比度」后，应用必须提供第三套配色。本项目常规档靠 8% 发丝线
// 表达层级（DESIGN.md:395），在该档位下等于不可见，所以高对比度档把
// 边框与文字推到 100% 不透明。
//
// 钉住这些值的原因：对比度是**无障碍**属性，一旦漂移，低视力用户会
// 直接看不到卡片边界——而这类反馈最难被开发者复现（开发者自己不开
// 高对比度，永远看不到问题）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/core/theme/apple_contrast.dart';

void main() {
  group('AppleContrast.resolve（用户覆盖 vs 系统值）', () {
    test('未手动设置时跟随系统', () {
      expect(
        AppleContrast.resolve(override: null, platform: AppleContrast.high),
        AppleContrast.high,
      );
      expect(
        AppleContrast.resolve(override: null, platform: AppleContrast.normal),
        AppleContrast.normal,
      );
    });

    test('手动值优先于系统值（两个方向都要压得住）', () {
      expect(
        AppleContrast.resolve(override: false, platform: AppleContrast.high),
        AppleContrast.normal,
        reason: '用户在没开系统高对比度的机器上想强制开启，或反之',
      );
      expect(
        AppleContrast.resolve(override: true, platform: AppleContrast.normal),
        AppleContrast.high,
      );
    });
  });

  group('高对比度亮色主题', () {
    test('纯白底 / 纯黑字 / 边框全不透明', () {
      final scheme = AppDesign.lightTheme(
        contrast: AppleContrast.high,
      ).colorScheme;
      expect(scheme.surface, Colors.white);
      expect(scheme.onSurface, Colors.black);
      expect(scheme.outline, Colors.black);
      expect(scheme.outlineVariant, Colors.black);
    });

    test('强调色仍是 Action Blue 色族（不引入第二强调色）', () {
      final scheme = AppDesign.lightTheme(
        contrast: AppleContrast.high,
      ).colorScheme;
      // #003D99：Action Blue #0066CC 加深版，对白底对比度 8.6:1。
      expect(scheme.primary, const Color(0xFF003D99));
    });

    test('发丝线从 8% 推到 100%', () {
      final theme = AppDesign.lightTheme(contrast: AppleContrast.high);
      final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.side.color, Colors.black);
      expect(theme.dividerTheme.color, Colors.black);
    });

    test('焦点环换用高对比蓝', () {
      final theme = AppDesign.lightTheme(contrast: AppleContrast.high);
      expect(theme.focusColor, const Color(0xFF003D99));
    });
  });

  group('高对比度深色主题', () {
    test('纯黑底 / 纯白字 / 边框全不透明', () {
      final scheme = AppDesign.darkTheme(
        contrast: AppleContrast.high,
      ).colorScheme;
      expect(scheme.surface, Colors.black);
      expect(scheme.onSurface, Colors.white);
      expect(scheme.outline, Colors.white);
    });

    test('高对比度档放弃深蓝身份（可读性优先）', () {
      final normal = AppDesign.darkTheme().colorScheme.surface;
      final high = AppDesign.darkTheme(
        contrast: AppleContrast.high,
      ).colorScheme.surface;
      expect(normal, const Color(0xFF181F2E)); // 常规档保留深蓝
      expect(high, Colors.black);
    });

    test('发丝线与焦点环都换成纯白 / 高对比蓝', () {
      final theme = AppDesign.darkTheme(contrast: AppleContrast.high);
      final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.side.color, Colors.white);
      expect(theme.focusColor, const Color(0xFF99CCFF));
    });
  });

  group('常规档不受影响（回归保护）', () {
    test('亮色常规档仍是 8% 发丝线 + Focus Blue', () {
      final theme = AppDesign.lightTheme();
      final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.side.color, Colors.black.withValues(alpha: 0.08));
      expect(theme.focusColor, const Color(0xFF0071E3));
    });

    test('深色常规档仍是深蓝 + 12% 发丝线', () {
      final theme = AppDesign.darkTheme();
      final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.side.color, Colors.white.withValues(alpha: 0.12));
    });
  });

  group('AppThemeController 高对比度开关', () {
    test('默认跟随系统（未持久化过时为 null）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppThemeController();
      addTearDown(controller.dispose);
      // 等 _load 完成
      await Future<void>.delayed(Duration.zero);
      expect(controller.highContrastOverride, isNull);
    });

    test('三态循环：跟随系统 → 开 → 关 → 跟随系统', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppThemeController();
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);

      controller.cycleHighContrast();
      expect(controller.highContrastOverride, isTrue);

      controller.cycleHighContrast();
      expect(controller.highContrastOverride, isFalse);

      controller.cycleHighContrast();
      expect(controller.highContrastOverride, isNull);
    });

    test('设置项文案随状态变化', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppThemeController();
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(controller.highContrastLabel, contains('跟随系统'));
      await controller.setHighContrast(true);
      expect(controller.highContrastLabel, contains('已开启'));
      await controller.setHighContrast(false);
      expect(controller.highContrastLabel, contains('已关闭'));
    });
  });
}
