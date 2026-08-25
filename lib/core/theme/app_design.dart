import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

/// Apple Design Language — 严格遵照 DESIGN.md (562行 Apple 设计规范)。
///
/// 核心原则：
/// - 单一蓝色 #0066cc（Action Blue）承载所有交互元素
/// - 无装饰渐变，无阴影在 UI chrome 上
/// - 颜色变化即分隔线
/// - SF Pro Display/Text 字体系统，negative letter-spacing
/// - Body copy 17px（非 16px）
/// - 80px 区块间距
abstract final class AppDesign {
  // ─── DESIGN.md 色彩体系 ──────────────────────────────────────────

  // Brand & Accent
  /// Action Blue — 唯一交互色（链接、CTA、选中态）。
  static const Color primary = Color(0xFF0066CC);
  /// Focus Blue — 键盘焦点环。
  static const Color primaryFocus = Color(0xFF0071E3);
  /// Sky Link Blue — 深色表面链接色。
  static const Color primaryOnDark = Color(0xFF2997FF);

  // Surface
  /// 纯白 — 主画布。
  static const Color canvas = Color(0xFFFFFFFF);
  /// 羊皮纸色 — Apple 标志性米白。
  static const Color canvasParchment = Color(0xFFF5F5F7);
  /// Pearl — 次要按钮底色。
  static const Color surfacePearl = Color(0xFFFAFAFC);
  /// Near-Black Tile 1 — 深色瓦片主色。
  static const Color surfaceTile1 = Color(0xFF272729);
  /// Near-Black Tile 2 — 深色瓦片微变体。
  static const Color surfaceTile2 = Color(0xFF2A2A2C);
  /// Near-Black Tile 3 — 深色瓦片底色。
  static const Color surfaceTile3 = Color(0xFF252527);
  /// 纯黑 — 全局导航栏背景。
  static const Color surfaceBlack = Color(0xFF000000);
  /// Translucent Chip Gray — 摄影浮层按钮底色。
  static const Color surfaceChipTranslucent = Color(0xFFD2D2D7);

  // On-Color Tokens
  /// On Primary — primary 上的文字色。
  static const Color onPrimary = Color(0xFFFFFFFF);
  /// On Dark — 深色表面上的文字色。
  static const Color onDark = Color(0xFFFFFFFF);

  // Text
  /// Near-Black Ink — 所有文字色。
  static const Color ink = Color(0xFF1D1D1F);
  /// Body on Dark — 深色表面文字。
  static const Color bodyOnDark = Color(0xFFFFFFFF);
  /// Body Muted — 深色表面次要文字。
  static const Color bodyMuted = Color(0xFFCCCCCC);
  /// Ink Muted 80 — 白色表面柔和文字。
  static const Color inkMuted80 = Color(0xFF333333);
  /// Ink Muted 48 — 禁用文字 / 法律文本。
  static const Color inkMuted48 = Color(0xFF7A7A7A);

  // Hairlines & Borders
  /// 柔和分隔线。
  static const Color dividerSoft = Color(0xFFF0F0F0);
  /// 1px 发丝线。
  static const Color hairline = Color(0xFFE0E0E0);

  // ─── 兼容旧引用 ────────────────────────────────────────────────
  static const Color appleBlue = primary;
  static const Color appleRed = Color(0xFFFF3B30);
  static const Color appleOrange = Color(0xFFFF9500);
  static const Color appleGreen = Color(0xFF4CD964);
  static const Color appleGray = Color(0xFF8E8E93);
  static const Color accent = primary;
  static const Color lightCanvas = canvas;
  static const Color lightSurface = canvas;
  static const Color lightSubtleSurface = canvasParchment;
  static const Color darkCanvas = surfaceBlack;
  static const Color darkSurface = surfaceTile1;
  static const Color darkSubtleSurface = surfaceTile2;

  // ─── DESIGN.md 排版体系 ─────────────────────────────────────────
  static const String _fontFamilyDisplay =
      'SF Pro Display, system-ui, -apple-system, sans-serif';
  static const String _fontFamilyBody =
      'SF Pro Text, system-ui, -apple-system, sans-serif';

  /// Hero Display — 56px/600/1.07/-0.28px
  static TextStyle get heroDisplay => const TextStyle(
        fontFamily: 'SF Pro Display, system-ui, -apple-system, sans-serif',
        fontSize: 56,
        fontWeight: FontWeight.w600,
        height: 1.07,
        letterSpacing: -0.28,
      );

