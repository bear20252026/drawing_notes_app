/// 盒子揭示动画效果（参考 Inspira UI 的 box-reveal）。
///
/// 内容从彩色方块后滑入显示。
/// 当元素进入视口时触发动画（使用 ScrollNotification 监听）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class BoxReveal extends StatefulWidget {
  const BoxReveal({
    super.key,
    required this.child,
    this.color = const Color(0xFF5046E6),
    this.duration = const Duration(milliseconds: 500),
    this.delay = const Duration(milliseconds: 250),
    this.triggerOnScroll = true,
  });

  /// 要显示的内容。
  final Widget child;

  /// 揭示方块的颜色。
  final Color color;

  /// 动画时长。
  final Duration duration;

  /// 内容动画延迟（相对于方块动画）。
  final Duration delay;

  /// 是否在滚动进入视口时触发。
  /// 为 false 时立即触发。
  final bool triggerOnScroll;

  @override
  State<BoxReveal> createState() => _BoxRevealState();
}

class _BoxRevealState extends State<BoxReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _boxSlideAnimation;
  late final Animation<double> _contentOpacityAnimation;
  late final Animation<Offset> _contentSlideAnimation;

  bool _hasTriggered = false;
  final GlobalKey _widgetKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    // 方块从左向右滑出。
    _boxSlideAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn,
      ),
    );

    // 内容淡入。
    _contentOpacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    // 内容从下方滑入。
    _contentSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    if (!widget.triggerOnScroll) {
      // 立即触发。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _checkVisibility() {
    if (_hasTriggered || !widget.triggerOnScroll) return;

    final renderObject = _widgetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    final position = renderObject.localToGlobal(Offset.zero);
    final viewportHeight = MediaQuery.of(_widgetKey.currentContext!).size.height;

    // 元素进入视口时触发。
    if (position.dy <= viewportHeight * 0.9) {
      _hasTriggered = true;
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听滚动以检测视口进入。
    if (widget.triggerOnScroll && !_hasTriggered) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _checkVisibility();
      });
      // 添加滚动监听。
      final scrollable = Scrollable.maybeOf(context);
      scrollable?.position.addListener(_checkVisibility);
    }

    return SizedBox(
      key: _widgetKey,
      width: double.infinity,
      child: Stack(
        children: [
          // 内容层。
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _contentOpacityAnimation.value,
                child: FractionalTranslation(
                  translation: _contentSlideAnimation.value,
                  child: widget.child,
                ),
              );
            },
          ),
          // 揭示方块层。
          AnimatedBuilder(
            animation: _boxSlideAnimation,
            builder: (context, child) {
              return Positioned.fill(
                child: FractionalTranslation(
                  translation: Offset(_boxSlideAnimation.value, 0),
                  child: Container(
                    color: widget.color,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
