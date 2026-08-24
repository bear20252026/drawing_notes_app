/// 文本揭示卡片（参考 Inspira UI 的 text-reveal-card）。
///
/// 鼠标悬停或触摸时，从左到右逐步揭示隐藏的文字。
/// 带有星空背景动画效果。
library;

import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class TextRevealCard extends StatefulWidget {
  const TextRevealCard({
    super.key,
    required this.hiddenText,
    this.header,
    this.width,
    this.height = 160,
    this.backgroundColor = const Color(0xFF1d1c20),
    this.revealColor = Colors.white,
    this.cursorColor = const Color(0xFF44403c),
    this.starsCount = 130,
    this.showStars = true,
  });

  /// 要揭示的隐藏文本。
  final Widget hiddenText;

  /// 卡片头部（可选）。
  final Widget? header;

  /// 卡片宽度。
  final double? width;

  /// 卡片高度。
  final double height;

  /// 背景颜色。
  final Color backgroundColor;

  /// 揭示文字颜色。
  final Color revealColor;

  /// 指示条颜色。
  final Color cursorColor;

  /// 星星数量。
  final int starsCount;

  /// 是否显示星空背景。
  final bool showStars;

  @override
  State<TextRevealCard> createState() => _TextRevealCardState();
}

class _TextRevealCardState extends State<TextRevealCard>
    with SingleTickerProviderStateMixin {
  double _widthPercentage = 0;
  bool _isMouseOver = false;
  final GlobalKey _cardKey = GlobalKey();

  void _updatePosition(double localX) {
    final renderBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final width = renderBox.size.width;
      setState(() {
        _widthPercentage = (localX / width * 100).clamp(0, 100);
      });
    }
  }

  void _onHover(PointerHoverEvent event) {
    _isMouseOver = true;
    _updatePosition(event.localPosition.dx);
  }

  void _onEnter(PointerEnterEvent event) {
    _isMouseOver = true;
  }

  void _onExit(PointerExitEvent event) {
    _isMouseOver = false;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && !_isMouseOver) {
        setState(() => _widthPercentage = 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rotateDeg = (_widthPercentage - 50) * 0.1;

    return MouseRegion(
      key: _cardKey,
      onEnter: _onEnter,
      onHover: _onHover,
      onExit: _onExit,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _isMouseOver = true;
          });
          _updatePosition(details.localPosition.dx);
        },
        onPanEnd: (_) {
          _isMouseOver = false;
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && !_isMouseOver) {
              setState(() => _widthPercentage = 0);
            }
          });
        },
        child: Container(
          width: widget.width,
          height: widget.height,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.header != null) widget.header!,
              const SizedBox(height: 8),
              Expanded(
                child: Stack(
                  children: [
                    // 星空背景。
                    if (widget.showStars)
                      Positioned.fill(
                        child: _StarsBackground(count: widget.starsCount),
                      ),

                    // 隐藏文本（底层）。
                    Positioned.fill(
                      child: ClipRect(
                        child: widget.hiddenText,
                      ),
                    ),

                    // 揭示文本（顶层，带 clipPath）。
                    Positioned.fill(
                      child: AnimatedContainer(
                        duration: _isMouseOver
                            ? Duration.zero
                            : const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: widget.backgroundColor,
                        ),
                        child: ClipRect(
                          clipper: _RevealClipper(_widthPercentage),
                          child: DefaultTextStyle(
                            style: TextStyle(color: widget.revealColor),
                            child: widget.hiddenText,
                          ),
                        ),
                      ),
                    ),

                    // 指示条。
                    if (_widthPercentage > 0)
                      AnimatedPositioned(
                        duration: _isMouseOver
                            ? Duration.zero
                            : const Duration(milliseconds: 400),
                        left: _widthPercentage / 100 *
                                (widget.width ?? 300) -
                            1,
                        top: 0,
                        bottom: 0,
                        child: Transform.rotate(
                          angle: rotateDeg * 3.14159 / 180,
                          child: Container(
                            width: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  widget.cursorColor,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 自定义裁剪器：从左到右揭示。
class _RevealClipper extends CustomClipper<Rect> {
  const _RevealClipper(this.percentage);

  final double percentage;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      0,
      0,
      size.width * percentage / 100,
      size.height,
    );
  }

  @override
  bool shouldReclip(_RevealClipper oldClipper) {
    return oldClipper.percentage != percentage;
  }
}

/// 星空背景。
class _StarsBackground extends StatelessWidget {
  const _StarsBackground({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final random = Random();
    return Stack(
      children: List.generate(count, (index) {
        final top = random.nextDouble();
        final left = random.nextDouble();
        final opacity = random.nextDouble();
        return Positioned(
          top: top * 100,
          left: left * 100,
          child: IgnorePointer(
            child: Container(
              width: 1,
              height: 1,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}
