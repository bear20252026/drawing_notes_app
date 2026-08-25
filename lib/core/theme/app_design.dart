import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

/// 应用统一设计语言 — Apple 设计风格。
///
/// 参照 Apple Human Interface Guidelines (HIG)：
/// - San Francisco 字体系统
/// - Apple 标准色彩系统（#007AFF 蓝、#FF3B30 红、#FF9500 橙、#4CD964 绿）
/// - iOS 圆角：12pt（大卡片）、8pt（按钮）、4pt（小元素）
/// - 8pt 基础网格，大量留白
/// - 阴影：0 2pt 8pt rgba(0,0,0,0.08)
/// - 大标题 + 底部标签栏
abstract final class AppDesign {
  // ─── Apple 标准色彩 ────────────────────────────────────────────
  /// Apple Blue — 主色调（链接、主操作、选中态）。
  static const Color appleBlue = Color(0xFF007AFF);
  /// Apple Red — 危险/删除操作。
  static const Color appleRed = Color(0xFFFF3B30);
  /// Apple Orange — 警告/次要强调。
  static const Color appleOrange = Color(0xFFFF9500);
  /// Apple Green — 成功/完成状态。
  static const Color appleGreen = Color(0xFF4CD964);
  /// Apple Gray — 中性文字/占位符。
  static const Color appleGray = Color(0xFF8E8E93);
  /// Apple Gray secondary — 次要中性文字。
  static const Color appleGray2 = Color(0xFFAEAEB2);
  /// Apple Teal — 信息提示。
  static const Color appleTeal = Color(0xFF5AC8FA);
  /// Apple Purple — 特殊分类。
  static const Color applePurple = Color(0xFFAF52DE);
  /// Apple Pink — 次要分类。
  static const Color applePink = Color(0xFFFF2D55);
  /// Apple Indigo — 系统紫。
  static const Color appleIndigo = Color(0xFF5856D6);

  // ─── 浅色模式表面色 ──────────────────────────────────────────
  static const Color lightSystemBackground = Color(0xFFF2F2F7);
  static const Color lightSecondarySystemBackground = Color(0xFFFFFFFF);
  static const Color lightTertiarySystemBackground = Color(0xFFF2F2F7);
  static const Color lightLabel = Color(0xFF000000);
  static const Color lightSecondaryLabel = Color(0xFF3C3C43);
  static const Color lightTertiaryLabel = Color(0xFF3C3C4399);
  static const Color lightSeparator = Color(0xFF3C3C4349);

  // ─── 深色模式表面色 ──────────────────────────────────────────
  static const Color darkSystemBackground = Color(0xFF000000);
  static const Color darkSecondarySystemBackground = Color(0xFF1C1C1E);
  static const Color darkTertiarySystemBackground = Color(0xFF2C2C2E);
  static const Color darkLabel = Color(0xFFFFFFFF);
  static const Color darkSecondaryLabel = Color(0xFFEBEBF5);
  static const Color darkTertiaryLabel = Color(0xFFEBEBF599);
  static const Color darkSeparator = Color(0xFF38383A);

