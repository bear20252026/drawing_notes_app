/// AppleInkWell — Apple 风格触摸反馈。
///
/// DESIGN.md 要求所有交互元素使用高亮反馈（highlightColor），
/// 而非 Material 水波纹（splashColor）。
/// 点击时有微缩放动画 0.95x + 高亮。
library;

import 'package:flutter/material.dart';
import '../../theme/app_design.dart';

/// Apple 风格触摸反馈 — 替代所有 InkWell / GestureDetector 点击。
///
/// 功能：
/// - 高亮: primary.withValues(alpha: 0.12)
/// - 无水波纹: splashColor: Colors.transparent
/// - 点击缩放: 0.95x + 200ms easeInOutCubic
/// - 可选长按反馈
class AppleInkWell extends StatefulWidget {
  const AppleInkWell({
    super.key,
    required this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.highlightColor,
    this.child,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color? highlightColor;
  final Widget? child;

  @override
  State<AppleInkWell> createState() => _AppleInkWellState();
}

class _AppleInkWellState extends State<AppleInkWell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  bool _pressing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDesign.quickMotion,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        _pressing = true;
        _controller.forward();
      },
      onTapUp: (_) {
        _pressing = false;
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () {
        _pressing = false;
        _controller.reverse();
      },
      onLongPressStart: (_) {
        _pressing = true;
        _controller.forward();
      },
      onLongPressEnd: (_) {
        _pressing = false;
        _controller.reverse();
        widget.onLongPress?.call();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              decoration: BoxDecoration(
                color: _pressing
                    ? (widget.highlightColor ??
                        AppDesign.primary.withValues(alpha: 0.12))
                    : Colors.transparent,
                borderRadius: widget.borderRadius,
              ),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}
