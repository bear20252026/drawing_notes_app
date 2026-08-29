import 'package:material_ui/material_ui.dart';
/// Apple (HIG) 设计语言 token 与可复用部件。
///
/// 参照 DESIGN.md（getdesign@apple）给出的苹果官方规范抽取：
/// - 单一强调色 Action Blue，克制使用；
/// - 低噪声表面层级（米白画布 / 白色表面 / 细描边胶囊），
/// - 胶囊按钮与圆角卡片（18px），
/// - SF 风格排版（标题 w600 + 负字距，正文 17px / 控制文本 13px）。
///
/// 颜色策略（用户@要求保留深蓝色系）：
/// - 明亮模式的「浅色 token」= Apple：米白画布 / 白表面 / 墨色文本。
/// - 黑暗模式的「深色 token」= 既有深蓝（navy）：`#101521` / `#181F2E` / `#222B3D`，
///   以便深色模式保留应用原有深蓝身份；结构风格（圆角/间距/字重/胶囊）两种模式均 Apple。
/// 本类提供可直接复用的部件，供各页面统一采用；页面背景/表面应优先用
/// `Theme.of(context).colorScheme` 自适应，深色模式自动落到深蓝色板。
abstract final class AppleColor {
  /// Action Blue：主强调色。
  static const Color actionBlue = Color(0xFF0066CC);
  /// 深色模式下的高亮蓝（按钮/链接）。
  static const Color actionBlueOnDark = Color(0xFF2997FF);
  /// 主墨色（近黑）。
  static const Color ink = Color(0xFF1D1D1F);
  /// 次要墨色。
  static const Color inkMuted = Color(0xFF6E6E73);
  /// 淡墨（辅助说明）。
  static const Color inkSubtle = Color(0xFF98989F);
  /// 米白画布。
  static const Color parchment = Color(0xFFF5F5F7);
  /// 白色表面。
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  /// 输入/芯片浅底。
  static const Color subtleSurface = Color(0xFFEBEBED);
  /// 细描边。
  static const Color hairline = Color(0xFFE0E0E0);
  /// 深色画布（深蓝 navy —— 保留原应用身份）。
  static const Color canvansDark = Color(0xFF101521);
  /// 深色表面（深蓝 navy）。
  static const Color surfaceDark = Color(0xFF181F2E);
  /// 深色芯片底（深蓝 navy）。
  static const Color subtleSurfaceDark = Color(0xFF222B3D);
  /// 星标橙（Apple 系统橙）。
  static const Color favourite = Color(0xFFFF9F0A);
  /// 系统绿（笔记类）。
  static const Color noteGreen = Color(0xFF30D158);
  /// 系统紫（块文档类）。
  static const Color blockPurple = Color(0xFFBF5AF2);
  /// 错误红（Apple 系统红）。
  static const Color errorRed = Color(0xFFFF3B30);
}

/// Apple 间距刻度（base=8）。
abstract final class AppleSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Apple 圆角刻度。
abstract final class AppleRadius {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 12;
  static const double lg = 18;
  static const double full = 9999;
}

/// Apple 排版助记（SF 风格：标题 w600 + 负字距，正文 17，控制 13）。
abstract final class AppleType {
  static const double body = 17;
  static const double title = 17;
  static const double control = 13;
  static const double caption = 11.5;
  static const double headline = 22;

  static TextStyle headlineStyle(Color color) => TextStyle(
        fontSize: headline,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: color,
      );

  static TextStyle titleStyle(Color color) => TextStyle(
        fontSize: title,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.35,
        color: color,
      );

  static TextStyle bodyStyle(Color color) => TextStyle(
        fontSize: body,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        color: color,
      );

  static TextStyle controlStyle(Color color, {FontWeight weight = FontWeight.w600}) =>
      TextStyle(
        fontSize: control,
        fontWeight: weight,
        letterSpacing: -0.1,
        color: color,
      );

  static TextStyle captionStyle(Color color) => TextStyle(
        fontSize: caption,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: color,
      );
}

/// 可复用的 Apple 主操作胶囊按钮。
///
/// 示例：`ApplePrimaryButton(label: '新建文档', onPressed: ...)`
class ApplePrimaryButton extends StatelessWidget {
  const ApplePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.icon(
      onPressed: onPressed,
      icon: icon == null ? null : Icon(icon, size: 16),
      label: Text(label),
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.primary),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
        padding: WidgetStatePropertyAll(
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppleRadius.full)),
        ),
        textStyle: WidgetStatePropertyAll(AppleType.controlStyle(Colors.white)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// 可复用的 Apple 胶囊搜索框。
class ApplePillSearchField extends StatelessWidget {
  const ApplePillSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppleType.bodyStyle(onSurface).copyWith(fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppleType.bodyStyle(
          onSurface.withValues(alpha: 0.4),
        ).copyWith(fontSize: 13),
        prefixIcon: Icon(Icons.search_rounded, size: 18, color: onSurface.withValues(alpha: 0.5)),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppleRadius.full),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppleRadius.full),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppleRadius.full),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
      ),
    );
  }
}

/// 可复用的 Apple 分区标题（分组/工具条分区）。
class AppleSectionHeader extends StatelessWidget {
  const AppleSectionHeader({
    super.key,
    required this.label,
    this.action,
  });

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppleSpacing.md, 12, AppleSpacing.xs, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppleType.captionStyle(muted),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
