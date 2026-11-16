import 'dart:ui' show Brightness, Color;

// 主题适配层（迁移评估步骤 2，2026-11-16）：内部主题模型 + 色板数据。
//
// **依赖纪律（本文件的存在意义）**：只准 import `dart:ui`——不 import
// material/widgets/cupertino 任何 UI 框架库。`Color`/`Brightness` 是引擎
// 层类型，不随 Material 实现更换而变；`ColorScheme`/`ThemeData`/
// `WidgetStateProperty` 是 Material 类型，一律不得出现在本文件。
// 由此内部主题模型与具体 Material 实现解耦：将来若切换 material_ui
// （平行 Material 实现，两套 ThemeData 类型不兼容——见
// docs/MATERIAL_UI_MIGRATION_ASSESSMENT.md），只需新增一个适配器把本
// 模型转成目标框架的主题类型，色板/结构决策零改动。
//
// 门禁：test/architecture/theme_adapter_seam_test.dart 钉死本纪律与
// 「ThemeData/ColorScheme 构造唯一落点 = material_theme_adapter.dart」。
//
// 结构决策（明暗 × 对比度四档、发丝线/焦点/圆角取值）在本文件；
// Material 装配语法（AppBarTheme/CardThemeData/…）在适配器。

/// 主题亮度档（内部枚举——不依赖 Material 的 Brightness 语义约定，
/// 但值直接用 dart:ui Brightness，避免无谓的双枚举转换）。
typedef SpecBrightness = Brightness;

/// 对比度档（内部布尔口径——与 AppleContrast 枚举解耦：本模型不 import
/// apple_contrast.dart，保持零框架依赖；调用方负责枚举→布尔映射）。
typedef SpecHighContrast = bool;

/// 内部语义色板（28 槽——与 M3 ColorScheme 的槽位一一对应，但**只是
/// 数据**：纯 const 构造，无任何 Material 类型）。
///
/// 槽位语义沿用 M3 命名（primary/onPrimary/…）是刻意的：适配器按名
/// 直映，不引入第二套语义翻译表；将来目标框架若有同名语义槽同样直映。
class AppColorSpec {
  const AppColorSpec({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.surfaceContainerHighest,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.shadow,
    required this.scrim,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    required this.surfaceTint,
  });

  final SpecBrightness brightness;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color surface;
  final Color onSurface;
  final Color surfaceContainerHighest;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color shadow;
  final Color scrim;
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color inversePrimary;
  final Color surfaceTint;
}

/// 应用主题规格（内部模型的根）：一档主题 = 色板 + 结构标量。
///
/// 结构标量只收「随档位变化的决策」；恒定结构令牌（圆角刻度/间距/
/// 触控尺寸/动效时长）仍归 Apple* 令牌类（它们本就是纯数据，适配器
/// 直接引用，不在本模型重复一份——单一事实来源）。
class AppThemeSpec {
  const AppThemeSpec({
    required this.colors,
    required this.canvas,
    required this.subtleSurface,
    required this.focusColor,
    required this.hairlineColor,
    required this.hairlineWidth,
    required this.focusWidth,
    required this.cardRadius,
    required this.controlRadius,
  });

  final AppColorSpec colors;

  /// 画布底色（scaffold/appBar 背景）。
  final Color canvas;

  /// 输入框填充等次级表面。
  final Color subtleSurface;

  /// 焦点环颜色（含对比度档决策）。
  final Color focusColor;

  /// 发丝线颜色（卡片边界/分隔线共用，含对比度档决策）。
  final Color hairlineColor;
  final double hairlineWidth;
  final double focusWidth;
  final double cardRadius;
  final double controlRadius;

  bool get isDark => colors.brightness == Brightness.dark;

  /// 页面水平留白（appBar titleSpacing 同源）。收编进规格层是为了斩断
  /// 适配器 → app_design 的回边（app_design → 适配器 → app_design 即循环，
  /// 架构规则 2 判红）；app_design.pagePadding 改为别名引用本常量。
  static const double pagePadding = 20;