  // ─── 设计常量（Apple HIG） ───────────────────────────────────
  /// 页面边距（8pt 网格）。
  static const double pagePadding = 20;
  static const double compactPagePadding = 12;
  /// 卡片圆角 — Apple 大卡片 12pt。
  static const double cardRadius = 12;
  /// 控件圆角 — Apple 按钮/输入 8pt。
  static const double controlRadius = 8;
  /// 小元素圆角（标签/徽章） 4pt。
  static const double smallRadius = 4;
  /// Apple 标准阴影。
  static const List<BoxShadow> appleShadow = [
    BoxShadow(
      color: Color(0x14000000), // rgba(0,0,0,0.08)
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
  /// Apple 大阴影（弹窗/浮层）。
  static const List<BoxShadow> appleShadowLarge = [
    BoxShadow(
      color: Color(0x29000000), // rgba(0,0,0,0.16)
      blurRadius: 24,
      offset: Offset(0, 4),
    ),
  ];
  static const Duration quickMotion = Duration(milliseconds: 140);
  static const Duration standardMotion = Duration(milliseconds: 200);

  // ─── 兼容旧引用（重定向到 Apple 色值） ────────────────────────
  /// 旧 ink → Apple 深色文字。
  static const Color ink = lightLabel;
  /// 旧 accent → Apple Blue。
  static const Color accent = appleBlue;
  /// 旧 lightCanvas → Apple 浅色背景。
  static const Color lightCanvas = lightSystemBackground;
  /// 旧 lightSurface → Apple 二级浅色背景。
  static const Color lightSurface = lightSecondarySystemBackground;
  /// 旧 lightSubtleSurface → Apple 三级浅色背景。
  static const Color lightSubtleSurface = lightTertiarySystemBackground;
  /// 旧 darkCanvas → Apple 深色背景。
  static const Color darkCanvas = darkSystemBackground;
  /// 旧 darkSurface → Apple 二级深色背景。
  static const Color darkSurface = darkSecondarySystemBackground;
  /// 旧 darkSubtleSurface → Apple 三级深色背景。
  static const Color darkSubtleSurface = darkTertiarySystemBackground;

  static ThemeData lightTheme() => _theme(Brightness.light);
  static ThemeData darkTheme() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Apple 色彩系统 — 浅色/深色模式映射。
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? const Color(0xFF0A84FF) : appleBlue,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF003A75)
          : const Color(0xFFD6E4FF),
      onPrimaryContainer: isDark
          ? const Color(0xFFD6E4FF)
          : const Color(0xFF001B3F),
      secondary: isDark ? const Color(0xFF5E5CE6) : appleIndigo,
      onSecondary: Colors.white,
      secondaryContainer: isDark
          ? const Color(0xFF3A3999)
          : const Color(0xFFE0DEF7),
      onSecondaryContainer: isDark
          ? const Color(0xFFE0DEF7)
          : const Color(0xFF1B1847),
      tertiary: isDark ? const Color(0xFF30D158) : appleGreen,
      onTertiary: Colors.white,
      tertiaryContainer: isDark
          ? const Color(0xFF004A1A)
          : const Color(0xFFC8F0D4),
      onTertiaryContainer: isDark
          ? const Color(0xFFC8F0D4)
          : const Color(0xFF002108),
      error: isDark ? const Color(0xFFFFB4AB) : appleRed,
      onError: isDark ? const Color(0xFF690005) : Colors.white,
      errorContainer: isDark
          ? const Color(0xFF93000A)
          : const Color(0xFFFFDAD6),
      onErrorContainer: isDark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF410002),
      surface: isDark ? darkSecondarySystemBackground : lightSecondarySystemBackground,
      onSurface: isDark ? darkLabel : lightLabel,
      surfaceContainerHighest: isDark
          ? const Color(0xFF48484A)
          : const Color(0xFFE5E5EA),
      onSurfaceVariant: isDark
          ? const Color(0xFFC7C7CC)
          : const Color(0xFF636366),
      outline: isDark ? const Color(0xFF636366) : const Color(0xFFC6C6C8),
      outlineVariant: isDark
          ? const Color(0xFF48484A)
          : const Color(0xFFD1D1D6),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark
          ? const Color(0xFFE5E5EA)
          : const Color(0xFF1C1C1E),
      onInverseSurface: isDark
          ? const Color(0xFF1C1C1E)
          : const Color(0xFFF2F2F7),
      inversePrimary: isDark ? const Color(0xFF0A84FF) : const Color(0xFFB3D7FF),
      surfaceTint: isDark ? const Color(0xFF0A84FF) : appleBlue,
    );

    // Apple 字体系统 — SF Pro（Flutter 系统默认字体在 Apple 平台即 SF Pro）。
    final textTheme = TextTheme(
      displayLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.37,
        color: isDark ? darkLabel : lightLabel,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.36,
        color: isDark ? darkLabel : lightLabel,
      ),
      displaySmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.35,
        color: isDark ? darkLabel : lightLabel,
      ),
      headlineLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.38,
        color: isDark ? darkLabel : lightLabel,
      ),
      headlineMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.41,
        color: isDark ? darkLabel : lightLabel,
      ),
      headlineSmall: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.24,
        color: isDark ? darkLabel : lightLabel,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.38,
        color: isDark ? darkLabel : lightLabel,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.41,
        color: isDark ? darkLabel : lightLabel,
      ),
      titleSmall: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.24,
        color: isDark ? darkLabel : lightLabel,
      ),
      bodyLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.41,
        color: isDark ? darkLabel : lightLabel,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.24,
        color: isDark ? darkLabel : lightLabel,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.08,
        color: isDark ? darkSecondaryLabel : lightSecondaryLabel,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.24,
        color: isDark ? darkLabel : lightLabel,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.08,
        color: isDark ? darkSecondaryLabel : lightSecondaryLabel,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.06,
        color: isDark ? darkTertiaryLabel : lightTertiaryLabel,
      ),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark ? darkSystemBackground : lightSystemBackground,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // Apple 风格分割线 — 细、半透明。
      dividerColor: isDark ? darkSeparator : lightSeparator,
    );

    return base.copyWith(
      // ─── AppBar — Apple 大标题风格 ──────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? darkSystemBackground : lightSystemBackground,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        titleSpacing: pagePadding,
        toolbarHeight: 56,
        // Apple 大标题 — SF Pro Display, Bold, 17pt。
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.41,
          color: isDark ? darkLabel : lightLabel,
        ),
        // Apple 大标题 — Large title style (34pt) for top of page。
        // ignore: prefer_const_constructors
        toolbarTextStyle: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.37,
          color: isDark ? darkLabel : lightLabel,
        ),
      ),

      // ─── Card — Apple 分组列表样式 ──────────────────────────
      cardTheme: CardThemeData(
        color: isDark ? darkSecondarySystemBackground : lightSecondarySystemBackground,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          // Apple 分组列表无描边，用背景色区分层级。
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // ─── Divider — Apple 细分割线 ──────────────────────────
      dividerTheme: DividerThemeData(
        color: (isDark ? darkSeparator : lightSeparator).withValues(alpha: 0.75),
        thickness: 0.5,
        space: 0.5,
      ),

      // ─── InputDecoration — Apple 圆角搜索/输入框 ────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? darkTertiarySystemBackground
            : lightTertiarySystemBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        hintStyle: TextStyle(
          color: isDark ? darkTertiaryLabel : lightTertiaryLabel,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),

      // ─── FilledButton — Apple 蓝色胶囊按钮 ────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.24,
            color: Colors.white,
          ),
        ),
      ),

      // ─── OutlinedButton — Apple 描边按钮 ──────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          side: BorderSide(color: colorScheme.primary),
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),

      // ─── TextButton — Apple 文字按钮 ──────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),

      // ─── IconButton — Apple 圆形触控区 ────────────────────
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),

      // ─── TabBar — Apple 分段控件风格 ──────────────────────
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.08,
          color: colorScheme.primary,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.08,
          color: colorScheme.onSurfaceVariant,
        ),
        indicator: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),

      // ─── SnackBar — Apple 风格通知条 ──────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.15,
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),

      // ─── Dialog — Apple 风格弹窗 ──────────────────────────
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: isDark ? darkTertiarySystemBackground : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.41,
          color: isDark ? darkLabel : lightLabel,
        ),
        contentTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.24,
          color: isDark ? darkSecondaryLabel : lightSecondaryLabel,
        ),
      ),

      // ─── Tooltip — Apple 风格提示 ──────────────────────────
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: isDark ? darkTertiarySystemBackground : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: Colors.white,
        ),
      ),

      // ─── BottomNavigationBar — Apple 底部标签栏 ────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? darkSecondarySystemBackground : lightSecondarySystemBackground,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ─── ListTile — Apple 分组列表条目 ────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        tileColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.41,
          color: isDark ? darkLabel : lightLabel,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.08,
          color: isDark ? darkTertiaryLabel : lightTertiaryLabel,
        ),
      ),

      // ─── Chip — Apple 标签 ──────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? darkTertiarySystemBackground : lightTertiarySystemBackground,
        selectedColor: colorScheme.primaryContainer,
        disabledColor: isDark ? darkTertiarySystemBackground : lightTertiarySystemBackground,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isDark ? darkLabel : lightLabel,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isDark ? darkLabel : lightLabel,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(smallRadius),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // ─── FloatingActionButton — Apple 浮动操作 ────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),

      // ─── Page Transitions — Apple 风格导航动画 ──────────────
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      // ─── Slider — Apple 风格滑块 ──────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(),
      ),

      // ─── Switch — Apple 风格开关 ──────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? darkSecondaryLabel : lightSecondaryLabel;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colorScheme.primary;
          return isDark ? darkTertiarySystemBackground : const Color(0xFFE9E9EA);
        }),
      ),
    );
  }
}
