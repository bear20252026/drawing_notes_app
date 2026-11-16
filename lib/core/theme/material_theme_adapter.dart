import 'package:flutter/material.dart';

import 'app_theme_spec.dart';
import 'apple_design.dart';
import 'apple_elevation.dart';
import 'apple_motion.dart';
// 注意：**不得 import app_design.dart**——app_design → 本文件 → app_design
// 即循环依赖（架构规则 2 判红）。pagePadding 已收编进 AppThemeSpec。

// 主题适配层（迁移评估步骤 2，2026-11-16）：内部主题模型 → Flutter
// Material 主题的**唯一转换点**。
//
// 接缝设计：`AppThemeSpec`（app_theme_spec.dart，零 Material 依赖）承载
// 全部配色/结构决策；本文件只做「模型 → Flutter ThemeData/ColorScheme」
// 的装配语法。将来若切换 material_ui（平行 Material 实现），新增一个
// 平行适配器消费同一 AppThemeSpec 即可，色板与决策零改动。
//
// **构造唯一落点（门禁钉死）**：lib/ 内 `ThemeData(` 与 `ColorScheme(`
// 的应用级构造只准出现在本文件（局部覆写如 SliderThemeData/局部
// DialogThemeData 不在此列——它们不是应用主题构造）。见
// test/architecture/theme_adapter_seam_test.dart。
//
// 行为契约：产出与重构前 app_design._theme 逐字段等价——黄金基线
// test/core/theme/theme_adapter_equivalence_test.dart 钉死（四档全覆盖）。
abstract final class MaterialThemeAdapter {
  /// 内部模型 → Material ColorScheme（按槽位名直映，无语义翻译）。
  static ColorScheme colorSchemeOf(AppColorSpec c) => ColorScheme(
    brightness: c.brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryContainer,
    onPrimaryContainer: c.onPrimaryContainer,
    secondary: c.secondary,
    onSecondary: c.onSecondary,
    secondaryContainer: c.secondaryContainer,
    onSecondaryContainer: c.onSecondaryContainer,
    tertiary: c.tertiary,
    onTertiary: c.onTertiary,
    tertiaryContainer: c.tertiaryContainer,
    onTertiaryContainer: c.onTertiaryContainer,
    error: c.error,
    onError: c.onError,
    errorContainer: c.errorContainer,
    onErrorContainer: c.onErrorContainer,
    surface: c.surface,
    onSurface: c.onSurface,
    surfaceContainerHighest: c.surfaceContainerHighest,
    onSurfaceVariant: c.onSurfaceVariant,
    outline: c.outline,
    outlineVariant: c.outlineVariant,
    shadow: c.shadow,
    scrim: c.scrim,
    inverseSurface: c.inverseSurface,
    onInverseSurface: c.onInverseSurface,
    inversePrimary: c.inversePrimary,
    surfaceTint: c.surfaceTint,
  );

  /// 内部模型 → 应用 ThemeData（装配语法与重构前 app_design._theme
  /// 逐条一致；决策值一律取自 spec，不在本文件自造配色/结构数值）。
  static ThemeData themeOf(AppThemeSpec spec) {
    final colorScheme = colorSchemeOf(spec.colors);
    final brightness = spec.colors.brightness;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: spec.canvas,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // 焦点环底色：与 AppleFocus 的 2px 描边共存（底色 12% + 描边 2px）。
      focusColor: spec.focusColor,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: spec.canvas,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: AppThemeSpec.pagePadding,
        toolbarHeight: 60,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spec.cardRadius),
          // 发丝线（DESIGN.md:395「1px rgba(0,0,0,0.08)」）。
          side: BorderSide(color: spec.hairlineColor),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        // 同一条发丝线：列表/侧栏分隔与卡片边界共用一套语言。
        color: spec.hairlineColor,
        thickness: spec.hairlineWidth,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: spec.subtleSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(spec.controlRadius),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(spec.controlRadius),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(spec.controlRadius),
          // 2px Focus Blue（DESIGN.md:300）。
          borderSide: BorderSide(
            color: spec.focusColor,
            width: spec.focusWidth,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: const Size(AppleTouch.minTarget, AppleTouch.minTarget),
              textStyle: base.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              // C8：M3 状态层（hover 8% / focus 12% / pressed 12%）。
              overlayColor: AppleStateLayer.overlay(colorScheme.onSurface),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(AppleTouch.minTarget, AppleTouch.minTarget),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              side: BorderSide(color: colorScheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(spec.controlRadius),
              ),
            ).copyWith(
              overlayColor: AppleStateLayer.overlay(colorScheme.onSurface),
            ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style:
            IconButton.styleFrom(
              minimumSize: const Size(AppleTouch.minTarget, AppleTouch.minTarget),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppleRadius.md),
              ),
            ).copyWith(
              overlayColor: AppleStateLayer.overlay(colorScheme.onSurface),
            ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: colorScheme.onPrimaryContainer,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: base.textTheme.labelLarge,
        indicator: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppleRadius.md),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppleRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        // 唯一那条真阴影（DESIGN.md:395）——只给模态用。
        elevation: AppleElevation.overlayLevel,
        shadowColor: AppleElevation.overlayColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spec.cardRadius),
        ),
        // 排版梯子：标题 17px/w600/-0.35；正文 15px/w400/行高 1.47。
        titleTextStyle: AppleType.titleStyle(colorScheme.onSurface),
        contentTextStyle: AppleType.bodyStyle(
          colorScheme.onSurfaceVariant,
        ).copyWith(fontSize: AppleType.dialogBody),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppleSpacing.lg,
          0,
          AppleSpacing.lg,
          AppleSpacing.md,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: AppleMotion.tooltipDelay,
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
      // M-06 豁免裁决：路由转场维持平台惯例域（Material 各平台默认 M3
      // zoom），显式钉住防 Flutter 版本变更回落——详见原 app_design 注释。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}