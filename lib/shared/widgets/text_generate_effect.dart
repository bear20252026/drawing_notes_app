/// 文本逐字生成动画效果（参考 Inspira UI 的 text-generate-effect）。
///
/// 每个词逐个显现，带有透明度 + 模糊动画。
/// 可用于欢迎语、标题动画等场景。
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

class TextGenerateEffect extends StatefulWidget {
  const TextGenerateEffect({
    super.key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 700),
    this.delay = const Duration(milliseconds: 0),
    this.wordDelay = const Duration(milliseconds: 200),
    this.enableBlur = true,
    this.blurSigma = 10.0,
    this.textAlign = TextAlign.start,
  });

  /// 要显示的文本。
  final String text;

  /// 文本样式。
  final TextStyle? style;

  /// 每个词的动画时长。
  final Duration duration;

  /// 开始动画前的延迟。
  final Duration delay;

  /// 词与词之间的延迟。
  final Duration wordDelay;

  /// 是否启用模糊效果。
  final bool enableBlur;

  /// 初始模糊程度。
  final double blurSigma;

  /// 文本对齐方式。
  final TextAlign textAlign;

  @override
  State<TextGenerateEffect> createState() => _TextGenerateEffectState();
}

class _TextGenerateEffectState extends State<TextGenerateEffect> {
  late final List<String> _words;
  final List<bool> _revealed = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _words = widget.text.split(' ');
    _revealed.addAll(List.filled(_words.length, false));

    // 延迟后开始逐个显现。
    Future.delayed(widget.delay, () {
      if (!mounted) return;
      _startRevealAnimation();
    });
  }

  void _startRevealAnimation() {
    _timer = Timer.periodic(widget.wordDelay, (timer) {
      final nextIndex = _revealed.indexOf(false);
      if (nextIndex == -1) {
        timer.cancel();
        return;
      }
      if (mounted) {
        setState(() {
          _revealed[nextIndex] = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: List.generate(_words.length, (index) {
          final isRevealed = _revealed[index];
          final word = _words[index];

          return WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: AnimatedOpacity(
              opacity: isRevealed ? 1.0 : 0.0,
              duration: widget.duration,
              curve: Curves.easeOut,
              child: widget.enableBlur
                  ? ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: isRevealed ? 0 : widget.blurSigma,
                          sigmaY: isRevealed ? 0 : widget.blurSigma,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            word,
                            style: widget.style,
                            textAlign: widget.textAlign,
                          ),
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        word,
                        style: widget.style,
                        textAlign: widget.textAlign,
                      ),
                    ),
            ),
          );
        }),
      ),
      textAlign: widget.textAlign,
    );
  }
}
