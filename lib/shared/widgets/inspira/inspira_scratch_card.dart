// Inspira UI · Scratch to Reveal —— 刮刮卡式擦除揭示。
//
// 灵感来自 Inspira UI 的 Scratch to Reveal（MIT），纯 Flutter 重写：
// - 指针划过在覆盖层上「擦出」透明孔洞（saveLayer + BlendMode.clear）；
// - 占用网格按笔刷半径增量统计已揭示比例（每段仅扫描一次全网格，开销可忽略），
//   达到阈值触发 onRevealed 并淡出余层；
// - 尊重系统「减弱动态效果」：跳过淡出动画，达到阈值直接消失。
//
// 典型用法：
//   InspiraScratchCard(
//     overlayText: '刮开查看',
//     onRevealed: () => setState(() => revealed = true),
//     child: RewardContent(),
//   )

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 单条擦除轨迹段。
@immutable
class ScratchSegment {
  const ScratchSegment(this.from, this.to);
  final Offset from;
  final Offset to;
}

class InspiraScratchCard extends StatefulWidget {
  const InspiraScratchCard({
    super.key,
    required this.child,
    this.overlayText,
    this.overlayTextStyle,
    this.overlayColor = const Color(0xFFB8BCC2),
    this.overlayGradient,
    this.brushSize = 30,
    this.revealThreshold = 0.62,
    this.onRevealed,
  }) : assert(revealThreshold > 0 && revealThreshold <= 1);

  /// 被揭示的内容。
  final Widget child;

  /// 覆盖层居中文案（如「刮开查看」），随孔洞一起被擦除。
  final String? overlayText;
  final TextStyle? overlayTextStyle;
  final Color overlayColor;
  final Gradient? overlayGradient;

  /// 笔刷直径。
  final double brushSize;

  /// 触发 [onRevealed] 的已揭示面积比例（0~1）。
  final double revealThreshold;

  final VoidCallback? onRevealed;

  @override
  State<InspiraScratchCard> createState() => _InspiraScratchCardState();
}

class _InspiraScratchCardState extends State<InspiraScratchCard>
    with SingleTickerProviderStateMixin {
  final List<ScratchSegment> _segments = [];
  late final AnimationController _fadeController;
  bool _revealed = false;
  bool _overlayGone = false;

  // 占用网格：粗粒度统计已揭示比例，避免逐像素采样。
  static const int _gridCols = 24;
  static const int _gridRows = 18;
  static const int _totalCells = _gridCols * _gridRows;
  final Set<int> _grid = <int>{};

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..addStatusListener(_onFadeStatus);
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _overlayGone = true);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _onScratch(Offset localPos, Size size) {
    final from = _segments.isEmpty ? localPos : _segments.last.to;
    _segments.add(ScratchSegment(from, localPos));
    _markGrid(from, localPos, size);

    if (!_revealed) {
      final ratio = _grid.length / _totalCells;
      if (ratio >= widget.revealThreshold) {
        _revealed = true;
        widget.onRevealed?.call();
        _fadeController.forward();
      }
    }
    setState(() {});
  }

  /// 把线段两侧 [brushSize/2] 半径内的格子标记为已揭示。
  /// 每个新线段只扫一遍全网格（24×18=432 次），开销可忽略。
  void _markGrid(Offset from, Offset to, Size size) {
    final cellW = size.width / _gridCols;
    final cellH = size.height / _gridRows;
    final radius = widget.brushSize / 2;

    for (var cy = 0; cy < _gridRows; cy++) {
      for (var cx = 0; cx < _gridCols; cx++) {
        final idx = cy * _gridCols + cx;
        if (_grid.contains(idx)) continue;
        final center =
            Offset((cx + 0.5) * cellW, (cy + 0.5) * cellH);
        if (_distToSegment(center, from, to) <= radius) {
          _grid.add(idx);
        }
      }
    }
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.distanceSquared;
    if (lenSq == 0) return (p - a).distance;
    var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  @override
  Widget build(BuildContext context) {
    final reduceEffects = MediaQuery.disableAnimationsOf(context);
    final showOverlay = !_overlayGone && !(reduceEffects && _revealed);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;

        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (showOverlay)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _fadeController,
                  builder: (context, _) {
                    final opacity = reduceEffects
                        ? 1.0
                        : lerpDouble(1, 0, Curves.easeOut
                            .transform(_fadeController.value))!;
                    return Opacity(
                      opacity: opacity,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanDown: (d) => _onScratch(d.localPosition, size),
                        onPanStart: (d) => _onScratch(d.localPosition, size),
                        onPanUpdate: (d) =>
                            _onScratch(d.localPosition, size),
                        child: CustomPaint(
                          // 公开 painter 类型便于测试定位覆盖层。
                          painter: InspiraScratchOverlayPainter(
                            segments: List.unmodifiable(_segments),
                            brushSize: widget.brushSize,
                            color: widget.overlayColor,
                            gradient: widget.overlayGradient,
                            text: widget.overlayText,
                            textStyle: widget.overlayTextStyle ??
                                Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 覆盖层画笔（公开以便测试定位与外部定制）。
class InspiraScratchOverlayPainter extends CustomPainter {
  InspiraScratchOverlayPainter({
    required this.segments,
    required this.brushSize,
    required this.color,
    required this.gradient,
    required this.text,
    required this.textStyle,
  });

  final List<ScratchSegment> segments;
  final double brushSize;
  final Color color;
  final Gradient? gradient;
  final String? text;
  final TextStyle? textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(null, Paint());

    final fill = Paint()..style = PaintingStyle.fill;
    if (gradient != null) {
      fill.shader = gradient!.createShader(Offset.zero & size);
    } else {
      fill.color = color;
    }
    canvas.drawRect(Offset.zero & size, fill);

    if (text != null && text!.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(1, size.width - 24));
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
    }

    // 擦除孔洞：clear 只作用于本 saveLayer 内的覆盖像素。
    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..strokeWidth = brushSize
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final seg in segments) {
      canvas.drawLine(seg.from, seg.to, clear);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(InspiraScratchOverlayPainter old) =>
      old.segments.length != segments.length ||
      old.color != color ||
      old.gradient != gradient ||
      old.brushSize != brushSize ||
      old.text != text;
}
