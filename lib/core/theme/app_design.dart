import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

/// 应用统一设计语言。
///
/// 目标不是模仿任何平台的专有控件，而是以内容优先、低噪声表面层级、
/// 稳定间距和可访问触控尺寸构建克制而有质感的创作工作区。
abstract final class AppDesign {
  static const Color ink = Color(0xFF172033);
  static const Color accent = Color(0xFF4568A9);
  static const Color lightCanvas = Color(0xFFF6F7FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSubtleSurface = Color(0xFFEFF1F6);
  static const Color darkCanvas = Color(0xFF101521);
  static const Color darkSurface = Color(0xFF181F2E);
  static const Color darkSubtleSurface = Color(0xFF222B3D);

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
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? const Color(0xFFB5CCFF) : accent,
      onPrimary: isDark ? const Color(0xFF102244) : Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF294579)
          : const Color(0xFFDCE8FF),
      onPrimaryContainer: isDark
          ? const Color(0xFFDCE8FF)
          : const Color(0xFF152C57),
      secondary: isDark ? const Color(0xFFBFC7DC) : const Color(0xFF59647A),
      onSecondary: isDark ? const Color(0xFF252B3A) : Colors.white,
      secondaryContainer: isDark
          ? const Color(0xFF3A4355)
          : const Color(0xFFE6EAF2),
      onSecondaryContainer: isDark
          ? const Color(0xFFE2E8F6)
          : const Color(0xFF242B3A),
      tertiary: isDark ? const Color(0xFF93D9C4) : const Color(0xFF166C59),
      onTertiary: isDark ? const Color(0xFF04382E) : Colors.white,
      tertiaryContainer: isDark
          ? const Color(0xFF1E5145)
          : const Color(0xFFD5F2E8),
      onTertiaryContainer: isDark
          ? const Color(0xFFC4F5E6)
          : const Color(0xFF00382E),
      error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
      onError: isDark ? const Color(0xFF690005) : Colors.white,
      errorContainer: isDark
          ? const Color(0xFF93000A)
          : const Color(0xFFFFDAD6),
      onErrorContainer: isDark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF410002),
      surface: isDark ? darkSurface : lightSurface,
      onSurface: isDark ? const Color(0xFFE2E8F4) : ink,
      surfaceContainerHighest: isDark
          ? const Color(0xFF343D50)
          : const Color(0xFFE0E4EC),
      onSurfaceVariant: isDark
          ? const Color(0xFFC3CBDD)
          : const Color(0xFF596176),
      outline: isDark ? const Color(0xFF8D97AA) : const Color(0xFF747D90),
      outlineVariant: isDark
          ? const Color(0xFF3F485B)
          : const Color(0xFFC4C9D4),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark
          ? const Color(0xFFE2E8F4)
          : const Color(0xFF2C3445),
      onInverseSurface: isDark
          ? const Color(0xFF2C3445)
          : const Color(0xFFF0F4FC),
      inversePrimary: isDark ? accent : const Color(0xFFB5CCFF),
      surfaceTint: isDark ? const Color(0xFFB5CCFF) : accent,
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
          fontWeight: FontWeight.w700,
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
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
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
          fontWeight: FontWeight.w700,
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
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
