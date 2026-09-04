import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../shared/widgets/apple_pressable.dart';

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

  /// 焦点蓝（Focus Blue）：键盘焦点环专用，比强调蓝略亮。
  /// DESIGN.md:8 `primary-focus: "#0071e3"`、:300「reserved for the keyboard
  /// focus ring on buttons (`outline: 2px solid`)」、:440 button-primary-focus。
  static const Color focusBlue = Color(0xFF0071E3);

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
///
/// 数值严格对齐 DESIGN.md:127-135（`rounded:` 段），**不得自创中间值**：
/// `none 0 / xs 5 / sm 8 / md 11 / lg 18 / pill 9999 / full 9999`。
/// 本项目未使用 none（需要直角时直接不设 borderRadius）。
abstract final class AppleRadius {
  static const double xs = 5;
  static const double sm = 8;
  static const double md = 11;
  static const double lg = 18;

  /// 胶囊（按钮 / 搜索框 / 芯片）—— Apple 的标志性形状。
  static const double pill = 9999;

  /// 圆形（浮动圆形控件），与 pill 同值但语义不同。
  static const double full = 9999;
}

/// Apple 排版助记（SF 风格：标题 w600 + 负字距，正文 17，控制 13）。
abstract final class AppleType {
  static const double body = 17;
  static const double title = 17;
  static const double control = 13;
  static const double caption = 11.5;
  static const double headline = 22;

  /// 正文行高。DESIGN.md:346「Body uses 1.47」、:506「Don't tighten
  /// line-height below 1.47 for body copy — the editorial leading is part of
  /// the brand」。此前本项目完全缺失，走的是 Flutter 默认行高。
  static const double bodyLineHeight = 1.47;

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
    height: bodyLineHeight,
    letterSpacing: -0.1,
    color: color,
  );

  static TextStyle controlStyle(
    Color color, {
    FontWeight weight = FontWeight.w600,
  }) => TextStyle(
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

/// 交互状态层（平台域裁决 C8，2026-09-04）。
///
/// **权威**：`android/skills`（Google 官方）+ Material 3 状态层规范。
/// `DESIGN.md` 对 hover / pressed 态没有任何规定，属**平台域**——
/// 按 `docs/DESIGN_SYSTEM.md` 第 2 节的分权模型，该域由平台官方规范说了算。
///
/// **不违反「单一强调色」铁律**（DESIGN.md:491）：状态层一律叠
/// `onSurface` 的中性半透明，不引入第二种强调色。描边状的键盘焦点环
/// 另由 `focusBlue` 负责（那是边框，这是底色，两者叠加不冲突）。
abstract final class AppleStateLayer {
  /// 鼠标悬停。
  static const double hover = 0.08;

  /// 键盘焦点（底色；与 2px focusBlue 描边共存）。
  static const double focus = 0.12;

  /// 按压中。
  static const double pressed = 0.12;

  /// 拖拽中。
  static const double dragged = 0.16;

  /// 禁用态前景压低（不是叠层，是 alpha）。
  static const double disabled = 0.38;

  /// 生成按钮 / 可点组件的 `overlayColor`。
  ///
  /// [onSurface] 传主题的 `colorScheme.onSurface`。
  /// 返回 `null` 表示该状态不叠色，保留组件默认行为。
  ///
  /// 判定顺序自「最强状态」往下：拖拽 > 按压 > 焦点 > 悬停。
  /// 禁用态返回 null——禁用由主题统一压低前景，不叠状态色。
  static WidgetStateProperty<Color?> overlay(Color onSurface) {
    return WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) return null;
      if (states.contains(WidgetState.dragged)) {
        return onSurface.withValues(alpha: dragged);
      }
      if (states.contains(WidgetState.pressed)) {
        return onSurface.withValues(alpha: pressed);
      }
      if (states.contains(WidgetState.focused)) {
        return onSurface.withValues(alpha: focus);
      }
      if (states.contains(WidgetState.hovered)) {
        return onSurface.withValues(alpha: hover);
      }
      return null;
    });
  }
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
    // ApplePressable 走「纯视觉」模式（onTap 为 null）：按压缩放交给它，
    // 点击行为仍由内部 FilledButton 处理，避免重复触发。
    return ApplePressable(
      child: FilledButton.icon(
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
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppleRadius.pill),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            AppleType.controlStyle(Colors.white),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
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
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: onSurface.withValues(alpha: 0.5),
        ),
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
  const AppleSectionHeader({super.key, required this.label, this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppleSpacing.md,
        12,
        AppleSpacing.xs,
        6,
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppleType.captionStyle(muted))),
          ?action,
        ],
      ),
    );
  }
}

/// 可复用的 Apple 确认对话框（R2-M4，架构审计 2026-08-31）。
///
/// 统一「取消 / 确认」双钮模式——全库 AlertDialog 样板 33 处的收敛入口。
/// 示例：`await AppleDialog.confirm(context, title: '彻底删除', content: '…')`
/// 确认返回 true，取消/ dismissing 返回 false；[confirmText] 传错误色文案
/// 时自动使用 error 色（危险操作语义）。
///
/// **平台域裁决 C1（2026-09-04）**：按钮顺序按平台走，不强制一种——
/// - Windows / Linux：主按钮在**左**（Fluent 与 GNOME 的既有习惯）；
/// - macOS / iOS / Android：主按钮在**右**（Apple HIG 与 M3 的习惯）。
/// 依据是 `docs/DESIGN_SYSTEM.md` 的分权模型：按钮顺序属**平台行为域**，
/// `DESIGN.md` 对该域表决权为零（它只管色/字/间距/圆角）。
class AppleDialog {
  AppleDialog._();

  /// Windows / Linux 把主按钮放在左边。
  static bool get _primaryFirst {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// 给尚未收敛到 [confirm] 的裸 `AlertDialog` 用的平台感知按钮行。
  ///
  /// 调用方**恒定按「次要 → 主要」顺序传入**（与现全库 36 处
  /// `actions: [取消, 确定]` 的写法一致），本方法负责按平台重排：
  /// Windows / Linux 返回倒序（主按钮在左），其余平台原样返回。
  ///
  /// 这样迁移成本 = 把 `actions: [...]` 包一层，不必逐个审查语义。
  static List<Widget> actions(List<Widget> secondaryToPrimary) =>
      _primaryFirst ? secondaryToPrimary.reversed.toList() : secondaryToPrimary;

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String content,
    String confirmText = '确定',
    String cancelText = '取消',
    bool dangerous = false,
  }) async {
    final cancelButton = TextButton(
      onPressed: () => Navigator.of(context).pop(false),
      child: Text(cancelText),
    );
    final confirmButton = FilledButton(
      style: dangerous
          ? FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            )
          : null,
      onPressed: () => Navigator.of(context).pop(true),
      child: Text(confirmText),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        // 代码里恒定写成「次要 → 主要」，由平台决定谁在左。
        actions: _primaryFirst
            ? <Widget>[confirmButton, cancelButton]
            : <Widget>[cancelButton, confirmButton],
      ),
    );
    return ok ?? false;
  }
}
