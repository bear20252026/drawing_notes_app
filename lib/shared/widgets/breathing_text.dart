/// 呼吸文字动画效果（参考 Inspira UI 的 breathing-text）。
///
/// 每个字母的字体粗细做波浪式循环动画（从细到粗再到细），
/// 字母间有交错延迟，形成"呼吸"般的视觉效果。
library;

import 'package:flutter/material.dart';

class BreathingText extends StatefulWidget {
  const BreathingText({
    super.key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 1500),
    this.staggerDuration = const Duration(milliseconds: 100),
    this.repeatDelay = const Duration(milliseconds: 100),
    this.minFontWeight = 100,
    this.maxFontWeight = 900,
    this.textAlign = TextAlign.start,
  });

  /// 要显示的文本。
  final String text;

  /// 基础文本样式。
  final TextStyle? style;

  /// 每个字母的呼吸周期。
  final Duration duration;

  /// 字母间交错延迟。
  final Duration staggerDuration;

  /// 循环重复延迟。
  final Duration repeatDelay;

  /// 最小字体粗细。
  final int minFontWeight;

  /// 最大字体粗细。
  final int maxFontWeight;

  /// 文本对齐方式。
  final TextAlign textAlign;

  @override
  State<BreathingText> createState() => _BreathingTextState();
}

class _BreathingTextState extends State<BreathingText>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    final letters = widget.text.split('');

    _controllers = List.generate(letters.length, (index) {
      final controller = AnimationController(
        duration: widget.duration,
        vsync: this,
      );

      // 交错延迟后开始动画。
      Future.delayed(widget.staggerDuration * index, () {
        if (mounted) {
          controller.repeat(
            reverse: true,
            period: widget.duration + widget.repeatDelay,
          );
        }
      });

      return controller;
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(
        begin: widget.minFontWeight.toDouble(),
        end: widget.maxFontWeight.toDouble(),
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOut,
      ));
    }).toList();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letters = widget.text.split('');

    return Text.rich(
      TextSpan(
        children: List.generate(letters.length, (index) {
          return WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: AnimatedBuilder(
              animation: _animations[index],
              builder: (context, child) {
                return Text(
                  letters[index],
                  style: (widget.style ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight(
                      _animations[index].value.round(),
                    ),
                  ),
                  textAlign: widget.textAlign,
                );
              },
            ),
          );
        }),
      ),
      textAlign: widget.textAlign,
    );
  }
}
