import 'package:material_ui/material_ui.dart';

/// 应用统一设计语言。
///
/// 目标不是模仿任何平台的专有控件，而是以内容优先、低噪声表面层级、
/// 稳定间距和可访问触控尺寸构建克制而有质感的创作工作区。
///
/// 颜色策略（用户@要求保留深蓝色系）：
///   - 明亮模式 = Apple（苹果）配色：Action Blue `#0066CC`、米白底 `#F5F5F7`、墨色 `#1D1D1F`。
///   - 黑暗模式 = 既有深蓝（navy）配色：`#172033` / `#4568A9` / `#101521` / `#181F2E` / `#222B3D`。
///   - 结构风格（圆角 / 间距 / 字重 / 动效 / 胶囊 / 过渡）= 统一为 Apple 风格，两种模式一致。
abstract final class AppDesign {
  // ---- 深蓝（黑暗模式）核心色板：保留 ----
  static const Color navyInk = Color(0xFF172033);
  static const Color navyAccent = Color(0xFF4568A9);
  static const Color darkCanvas = Color(0xFF101521);
  static const Color darkSurface = Color(0xFF181F2E);
  static const Color darkSubtleSurface = Color(0xFF222B3D);

  // ---- Apple（明亮模式）核心色板 ----
  static const Color ink = Color(0xFF1D1D1F); // Apple 主体墨色
  static const Color accent = Color(0xFF0066CC); // Action Blue
  static const Color lightCanvas = Color(0xFFF5F5F7); // 米白底 (parchment)
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSubtleSurface = Color(0xFFF2F2F7); // systemGray6

  // ---- Apple 结构风格（两种模式一致）----
  static const double pagePadding = 20;
  static const double compactPagePadding = 12;
  static const double cardRadius = 18;
  static const double controlRadius = 12;
  static const Duration quickMotion = Duration(milliseconds: 140);
  static const Duration standardMotion = Duration(milliseconds: 200);

  static ThemeData lightTheme() => _theme(Brightness.light);
  static ThemeData darkTheme() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // 颜色随模式切换：明亮=Apple，黑暗=深蓝。
    final colorScheme = isDark ? _navyScheme() : _appleLightScheme();

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
          letterSpacing: -0.25,
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
            color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.75),
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
          borderRadius: BorderRadius.circular(10),
        ),
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

  /// Apple 明亮模式 ColorScheme。
  static ColorScheme _appleLightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF0066CC), // Action Blue
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDCE9FF),
      onPrimaryContainer: Color(0xFF0A2540),
      secondary: Color(0xFF6E6E73),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE9E9EB),
      onSecondaryContainer: Color(0xFF2C2C2E),
      tertiary: Color(0xFF30D158),
      onTertiary: Color(0xFF0B3D1E),
      tertiaryContainer: Color(0xFFD6F5DE),
      onTertiaryContainer: Color(0xFF0B3D1E),
      error: Color(0xFFFF3B30),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF6B1B14),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1D1D1F),
      surfaceContainerHighest: Color(0xFFEDEDEF),
      onSurfaceVariant: Color(0xFF6E6E73),
      outline: Color(0xFF86868B),
      outlineVariant: Color(0xFFD2D2D7),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFF2C2C2E),
      onInverseSurface: Color(0xFFF5F5F7),
      inversePrimary: Color(0xFF0066CC),
      surfaceTint: Color(0xFF0066CC),
    );
  }

  /// 深蓝（navy）黑暗模式 ColorScheme —— 保留既有应用身份。
  static ColorScheme _navyScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFB5CCFF),
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
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFE2E8F4),
      onInverseSurface: Color(0xFF2C3445),
      inversePrimary: Color(0xFF4568A9),
      surfaceTint: Color(0xFFB5CCFF),
    );
  }
}
