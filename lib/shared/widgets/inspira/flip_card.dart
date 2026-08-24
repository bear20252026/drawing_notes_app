// Inspira UI——Flip Card 翻转预览卡（借鉴 framer-motion FlipCard）。
//
// 用途：笔记本/文档预览卡——正面缩略图，翻转后显示元数据详情。
// - 点击切换正反面（Y 轴 3D 旋转，跨 90° 时换面避免镜像）
// - 尊重系统"减少动态效果"（MediaQuery.disableAnimations → 直接切换）
// - 无障碍：Semantics(button + flipped 状态) + 焦点可达 + Enter/Space 触发
//
// 用法：打开动作由宿主在 front/back 内部自行放置按钮，
// 本组件的点击只负责翻转，不吞掉业务交互。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FlipCard extends StatefulWidget {
  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    this.height = 180,
    this.borderRadius = 12,
    this.duration = const Duration(milliseconds: 500),
    this.semanticLabel,
  });

  /// 正面（如：缩略图）。
  final Widget front;

  /// 背面（如：标题/页数/修改时间等元数据）。
  final Widget back;

  final double height;
  final double borderRadius;
  final Duration duration;

  /// 读屏器朗读标签。
  final String? semanticLabel;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _angle;
  bool _flipped = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _angle =
        Tween<double>(begin: 0, end: math.pi).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _flipped = !_flipped);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      // 减少动态效果：跳过旋转直接换面。
      _flipped ? _controller.value = 1 : _controller.value = 0;
      return;
    }
    _flipped ? _controller.forward() : _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            _toggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedBuilder(
            animation: _angle,
            builder: (context, _) {
              final angle = _angle.value;
              // 跨越 90° 后切换显示背面，并把剩余角度映射为 0..π/2 的正向旋转，
              // 避免背面文字镜像。
              final showBack = angle > math.pi / 2;
              final displayAngle = showBack ? angle - math.pi : angle;
              final child = showBack ? widget.back : widget.front;

              return SizedBox(
                height: widget.height,
                width: double.infinity,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001) // 透视深度
                    ..rotateY(displayAngle),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius:
                            BorderRadius.circular(widget.borderRadius),
                      ),
                      position: DecorationPosition.foreground,
                      child: child,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
