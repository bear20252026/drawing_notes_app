import 'package:flutter/material.dart';

import 'apple_design.dart';
import 'apple_elevation.dart';
import 'apple_focus.dart';

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

  /// 卡片圆角 = `AppleRadius.lg`（DESIGN.md:425「Store utility cards」18px）。
  static const double cardRadius = AppleRadius.lg;

  /// 控件圆角 = `AppleRadius.md`（DESIGN.md:424「White Pearl Button
  /// capsules」11px）。此前写死 12——属于 DESIGN.md:511 明令禁止的
  ///「mixing radii grammars」。
  static const double controlRadius = AppleRadius.md;
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
      // 焦点环底色：与 AppleFocus 的 2px 描边共存（底色 12% + 描边 2px）。
      // DESIGN.md:8 `primary-focus: "#0071e3"`、:300「focus ring on buttons
      // (`outline: 2px solid`)」。此前主题层完全没有焦点态。
      focusColor: AppleFocus.colorFor(brightness),
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
          // 发丝线（DESIGN.md:395「1px rgba(0,0,0,0.08)」）。此前用
          // outlineVariant（≈18% 灰），卡片看起来像描边盒子而非苹果的轻分层。
          side: BorderSide(color: AppleHairline.colorFor(brightness)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        // 同一条发丝线：列表/侧栏分隔与卡片边界共用一套语言。
        color: AppleHairline.colorFor(brightness),
        thickness: AppleHairline.width,
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
          // 2px Focus Blue（DESIGN.md:300）。此前是 1.5px primary，
          // 与「焦点 = 2px 描边」的明文规定不符。
          borderSide: BorderSide(
            color: AppleFocus.colorFor(brightness),
            width: AppleFocus.width,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: const Size(44, 44),
              textStyle: base.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              // C8：M3 状态层（hover 8% / focus 12% / pressed 12%），叠 onSurface
              // 的中性半透明——不引入第二强调色。
              // 注：styleFrom 的 overlayColor 只收单一 Color（全状态同色），
              // 要按状态区分必须走 copyWith 的 WidgetStateProperty 重载。
              overlayColor: AppleStateLayer.overlay(colorScheme.onSurface),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              side: BorderSide(color: colorScheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(controlRadius),
              ),
            ).copyWith(
              overlayColor: AppleStateLayer.overlay(colorScheme.onSurface),
            ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style:
            IconButton.styleFrom(
              minimumSize: const Size(44, 44),
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
        // 唯一那条真阴影：DESIGN.md:395 `rgba(0,0,0,0.22) 3px 5px 30px 0`。
        // 只给模态用——卡片/按钮一律 flat（:502 明文禁止）。
        elevation: AppleElevation.overlayLevel,
        shadowColor: AppleElevation.overlayColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        // 对话框排版此前完全交给 M3 默认（title 22px / content 14px /
        // 默认字距）。按 DESIGN.md 的排版梯子重排：
        // - 标题 17px / w600 / -0.35（DESIGN.md 的 `title` 档）；
        // - 正文 15px / w400 / 行高 1.47（:506 明令行高不得低于 1.47）。
        //   取 15 而非 :504 的 17：17px 是**营销正文**（长文阅读）档，
        //   对话框是短交互文案，17px 会把确认弹窗撑成半屏；1.47 的行高
        //   规矩照办，只把字号收到 UI 尺度。
        // - 内容用 onSurfaceVariant，与标题形成层级差（shadcn 的信息层级
        //   做法：主信息用强色，说明性信息降一档）。
        titleTextStyle: AppleType.titleStyle(colorScheme.onSurface),
        contentTextStyle: AppleType.bodyStyle(
          colorScheme.onSurfaceVariant,
        ).copyWith(fontSize: 15),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppleSpacing.lg,
          0,
          AppleSpacing.lg,
          AppleSpacing.md,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
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