  /// 四档主题规格的唯一决策点（明暗 × 对比度）。
  ///
  /// 色板数据与重构前 app_design.dart 的四套 ColorScheme 逐值一致
  /// （黄金基线 test/core/theme/theme_adapter_equivalence_test.dart 钉死）。
  static AppThemeSpec resolve({
    required SpecBrightness brightness,
    SpecHighContrast highContrast = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final colors = highContrast
        ? (isDark ? highContrastDarkColors : highContrastLightColors)
        : (isDark ? navyColors : appleLightColors);
    return AppThemeSpec(
      colors: colors,
      canvas: isDark ? _canvasDark : _canvasLight,
      subtleSurface: isDark ? _subtleDark : _subtleLight,
      focusColor: highContrast
          ? (isDark ? _focusHighDark : _focusHighLight)
          : (isDark ? _focusOnDark : _focusLight),
      // 发丝线：8% 黑 / 12% 白（AppleHairline 同口径）。alpha 用
      // withValues 同式计算而非手写 hex 常量——手写舍入与框架计算
      // 可能差分毫（黄金基线实测踩中），同式即逐位一致。
      hairlineColor: highContrast
          ? (isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
          : (isDark
                ? const Color(0xFFFFFFFF).withValues(alpha: 0.12)
                : const Color(0xFF000000).withValues(alpha: 0.08)),
      hairlineWidth: 1,
      focusWidth: 2,
      cardRadius: 18, // AppleRadius.lg
      controlRadius: 11, // AppleRadius.md
    );
  }

  // ---- 画布/次级表面（与 AppleColor 同值；测试钉住防分叉）----
  static const Color _canvasLight = Color(0xFFF5F5F7); // parchment
  static const Color _canvasDark = Color(0xFF101521); // canvansDark
  static const Color _subtleLight = Color(0xFFF2F2F7); // systemGray6（刻意独立灰阶）
  static const Color _subtleDark = Color(0xFF222B3D); // subtleSurfaceDark

  // ---- 焦点环（与 AppleFocus 同值；测试钉住防分叉）----
  static const Color _focusLight = Color(0xFF0071E3);
  static const Color _focusOnDark = Color(0xFF2997FF);
  static const Color _focusHighLight = Color(0xFF003D99);
  static const Color _focusHighDark = Color(0xFF99CCFF);

  /// Apple 明亮模式色板（Action Blue 族）。
  static const AppColorSpec appleLightColors = AppColorSpec(
    brightness: Brightness.light,
    primary: Color(0xFF0066CC), // Action Blue
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCE9FF),
    onPrimaryContainer: Color(0xFF0A2540),
    secondary: Color(0xFF6E6E73),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE9E9EB),
    onSecondaryContainer: Color(0xFF2C2C2E),
    tertiary: Color(0xFF30D158),
    onTertiary: Color(0xFF0B3D1E),
    tertiaryContainer: Color(0xFFD6F5DE),
    onTertiaryContainer: Color(0xFF0B3D1E),
    error: Color(0xFFFF3B30),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF6B1B14),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1D1D1F),
    surfaceContainerHighest: Color(0xFFEDEDEF),
    onSurfaceVariant: Color(0xFF6E6E73),
    outline: Color(0xFF86868B),
    outlineVariant: Color(0xFFD2D2D7),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2C2C2E),
    onInverseSurface: Color(0xFFF5F5F7),
    inversePrimary: Color(0xFF0066CC),
    surfaceTint: Color(0xFF0066CC),
  );

  /// 深蓝（navy）黑暗模式色板——保留既有应用身份。
  /// primary/surfaceTint = actionBlueOnDark #2997FF（H1 裁决）。
  static const AppColorSpec navyColors = AppColorSpec(
    brightness: Brightness.dark,
    primary: Color(0xFF2997FF),
    onPrimary: Color(0xFF102244),
    primaryContainer: Color(0xFF294579),
    onPrimaryContainer: Color(0xFFDCE8FF),
    secondary: Color(0xFFBFC7DC),
    onSecondary: Color(0xFF252B3A),
    secondaryContainer: Color(0xFF3A4355),
    onSecondaryContainer: Color(0xFFE2E8F6),
    tertiary: Color(0xFF93D9C4),
    onTertiary: Color(0xFF04382E),
    tertiaryContainer: Color(0xFF1E5145),
    onTertiaryContainer: Color(0xFFC4F5E6),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF181F2E),
    onSurface: Color(0xFFE2E8F4),
    surfaceContainerHighest: Color(0xFF343D50),
    onSurfaceVariant: Color(0xFFC3CBDD),
    outline: Color(0xFF8D97AA),
    outlineVariant: Color(0xFF3F485B),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE2E8F4),
    onInverseSurface: Color(0xFF2C3445),
    inversePrimary: Color(0xFF4568A9),
    surfaceTint: Color(0xFF2997FF),
  );

  /// Windows 高对比度（亮）：纯白底/纯黑字/边框 100% 不透明。
  /// 强调色留 Action Blue 色族（#003D99 对白 8.6:1）。
  static const AppColorSpec highContrastLightColors = AppColorSpec(
    brightness: Brightness.light,
    primary: Color(0xFF003D99),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF003D99),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFF1A1A1A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE6E6E6),
    onSecondaryContainer: Color(0xFF000000),
    tertiary: Color(0xFF004D33),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF004D33),
    onTertiaryContainer: Color(0xFFFFFFFF),
    error: Color(0xFFB00020),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFB00020),
    onErrorContainer: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF000000),
    surfaceContainerHighest: Color(0xFFE6E6E6),
    onSurfaceVariant: Color(0xFF000000),
    outline: Color(0xFF000000),
    outlineVariant: Color(0xFF000000),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF000000),
    onInverseSurface: Color(0xFFFFFFFF),
    inversePrimary: Color(0xFF99CCFF),
    surfaceTint: Color(0xFF003D99),
  );

  /// Windows 高对比度（暗）：纯黑底/纯白字（深蓝底白字不足 7:1）。
  static const AppColorSpec highContrastDarkColors = AppColorSpec(
    brightness: Brightness.dark,
    primary: Color(0xFF99CCFF),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF99CCFF),
    onPrimaryContainer: Color(0xFF000000),
    secondary: Color(0xFFFFFFFF),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF1A1A1A),
    onSecondaryContainer: Color(0xFFFFFFFF),
    tertiary: Color(0xFF7FFFD4),
    onTertiary: Color(0xFF000000),
    tertiaryContainer: Color(0xFF004D33),
    onTertiaryContainer: Color(0xFFFFFFFF),
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF000000),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFFFFF),
    surface: Color(0xFF000000),
    onSurface: Color(0xFFFFFFFF),
    surfaceContainerHighest: Color(0xFF1A1A1A),
    onSurfaceVariant: Color(0xFFFFFFFF),
    outline: Color(0xFFFFFFFF),
    outlineVariant: Color(0xFFFFFFFF),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFFFFFFF),
    onInverseSurface: Color(0xFF000000),
    inversePrimary: Color(0xFF003D99),
    surfaceTint: Color(0xFF99CCFF),
  );
}