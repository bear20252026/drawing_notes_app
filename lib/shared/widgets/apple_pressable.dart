import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/apple_focus.dart';
import '../../core/theme/apple_motion.dart';

/// Apple 系统级按压微交互：按下时 `transform: scale(0.95)`。
///
/// 依据 DESIGN.md:439 / :444 / :497 —— 原文要求「Use `transform: scale(0.95)`
/// as the active/press state on every button — it's the system-wide
/// micro-interaction」。此前本项目完全没有落地。
///
/// **三输入兼容**（用户硬性要求）：指针（鼠标/触屏）与键盘按下都会触发同一
/// 视觉反馈——
/// - 鼠标 / 触屏：`onTapDown` / `onTapUp` / `onTapCancel`；
/// - 键盘：`onKeyEvent` 捕获 Enter / Space 的按下与抬起。
///
/// 刻意**不用** `GestureDetector.onTap` 之外的语义：本组件只负责视觉缩放，
/// 实际点击行为交给 [onTap]，因此把它包在 `IconButton`/`GestureDetector`
/// 外面不会改变任何布局（Transform 不影响 layout 尺寸）。
///
/// 用法：
/// ```dart
/// ApplePressable(
///   onTap: () => doSomething(),
///   semanticLabel: '导出',
///   child: const Icon(Icons.ios_share_rounded),
/// )
/// ```
///
/// **两种模式**：
/// - [onTap] 非空：本组件接管点击（指针 + 键盘），适用于自定义控件。
/// - [onTap] 为 null：**只提供按压视觉**，手势完全交给 child（用
///   `HitTestBehavior.translucent`，且不插入 Focus 节点以免抢焦点）。
///   包在 `FilledButton`/`IconButton` 等 Material 控件外面时用这个模式。
///
/// **减弱动效**（`MediaQuery.disableAnimations`）：系统开启「减少动画」时
/// 自动跳过缩放，只保留颜色/overlay 反馈——依据 apple-design §14：
/// 「Reduced motion doesn't mean no feedback — it means a gentler,
/// non-vestibular equivalent」。
class ApplePressable extends StatefulWidget {
  const ApplePressable({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.scale = ApplePressable.defaultScale,
    this.enabled = true,
    this.duration = AppleMotion.press,
    this.borderRadius,
  });

  /// DESIGN.md 明文规定的系统级按压缩放系数。
  ///
  /// DESIGN.md:439 明文 0.95；STANDARDS.md:59 标准值 0.97、subtle 区间
  /// 0.95–0.98。**取 0.95**——DESIGN.md 是项目宪法，且落在 subtle 区间内。
  static const double defaultScale = AppleMotion.pressScale;

  final Widget child;

  /// 点击回调；为 null 时组件退化为纯容器（仍可播放按压反馈）。
  final VoidCallback? onTap;

  /// 读屏标签。传了才会向语义树暴露 button 语义（R6 审计结论）。
  final String? semanticLabel;

  /// 按压缩放系数，默认 0.95。
  final double scale;

  /// false 时忽略一切输入且不缩放。
  final bool enabled;

  final Duration duration;

  /// 可选：把缩放裁剪到圆角矩形内（用于卡片型按压目标）。
  final BorderRadius? borderRadius;

  @override
  State<ApplePressable> createState() => _ApplePressableState();
}

class _ApplePressableState extends State<ApplePressable> {
  /// 按下来源集合：指针与键盘各算一路，任意一路按下即处于按压态。
  ///（用 Set 而非 bool，避免「键盘按住 + 鼠标松开」提前取消缩放。）
  final Set<_PressSource> _pressed = <_PressSource>{};

  bool get _isPressed => _pressed.isNotEmpty && widget.enabled;

  void _add(_PressSource source) {
    if (!widget.enabled) return;
    if (_pressed.add(source) && mounted) setState(() {});
  }

  void _remove(_PressSource source) {
    if (_pressed.remove(source) && mounted) setState(() {});
  }

  void _clear() {
    if (_pressed.isEmpty) return;
    _pressed.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 减弱动效时不缩放（仍保留颜色类反馈）。三信号合一判定，
    // 见 AppleMotion.reduceMotionOf 的映射说明。
    final reduceMotion = AppleMotion.reduceMotionOf(context);
    final pressed = _isPressed && !reduceMotion;

    final scaled = AnimatedScale(
      scale: pressed ? widget.scale : 1.0,
      duration: widget.duration,
      // 必须是 AppleMotion.easeOut（0.23,1,0.32,1）；Flutter 内置的
      // Curves.easeOutCubic 控制点为 (0.215,0.61,0.355,1)，不是同一条曲线。
      curve: AppleMotion.easeOut,
      child: widget.child,
    );

    final clipped = widget.borderRadius == null
        ? scaled
        : ClipRRect(borderRadius: widget.borderRadius!, child: scaled);

    // 纯视觉模式：不接管手势、不抢焦点，事件穿透给 child。
    final visualOnly = widget.onTap == null;

    final detector = GestureDetector(
      behavior: visualOnly
          ? HitTestBehavior.translucent
          : HitTestBehavior.opaque,
      onTapDown: (_) => _add(_PressSource.pointer),
      onTapUp: (_) => _remove(_PressSource.pointer),
      onTapCancel: _clear,
      onTap: widget.onTap,
      child: clipped,
    );

    Widget result;
    if (visualOnly) {
      result = detector;
    } else {
      result = Focus(
        // 键盘可达：Enter / Space 触发按压与激活；焦点环由主题层统一绘制
        //（app_design.dart 的 2px Focus Blue）。
        onKeyEvent: (node, event) {
          // 注意：LogicalKeyboardKey 覆写了 ==/hashCode，不能放进 const Set
          //（analyzer: const_set_element_not_primitive_equality），改用逐个比较。
          final key = event.logicalKey;
          final isActivation =
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.numpadEnter;
          if (!isActivation) return KeyEventResult.ignored;
          if (event is KeyDownEvent) {
            _add(_PressSource.keyboard);
            return KeyEventResult.handled;
          }
          if (event is KeyUpEvent) {
            _remove(_PressSource.keyboard);
            widget.onTap?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: detector,
      );
    }

    if (widget.semanticLabel != null) {
      result = Semantics(
        label: widget.semanticLabel,
        button: true,
        enabled: widget.enabled,
        child: result,
      );
    }

    // 键盘焦点环：2px Focus Blue，外扩绘制不占布局。
    // 补上此前「注释里承诺、主题层却没配」的欠账——见 apple_focus.dart。
    // AppleFocusRing 的 Focus 节点 canRequestFocus: false，只观察不抢焦点，
    // 因此两种模式下都不会多出一次 Tab 停靠。
    return AppleFocusRing(
      borderRadius:
          widget.borderRadius?.topLeft.x ?? AppleFocusRing.defaultRadius,
      enabled: widget.enabled,
      child: result,
    );
  }
}

enum _PressSource { pointer, keyboard }
