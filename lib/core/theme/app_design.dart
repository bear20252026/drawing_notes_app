import 'package:material_ui/material_ui.dart';

/// 应用统一设计语言 —— Apple (HIG) 风格。
///
/// 目标：以内容优先、低噪声表面层级、克制的单一强调色（Action Blue）、
/// 胶囊按钮与圆角卡片，构建 Apple 风格创作工作区。颜色与排版取向
/// 参照 DESIGN.md（getdesign@apple）给出的 token；结构常量
/// (pagePadding/cardRadius/controlRadius/quickMotion/standardMotion)
/// 保持稳定以兼容既有调用方与测试。
abstract final class AppDesign {
  // ---- Apple token：颜色 ----
  static const Color ink = Color(0xFF1D1D1F); // Apple 主体墨色
  static const Color accent = Color(0xFF0066CC); // Action Blue
  static const Color accentOnDark = Color(0xFF2997FF); // 深色下的高亮蓝
  static const Color lightCanvas = Color(0xFFF5F5F7); // 米白底 (parchment)
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSubtleSurface = Color(0xFFEBEBED); // 输入/芯片底
  static const Color darkCanvas = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1D1D1F);
  static const Color darkSubtleSurface = Color(0xFF2C2C2E);

  // ---- 结构常量（保持稳定，兼容既有测试/调用） ----
  static const double pagePadding = 20;
  static const double compactPagePadding = 12;
  static const double cardRadius = 18; // Apple lg ≈ 18
  static const double controlRadius = 12; // Apple md ≈ 12
  static const double pillRadius = 9999; // 胶囊（Apple pill）
  static const Duration quickMotion = Duration(milliseconds: 140);
  static const Duration standardMotion = Duration(milliseconds: 200);

  static ThemeData lightTheme() => _theme(Brightness.light);
  static ThemeData darkTheme() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final ColorScheme colorScheme = ColorScheme(
      brightness: brightness,
      // 主强调色：Action Blue
      primary: isDark ? accentOnDark : accent,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF0A2A4A)
          : const Color(0xFFE8F1FF),
      onPrimaryContainer: isDark
          ? const Color(0xFFA7CDFF)
          : const Color(0xFF002C5C),
      // 次级（次要文字/控件）
      secondary: isDark ? const Color(0xFFA1A1A6) : const Color(0xFF6E6E73),
      onSecondary: isDark ? const Color(0xFF1D1D1F) : Colors.white,
      secondaryContainer: isDark
          ? const Color(0xFF2C2C2E)
          : const Color(0xFFF0F0F0),
      onSecondaryContainer:
          isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1D1D1F),
      // 强调绿（Apple 系统绿）
      tertiary: isDark ? const Color(0xFF30D158) : const Color(0xFF28B452),
      onTertiary: Colors.white,
      tertiaryContainer:
          isDark ? const Color(0xFF1E3F2A) : const Color(0xFFE3F5E9),
      onTertiaryContainer:
          isDark ? const Color(0xFFB9E8C6) : const Color(0xFF0A3B1C),
      // 错误：Apple 红
      error: isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30),
      onError: Colors.white,
      errorContainer:
          isDark ? const Color(0xFF5A1A16) : const Color(0xFFFFE5E3),
      onErrorContainer: isDark ? const Color(0xFFFFB4AC) : const Color(0xFF6E0B05),
      // 表面
      surface: isDark ? darkSurface : lightSurface,
      onSurface: isDark ? const Color(0xFFF5F5F7) : ink,
      surfaceContainerHighest: isDark
          ? const Color(0xFF2C2C2E)
          : const Color(0xFFEBEBED),
      onSurfaceVariant: isDark ? const Color(0xFF98989F) : const Color(0xFF6E6E73),
      outline: isDark ? const Color(0xFF6E6E73) : const Color(0xFFA1A1A6),
      outlineVariant: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE0E0E0),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F),
      onInverseSurface: isDark ? const Color(0xFF1D1D1F) : const Color(0xFFF5F5F7),
      inversePrimary: isDark ? accent : accentOnDark,
      surfaceTint: isDark ? accentOnDark : accent,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? darkCanvas : lightCanvas,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? darkCanvas : lightCanvas,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: pagePadding,
        toolbarHeight: 60,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.35, // Apple SF 标题负字距
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.9),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? darkSubtleSurface : lightSubtleSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelColor: colorScheme.onSurface,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: base.textTheme.labelLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
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
