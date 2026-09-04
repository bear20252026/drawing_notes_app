import 'package:flutter/material.dart';

/// Apple 键盘焦点环。
///
/// **依赖方向约束（勿改）**：本文件**不能** `import 'apple_design.dart'`
/// —— `apple_design.dart` → `shared/widgets/apple_pressable.dart` → 本文件
/// 已经是一条链，再引回去就构成循环依赖，会被
/// `test/architecture_test.dart` 的「规则 2：零循环依赖」判红。
/// 因此下面两枚 Focus Blue 常量在此自含（不引 `AppleColor`），
/// 由 `test/core/theme/apple_surface_test.dart` 断言与 `AppleColor` 同值
/// —— 靠测试而不是靠 import 来守住单一事实来源。
///
/// **权威**：DESIGN.md ——
/// - :8 `primary-focus: "#0071e3"`；
/// - :300「(Focus Blue) is reserved for the keyboard focus ring on buttons
///   (`outline: 2px solid`)」；
/// - :440 `button-primary-focus` 同样使用 2px 描边。
///
/// 本项目此前**完全没有**焦点态：`ApplePressable` 的注释承诺「焦点环由主题
/// 层统一绘制（app_design.dart 的 2px Focus Blue）」，但主题层其实没配——
/// 键盘用户 Tab 到按钮时看不到任何指示。本文件把这条欠账补上。
///
/// **为什么不只靠 Flutter 默认的 focusColor**：Material 的焦点表现是
/// `overlayColor`（一层半透明底色，见 `AppleStateLayer.focus` = 12%），
/// 在深色图标按钮上几乎不可见，且触屏用户误触 Tab 后也分不清焦点在哪。
/// DESIGN.md 要的是**描边**（outline），两者叠加不冲突：底色 + 2px 环。
abstract final class AppleFocus {
  /// 描边宽度：DESIGN.md:300 明文 2px。
  static const double width = 2;

  /// 环与控件之间的留白（Apple HIG 的 focus ring 是外扩的，不压在控件上）。
  static const double gap = 2;

  /// 焦点环颜色：Focus Blue `#0071E3`（同 `AppleColor.focusBlue`）。
  ///
  /// 注意与强调色 Action Blue `#0066CC` 区分：同一个色族，但焦点环略亮，
  /// 在深色底上对比度更好。二者都在 DESIGN.md 的色板里，不算「第二强调色」。
  static const Color color = Color(0xFF0071E3);

  /// 深色模式下更亮一档，保证在深蓝底上可见（同
  /// `AppleColor.actionBlueOnDark` `#2997FF`）。
  static const Color colorOnDark = Color(0xFF2997FF);

  /// 高对比度档（C2）：仍是同一个蓝，只是把亮度推到对比度极限——
  /// 亮底 #003D99（对白 8.6:1）、暗底 #99CCFF（对黑 11:1）。
  /// 不换成别的色系，守住「单一强调色」铁律。
  static const Color colorHighContrastLight = Color(0xFF003D99);
  static const Color colorHighContrastDark = Color(0xFF99CCFF);

  /// 参数用 [highContrast] 布尔而非 `AppleContrast` 枚举：本文件位于
  /// `apple_design.dart → apple_pressable.dart → 本文件` 的依赖链末端，
  /// 再加出向依赖会推高上游的 Martin instability（见 AppleHairline
  /// 同名注释里的架构门禁说明）。
  static Color colorFor(Brightness brightness, {bool highContrast = false}) {
    if (highContrast) {
      return brightness == Brightness.dark
          ? colorHighContrastDark
          : colorHighContrastLight;
    }
    return brightness == Brightness.dark ? colorOnDark : color;
  }
}

/// 用 2px 焦点环包裹任意可聚焦控件。
///
/// 焦点环**外扩**绘制（不挤占布局）：外层始终预留 [AppleFocus.gap] 的
/// padding，焦点出现时只切换描边，不会让控件位置跳动。
///
/// 用法：
/// ```dart
/// AppleFocusRing(
///   borderRadius: AppleRadius.md,
///   child: IconButton(...),
/// )
/// ```
///
/// 已经自带焦点处理的控件（Material 按钮）也能用——本组件只读**后代**的
/// 焦点变化，不抢焦点节点。
class AppleFocusRing extends StatefulWidget {
  /// 默认圆角 = `AppleRadius.md`（DESIGN.md:424）。
  ///
  /// 不直接引用 `AppleRadius` 是为了避免 `apple_design.dart`（已 import
  /// `apple_pressable.dart`）与本文件形成循环导入。
  static const double defaultRadius = 11;

  const AppleFocusRing({
    super.key,
    required this.child,
    this.borderRadius = defaultRadius,
    this.enabled = true,
  });

  final Widget child;

  /// 控件自身圆角；焦点环会自动外扩到 `borderRadius + gap`。
  final double borderRadius;

  /// false 时永不绘制焦点环（例如控件被禁用）。
  final bool enabled;

  @override
  State<AppleFocusRing> createState() => _AppleFocusRingState();
}

class _AppleFocusRingState extends State<AppleFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // 焦点环颜色取自主题的 focusColor（由 app_design 统一注入，已含
    // 对比度档位），而不是自己按 brightness 现算——这样高对比度档下
    // 无需每个调用点都传 contrast。
    final ringColor = Theme.of(context).focusColor;
    final showRing = widget.enabled && _focused;
    final gap = AppleFocus.gap;

    return Focus(
      // 只观察焦点，不参与 Tab 遍历（canRequestFocus: false）——
      // 否则每个按钮都要按两次 Tab 才过得去。
      // 按键行为仍归 child（如 ApplePressable 的 Enter / Space 激活）。
      canRequestFocus: false,
      onFocusChange: (hasFocus) {
        if (_focused == hasFocus) return;
        if (!mounted) return;
        setState(() => _focused = hasFocus);
      },
      child: Stack(
        // 约束透传：child 收到的盒子约束与外层一致，包一层不改变布局。
        fit: StackFit.passthrough,
        // 焦点环是外扩绘制的（负 inset），必须关裁剪，否则会被切掉。
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (showRing)
            Positioned(
              left: -gap,
              top: -gap,
              right: -gap,
              bottom: -gap,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      widget.borderRadius + gap,
                    ),
                    border: Border.all(
                      color: ringColor,
                      width: AppleFocus.width,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