  /// Display LG — 40px/600/1.10/0
  static TextStyle get displayLg => const TextStyle(
        fontFamily: 'SF Pro Display, system-ui, -apple-system, sans-serif',
        fontSize: 40,
        fontWeight: FontWeight.w600,
        height: 1.10,
        letterSpacing: 0,
      );

  /// Display MD — 34px/600/1.47/-0.374px
  static TextStyle get displayMd => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 34,
        fontWeight: FontWeight.w600,
        height: 1.47,
        letterSpacing: -0.374,
      );

  /// Lead — 28px/400/1.14/0.196px
  static TextStyle get lead => const TextStyle(
        fontFamily: 'SF Pro Display, system-ui, -apple-system, sans-serif',
        fontSize: 28,
        fontWeight: FontWeight.w400,
        height: 1.14,
        letterSpacing: 0.196,
      );

  /// Tagline — 21px/600/1.19/0.231px
  static TextStyle get tagline => const TextStyle(
        fontFamily: 'SF Pro Display, system-ui, -apple-system, sans-serif',
        fontSize: 21,
        fontWeight: FontWeight.w600,
        height: 1.19,
        letterSpacing: 0.231,
      );

  /// Body Strong — 17px/600/1.24/-0.374px
  static TextStyle get bodyStrong => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.24,
        letterSpacing: -0.374,
      );

  /// Body — 17px/400/1.47/-0.374px
  static TextStyle get body => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.47,
        letterSpacing: -0.374,
      );

  /// Caption — 14px/400/1.43/-0.224px
  static TextStyle get caption => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.43,
        letterSpacing: -0.224,
      );

  /// Caption Strong — 14px/600/1.29/-0.224px
  static TextStyle get captionStrong => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.29,
        letterSpacing: -0.224,
      );

  /// Button Large — 18px/300/1.0/0
  static TextStyle get buttonLarge => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 18,
        fontWeight: FontWeight.w300,
        height: 1.0,
        letterSpacing: 0,
      );

  /// Button Utility — 14px/400/1.29/-0.224px
  static TextStyle get buttonUtility => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.29,
        letterSpacing: -0.224,
      );

  /// Fine Print — 12px/400/1.0/-0.12px
  static TextStyle get finePrint => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.0,
        letterSpacing: -0.12,
      );

  /// Nav Link — 12px/400/1.0/-0.12px
  static TextStyle get navLink => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.0,
        letterSpacing: -0.12,
      );

  /// Lead Airy — 24px/300/1.5/0（环境页大段文字，罕见的 weight 300）
  static TextStyle get leadAiry => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 24,
        fontWeight: FontWeight.w300,
        height: 1.5,
        letterSpacing: 0,
      );

  /// Dense Link — 17px/400/2.41/0（页脚/商店链接列表，宽松行高）
  static TextStyle get denseLink => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 2.41,
        letterSpacing: 0,
      );

  /// Micro Legal — 10px/400/1.3/-0.08px（法律声明）
  static TextStyle get microLegal => const TextStyle(
        fontFamily: 'SF Pro Text, system-ui, -apple-system, sans-serif',
        fontSize: 10,
        fontWeight: FontWeight.w400,
        height: 1.3,
        letterSpacing: -0.08,
      );

  // ─── DESIGN.md 圆角体系 ─────────────────────────────────────────
  /// None — 0px（全出血瓦片）。
  static const double roundedNone = 0;
  /// XS — 5px（稀有inline chips）。
  static const double roundedXs = 5;
  /// SM — 8px（深色工具按钮）。
  static const double roundedSm = 8;
  /// MD — 11px（Pearl Button 胶囊）。
  static const double roundedMd = 11;
  /// LG — 18px（Store 工具卡片）。
  static const double roundedLg = 18;
  /// Pill — 9999px（主蓝色胶囊CTA、搜索框、chips）。
  static const double roundedPill = 9999;
  /// Full — 9999px（圆形控制芯片、button-icon-circular）。
  static const double roundedFull = 9999;

  // 兼容旧引用
  static const double cardRadius = roundedLg;
  static const double controlRadius = roundedSm;
  static const double smallRadius = roundedXs;
  static const double pillRadius = roundedPill;
  static const double fullRadius = roundedFull;

  // ─── DESIGN.md 间距体系 ─────────────────────────────────────────
  /// 4px
  static const double spacingXxs = 4;
  /// 8px
  static const double spacingXs = 8;
  /// 12px
  static const double spacingSm = 12;
  /// 17px（基础间距）
  static const double spacingMd = 17;
  /// 24px
  static const double spacingLg = 24;
  /// 32px
  static const double spacingXl = 32;
  /// 48px
  static const double spacingXxl = 48;
  /// 80px（区块间距 — Apple 大量留白）
  static const double spacingSection = 80;

  // 兼容旧引用
  static const double pagePadding = 20;
  static const double compactPagePadding = 12;

  // ─── 阴影（仅产品图片使用，UI chrome 无阴影） ─────────────────
  /// 产品图片阴影 — 系统唯一阴影。
  static const List<BoxShadow> productShadow = [
    BoxShadow(
      color: Color(0x38000000), // rgba(0,0,0,0.22)
      blurRadius: 30,
      offset: Offset(3, 5),
    ),
  ];

  // 旧引用 — 保留但不再用于 UI chrome
  static const List<BoxShadow> appleShadow = [];
  static const List<BoxShadow> appleShadowLarge = [];

  // ─── 动画 ──────────────────────────────────────────────────────
  static const Duration quickMotion = Duration(milliseconds: 140);
  static const Duration standardMotion = Duration(milliseconds: 200);

  // ─── 主题构建 ──────────────────────────────────────────────────
  static ThemeData lightTheme() => _theme(Brightness.light);
  static ThemeData darkTheme() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // DESIGN.md 色彩映射
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: canvas,
      primaryContainer: const Color(0xFFD6E4FF),
      onPrimaryContainer: const Color(0xFF001B3F),
      secondary: isDark ? surfaceTile2 : canvasParchment,
      onSecondary: isDark ? bodyOnDark : ink,
      secondaryContainer: isDark
          ? const Color(0xFF3A3999)
          : const Color(0xFFE0DEF7),
      onSecondaryContainer: isDark
          ? const Color(0xFFE0DEF7)
          : const Color(0xFF1B1847),
      tertiary: isDark ? const Color(0xFF30D158) : appleGreen,
      onTertiary: canvas,
      tertiaryContainer: isDark
          ? const Color(0xFF004A1A)
          : const Color(0xFFC8F0D4),
      onTertiaryContainer: isDark
          ? const Color(0xFFC8F0D4)
          : const Color(0xFF002108),
      error: appleRed,
      onError: canvas,
      errorContainer: const Color(0xFFFFDAD6),
      onErrorContainer: const Color(0xFF410002),
      surface: isDark ? surfaceTile1 : canvas,
      onSurface: isDark ? bodyOnDark : ink,
      surfaceContainerHighest: isDark
          ? const Color(0xFF48484A)
          : hairline,
      onSurfaceVariant: isDark ? bodyMuted : inkMuted48,
      outline: isDark ? const Color(0xFF636366) : hairline,
      outlineVariant: isDark
          ? const Color(0xFF48484A)
          : dividerSoft,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark ? canvas : surfaceTile1,
      onInverseSurface: isDark ? surfaceTile1 : canvasParchment,
      inversePrimary: isDark ? primary : const Color(0xFFB3D7FF),
      surfaceTint: primary,
    );

    // DESIGN.md 排版 — SF Pro
    final textTheme = TextTheme(
      displayLarge: TextStyle(
        fontFamily: _fontFamilyDisplay,
        fontSize: 40, // display-lg
        fontWeight: FontWeight.w600,
        height: 1.10,
        letterSpacing: 0,
        color: isDark ? bodyOnDark : ink,
      ),
      displayMedium: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 34, // display-md
        fontWeight: FontWeight.w600,
        height: 1.47,
        letterSpacing: -0.374,
        color: isDark ? bodyOnDark : ink,
      ),
      displaySmall: TextStyle(
        fontFamily: _fontFamilyDisplay,
        fontSize: 28, // lead
        fontWeight: FontWeight.w400,
        height: 1.14,
        letterSpacing: 0.196,
        color: isDark ? bodyOnDark : ink,
      ),
      headlineLarge: TextStyle(
        fontFamily: _fontFamilyDisplay,
        fontSize: 21, // tagline
        fontWeight: FontWeight.w600,
        height: 1.19,
        letterSpacing: 0.231,
        color: isDark ? bodyOnDark : ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 17, // body-strong
        fontWeight: FontWeight.w600,
        height: 1.24,
        letterSpacing: -0.374,
        color: isDark ? bodyOnDark : ink,
      ),
      headlineSmall: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 17, // body
        fontWeight: FontWeight.w400,
        height: 1.47,
        letterSpacing: -0.374,
        color: isDark ? bodyOnDark : ink,
      ),
      titleLarge: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 17, // body-strong
        fontWeight: FontWeight.w600,
        height: 1.24,
        letterSpacing: -0.374,
        color: isDark ? bodyOnDark : ink,
      ),
      titleMedium: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 17, // body
        fontWeight: FontWeight.w400,
        height: 1.47,
        letterSpacing: -0.374,
        color: isDark ? bodyOnDark : ink,
      ),
      titleSmall: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 14, // caption
        fontWeight: FontWeight.w400,
        height: 1.43,
        letterSpacing: -0.224,
        color: isDark ? bodyOnDark : ink,
      ),
      bodyLarge: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 17, // body
        fontWeight: FontWeight.w400,
        height: 1.47,
        letterSpacing: -0.374,
        color: isDark ? bodyOnDark : ink,
      ),
      bodyMedium: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 14, // caption
        fontWeight: FontWeight.w400,
        height: 1.43,
        letterSpacing: -0.224,
        color: isDark ? bodyOnDark : ink,
      ),
      bodySmall: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 12, // fine-print
        fontWeight: FontWeight.w400,
        height: 1.0,
        letterSpacing: -0.12,
        color: isDark ? bodyMuted : inkMuted48,
      ),
      labelLarge: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 14, // button-utility
        fontWeight: FontWeight.w400,
        height: 1.29,
        letterSpacing: -0.224,
        color: isDark ? bodyOnDark : ink,
      ),
      labelMedium: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 12, // fine-print
        fontWeight: FontWeight.w400,
        height: 1.0,
        letterSpacing: -0.12,
        color: isDark ? bodyMuted : inkMuted48,
      ),
      labelSmall: TextStyle(
        fontFamily: _fontFamilyBody,
        fontSize: 10, // micro-legal
        fontWeight: FontWeight.w400,
        height: 1.3,
        letterSpacing: -0.08,
        color: isDark ? bodyMuted : inkMuted48,
      ),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      // DESIGN.md: 纯白/羊皮纸背景（非灰色）
      scaffoldBackgroundColor: isDark ? surfaceBlack : canvas,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // DESIGN.md: hairline divider
      dividerColor: isDark ? const Color(0xFF48484A) : hairline,
    );

    return base.copyWith(
      // ─── AppBar — 全局导航栏（DESIGN.md: surface-black, 44px） ──
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceBlack,
        foregroundColor: bodyOnDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: pagePadding,
        toolbarHeight: 44,
        titleTextStyle: navLink.copyWith(
          color: bodyOnDark,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ─── Card — store-utility-card（DESIGN.md: 18px radius, no shadow） ──
      cardTheme: CardThemeData(
        color: isDark ? surfaceTile1 : canvas,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(roundedLg),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // ─── Divider — hairline（DESIGN.md: 1px rgba(0,0,0,0.08)） ──
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF48484A) : hairline,
        thickness: 0.5,
        space: 0.5,
      ),

      // ─── InputDecoration — search-input（DESIGN.md: pill radius, 44px height） ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surfaceTile2 : canvas,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingMd,
          vertical: spacingSm,
        ),
        hintStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          color: inkMuted48,
          fontSize: 17,
          fontWeight: FontWeight.w400,
          height: 1.47,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(roundedPill),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(roundedPill),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(roundedPill),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),

      // ─── FilledButton — button-primary（DESIGN.md: pill, #0066cc） ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          backgroundColor: primary,
          foregroundColor: canvas,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedPill),
          ),
          textStyle: body.copyWith(
            color: canvas,
          ),
        ),
      ),

      // ─── OutlinedButton — button-secondary-pill ──────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          side: const BorderSide(color: primary),
          foregroundColor: primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedPill),
          ),
          textStyle: body.copyWith(color: primary),
        ),
      ),

      // ─── TextButton — text-link（DESIGN.md: transparent bg, primary text） ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          foregroundColor: primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedSm),
          ),
          textStyle: body.copyWith(color: primary),
        ),
      ),

      // ─── IconButton — button-icon-circular（DESIGN.md: 44x44, full radius, chip-translucent bg） ──
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          backgroundColor: surfaceChipTranslucent,
          foregroundColor: ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedFull),
          ),
        ),
      ),

      // ─── TabBar — sub-nav-frosted（DESIGN.md: parchment bg, tagline text） ──
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: primary,
        unselectedLabelColor: inkMuted48,
        labelStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.224,
          color: primary,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.224,
          color: inkMuted48,
        ),
        indicator: BoxDecoration(
          color: primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(roundedSm),
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),

      // ─── SnackBar ────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: surfaceTile1,
        contentTextStyle: body.copyWith(color: bodyOnDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(roundedSm),
        ),
      ),

      // ─── Dialog — Apple 风格弹窗 ──────────────────────────────────
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: isDark ? surfaceTile2 : canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(roundedLg),
        ),
        titleTextStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.374,
          color: isDark ? bodyOnDark : ink,
        ),
        contentTextStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 17,
          fontWeight: FontWeight.w400,
          height: 1.47,
          letterSpacing: -0.374,
          color: isDark ? bodyMuted : inkMuted80,
        ),
      ),

      // ─── Tooltip ──────────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: surfaceTile1,
          borderRadius: BorderRadius.circular(roundedSm),
        ),
        textStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.12,
          color: bodyOnDark,
        ),
      ),

      // ─── BottomNavigationBar ──────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? surfaceTile1 : canvas,
        selectedItemColor: primary,
        unselectedItemColor: inkMuted48,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 10,
          fontWeight: FontWeight.w400,
          height: 1.3,
          letterSpacing: -0.08,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 10,
          fontWeight: FontWeight.w400,
          height: 1.3,
          letterSpacing: -0.08,
        ),
      ),

      // ─── ListTile ────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: spacingSm, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(roundedSm),
        ),
        tileColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 17,
          fontWeight: FontWeight.w400,
          height: 1.47,
          letterSpacing: -0.374,
          color: isDark ? bodyOnDark : ink,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.43,
          letterSpacing: -0.224,
          color: isDark ? bodyMuted : inkMuted48,
        ),
      ),

      // ─── Chip — configurator-option-chip（DESIGN.md: pill, 12x16 padding） ──
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? surfaceTile2 : canvas,
        selectedColor: primary.withValues(alpha: 0.12),
        disabledColor: isDark ? surfaceTile3 : dividerSoft,
        labelStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.224,
          color: isDark ? bodyOnDark : ink,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: _fontFamilyBody,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: isDark ? bodyOnDark : ink,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(roundedPill),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),

      // ─── FloatingActionButton ────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: canvas,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(roundedPill),
        ),
      ),

      // ─── Page Transitions — CupertinoPageTransitionsBuilder ──────
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      // ─── Slider ──────────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: isDark ? surfaceTile3 : dividerSoft,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.12),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(),
      ),

      // ─── Switch — Apple 风格开关 ──────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return canvas;
          return isDark ? bodyMuted : inkMuted48;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return isDark ? surfaceTile3 : const Color(0xFFE9E9EA);
        }),
      ),
    );
  }

  // ─── Apple 组件样式（DESIGN.md 第 5 节）──────────────────────────

  /// Button Primary — primary bg, pill radius, 11px × 22px padding
  static ButtonStyle get buttonPrimary => ButtonStyle(
        backgroundColor: WidgetStateProperty.all(primary),
        foregroundColor: WidgetStateProperty.all(canvas),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedPill),
          ),
        ),
        minimumSize: WidgetStateProperty.all(const Size(44, 44)),
      );

  /// Button Secondary Pill — transparent bg, primary border, pill radius
  static ButtonStyle get buttonSecondaryPill => ButtonStyle(
        backgroundColor: WidgetStateProperty.all(Colors.transparent),
        foregroundColor: WidgetStateProperty.all(primary),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedPill),
            side: const BorderSide(color: primary),
          ),
        ),
        minimumSize: WidgetStateProperty.all(const Size(44, 44)),
      );

  /// Button Dark Utility — ink bg, sm radius, 8px × 15px padding
  static ButtonStyle get buttonDarkUtility => ButtonStyle(
        backgroundColor: WidgetStateProperty.all(ink),
        foregroundColor: WidgetStateProperty.all(bodyOnDark),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedSm),
          ),
        ),
        minimumSize: WidgetStateProperty.all(const Size(44, 44)),
      );

  /// Search Input — canvas bg, pill radius, 12px × 20px padding, 44px height
  static InputBorder get searchInputBorder => OutlineInputBorder(
        borderRadius: BorderRadius.circular(roundedPill),
        borderSide: BorderSide(color: hairline),
      );

  /// Store Utility Card — canvas bg, 1px hairline border, lg radius, 24px padding
  static BoxDecoration get storeUtilityCard => BoxDecoration(
        color: canvas,
        border: Border.all(color: hairline, width: 1),
        borderRadius: BorderRadius.circular(roundedLg),
      );

  /// Product Shadow — rgba(0,0,0,0.22) 3px 5px 30px（唯一阴影）
  static List<BoxShadow> get productShadowComponent => [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.22),
          offset: const Offset(3, 5),
          blurRadius: 30,
          spreadRadius: 0,
        ),
      ];

  /// Soft Hairline — 1px rgba(0,0,0,0.08) border
  static BoxBorder get softHairline => Border.all(
        color: const Color(0xFF000000).withValues(alpha: 0.08),
        width: 1,
      );

  /// Button Icon Circular — 44×44px, full radius, surface-chip-translucent bg
  static ButtonStyle get buttonIconCircular => ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(44, 44)),
        backgroundColor: WidgetStateProperty.all(surfaceChipTranslucent),
        foregroundColor: WidgetStateProperty.all(ink),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedFull),
          ),
        ),
      );

  /// Configurator Option Chip — pill, 12×16 padding
  static ButtonStyle get configuratorOptionChip => ButtonStyle(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedPill),
          ),
        ),
        side: WidgetStateProperty.all(BorderSide(color: hairline)),
      );

  /// Button Pearl Capsule — surface-pearl bg, ink-muted-80 text, md radius, 8px × 14px padding
  /// DESIGN.md: product-card secondary button with 3px divider-soft border
  static ButtonStyle get buttonPearlCapsule => ButtonStyle(
        backgroundColor: WidgetStateProperty.all(surfacePearl),
        foregroundColor: WidgetStateProperty.all(inkMuted80),
        textStyle: WidgetStateProperty.all(
          caption.copyWith(color: inkMuted80),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedMd),
            side: const BorderSide(color: dividerSoft, width: 3),
          ),
        ),
        minimumSize: WidgetStateProperty.all(const Size(44, 44)),
      );

  /// Button Store Hero — primary bg, on-primary text, button-large typography (18/300), pill, 14px × 28px padding
  static ButtonStyle get buttonStoreHero => ButtonStyle(
        backgroundColor: WidgetStateProperty.all(primary),
        foregroundColor: WidgetStateProperty.all(canvas),
        textStyle: WidgetStateProperty.all(
          buttonLarge.copyWith(color: canvas),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedPill),
          ),
        ),
        minimumSize: WidgetStateProperty.all(const Size(44, 44)),
      );

  /// Text Link On Dark — transparent bg, primary-on-dark text, body typography
  static ButtonStyle get textLinkOnDark => ButtonStyle(
        backgroundColor: WidgetStateProperty.all(Colors.transparent),
        foregroundColor: WidgetStateProperty.all(primaryOnDark),
        textStyle: WidgetStateProperty.all(
          body.copyWith(color: primaryOnDark),
        ),
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundedSm),
          ),
        ),
      );

  /// Floating Sticky Bar — canvas-parchment bg (80% opacity), body typography, 64px height, 12px × 32px padding
  static BoxDecoration get floatingStickyBar => BoxDecoration(
        color: canvasParchment.withValues(alpha: 0.80),
        borderRadius: BorderRadius.zero,
      );

  /// Environment Quote Card — surface-tile-1 bg, on-dark text, display-lg typography, no radius, 80px padding
  static BoxDecoration get environmentQuoteCard => BoxDecoration(
        color: surfaceTile1,
        borderRadius: BorderRadius.circular(roundedNone),
      );

  /// Footer — canvas-parchment bg, ink-muted-80 text, fine-print typography, 64px padding
  static TextStyle get footerLinkHeading => captionStrong.copyWith(color: inkMuted80);
  static TextStyle get footerLink => denseLink.copyWith(color: inkMuted80);
  static TextStyle get footerLegal => finePrint.copyWith(color: inkMuted48);
}
