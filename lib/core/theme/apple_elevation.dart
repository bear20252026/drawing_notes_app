import 'package:flutter/material.dart';

/// 表面层级：发丝线 + 海拔（阴影）三档。
///
/// **权威**：`DESIGN.md` 第 391–407 行「Elevation & Depth」。
///
/// 该章的核心事实是 **Apple 只有一条真阴影**，且只给产品渲染图用：
/// > "Apple uses exactly one drop-shadow, and it is applied to photographic
/// > product imagery — never to cards, never to buttons, never to text."
/// > （DESIGN.md:402）
/// > "Don't add shadows to cards, buttons, or text."（DESIGN.md:502）
///
/// 本项目是创作类 App（画布 / 笔记），没有产品渲染图，但**浮层**（对话框、
/// 弹出面板、吸顶工具条）仍需要「浮在内容之上」的视觉依据。因此本文件的
/// 裁决是：
/// - **内容层**（画布、文档列表、卡片、笔记正文）→ [flat]：零阴影，
///   层级只靠表面色差与 [AppleHairline] 发丝线。
/// - **浮层** → [raised]：极浅投影（10%），负责把浮层从内容里「抬」出来。
/// - **模态**（对话框）→ [overlay]：直接取 DESIGN.md:395 那条唯一真阴影
///   `rgba(0,0,0,0.22) 3px 5px 30px 0`，不另造第二套阴影语言。
///
/// 这样既守住了「不混阴影语法」，也不会让桌面端对话框看起来贴在背景上。
abstract final class AppleElevation {
  /// Flat —— 内容层：无阴影。层级靠表面色差 + [AppleHairline]。
  static const List<BoxShadow> flat = <BoxShadow>[];

  /// Raised —— 浮层（弹出菜单 / 面板 / 吸顶条）：极浅投影。
  ///
  /// 10% 黑 + 8px 模糊 + 2px 下沉，配合 [AppleHairline] 1px 边。
  /// 刻意比 M3 的 elevation 2（约 15%）更浅——DESIGN.md 的阴影哲学是
  /// 「能不投影就不投影」。
  static const List<BoxShadow> raised = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A000000), // 10%
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Overlay —— 模态（对话框 / 全屏弹层）：系统唯一那条真阴影。
  ///
  /// DESIGN.md:395 原文 `rgba(0, 0, 0, 0.22) 3px 5px 30px 0`
  ///（0x38 = 56/255 ≈ 0.22）。
  static const List<BoxShadow> overlay = <BoxShadow>[
    BoxShadow(
      color: Color(0x38000000), // 22%
      blurRadius: 30,
      offset: Offset(3, 5),
    ),
  ];

  /// 给 `DialogThemeData.elevation` 用的档位值。
  ///
  /// Flutter 的 Dialog 走 Material elevation（不收 `boxShadow`），
  /// 因此这里只提供档位号，颜色另由 `shadowColor` 对齐 [overlay]。
  static const double overlayLevel = 24;

  /// 给 `shadowColor` 用的颜色，与 [overlay] 同色。
  static const Color overlayColor = Color(0x38000000);
}

/// 发丝线（hairline）—— Apple 表达层级的默认手段。
///
/// **权威**：DESIGN.md:395「Soft hairline | 1px `rgba(0, 0, 0, 0.08)` border |
/// Utility cards, sub-nav frosted-glass separator」。
///
/// 本项目此前用的是 `ColorScheme.outlineVariant`（亮色 `#D2D2D7` ≈ 18% 灰，
/// 明显偏重，卡片看起来像「描边盒子」而不是苹果的轻分层）。收编到 8%
/// 后，卡片边界仍在，但视觉噪声显著下降。
///
/// **深色模式不能用黑**：8% 黑在深蓝底上几乎不可见，因此深色取 12% 白
/// ——这是同一个「相对背景 8% 亮度差」在深底上的等效表达。
abstract final class AppleHairline {
  /// 线宽：永远 1px，不随 DPI 变粗（Flutter 的逻辑像素即如此）。
  static const double width = 1;

  /// 亮色模式黑度 8%（DESIGN.md:395 明文）。
  static const double lightOpacity = 0.08;

  /// 深底等效值：12% 白。
  static const double darkOpacity = 0.12;

  /// 取当前主题下发丝线颜色。
  ///
  /// 参数用 [highContrast] 布尔而非 `AppleContrast` 枚举，是为了让本文件
  /// 不依赖 `apple_contrast.dart`——`core/di/providers.dart` 的 Martin
  /// instability 基线是 0.4，多一条出向依赖会把它从 0.33 推到 0.50 而
  /// 撞上架构门禁（`test/architecture_test.dart` 规则 3b）。
  static Color colorOf(BuildContext context, {bool highContrast = false}) =>
      colorFor(Theme.of(context).brightness, highContrast: highContrast);

  /// 取 [Brightness] 对应的发丝线颜色（不依赖 BuildContext，便于测试）。
  ///
  /// **高对比度档**（C2）：直接上纯黑 / 纯白 100% 不透明。8% 的发丝线
  /// 在低视力用户眼里等于没有——这正是 Windows 高对比度模式存在的理由。
  static Color colorFor(Brightness brightness, {bool highContrast = false}) {
    if (highContrast) {
      return brightness == Brightness.dark ? Colors.white : Colors.black;
    }
    return brightness == Brightness.dark
        ? Colors.white.withValues(alpha: darkOpacity)
        : Colors.black.withValues(alpha: lightOpacity);
  }

  /// 一条 [BorderSide]。
  static BorderSide sideOf(BuildContext context, {bool highContrast = false}) =>
      BorderSide(
        color: colorOf(context, highContrast: highContrast),
        width: width,
      );

  /// 一圈 [Border]。
  static Border borderOf(BuildContext context, {bool highContrast = false}) =>
      Border.fromBorderSide(sideOf(context, highContrast: highContrast));

  /// 圆角矩形描边（卡片 / 面板常用）。
  static RoundedRectangleBorder roundedBorderOf(
    BuildContext context, {
    double radius = 18,
    bool highContrast = false,
  }) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: sideOf(context, highContrast: highContrast),
  );

  /// 列表行分隔线。
  ///
  /// **shadcn 信息层级做法**（只抄做法不抄色，见 docs/DESIGN_SYSTEM.md）：
  /// 分隔线从**文字起始处**开始，而不是从屏幕边缘拉通——拉通的发丝线会把
  /// 每一行切成「格子」，而从文字处起则只做分组提示，层级更轻。
  static Widget listDivider(
    BuildContext context, {
    double indent = 16,
    double height = 1,
    bool highContrast = false,
  }) => Divider(
    height: height,
    thickness: width,
    indent: indent,
    endIndent: 0,
    color: colorOf(context, highContrast: highContrast),
  );
}
