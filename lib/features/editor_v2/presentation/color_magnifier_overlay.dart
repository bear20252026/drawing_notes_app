// ColorMagnifierOverlay —— 放大镜取色环 UI（P2 #30）。
//
// 在长按取色时显示：放大环 + 十字准心 + 颜色预览。
// 跟随手指/笔尖位置实时更新。
library;

import 'package:flutter/material.dart';
import '../application/color_magnifier.dart';

/// 放大镜取色环 Widget。
///
/// 使用方式：将此 Widget 放在 Stack 顶层，传入当前 [state]。
/// 放大环尺寸由 [radius] 控制，默认 60px。
class ColorMagnifierOverlay extends StatelessWidget {
  const ColorMagnifierOverlay({
    super.key,
    required this.state,
    this.radius = 60,
  });

  /// 当前取色器状态。
  final ColorMagnifierState state;

  /// 放大环半径（像素）。
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (!state.isActive) return const SizedBox.shrink();

    return Positioned(
      left: state.position.dx - radius - 16, // 环在指针左上方
      top: state.position.dy - radius - 80,
      child: IgnorePointer(
        child: CustomPaint(
          size: Size(radius * 2 + 32, radius * 2 + 96),
          painter: _MagnifierPainter(
            state: state,
            radius: radius,
          ),
        ),
      ),
    );
  }
}

class _MagnifierPainter extends CustomPainter {
  _MagnifierPainter({
    required this.state,
    required this.radius,
  });

  final ColorMagnifierState state;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(radius + 16, radius + 16);

    // ── 1. 外圈阴影 ──
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, radius + 4, shadowPaint);

    // ── 2. 外圈边框 ──
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, borderPaint);

    // ── 3. 放大镜内部背景 ──
    final bgPaint = Paint()
      ..color = state.color ?? Colors.grey.shade300
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 3, bgPaint);

    // ── 4. 颜色信息文字 ──
    final textPainter = TextPainter(
      text: TextSpan(
        text: state.colorHex,
        style: TextStyle(
          color: _contrastColor(state.color ?? Colors.grey),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );

    // ── 5. 十字准心 ──
    final crosshairPaint = Paint()
      ..color = _contrastColor(state.color ?? Colors.grey)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const crossSize = 8.0;
    canvas.drawLine(
      Offset(center.dx - crossSize, center.dy),
      Offset(center.dx + crossSize, center.dy),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - crossSize),
      Offset(center.dx, center.dy + crossSize),
      crosshairPaint,
    );

    // ── 6. 底部颜色标签 ──
    final tagPainter = TextPainter(
      text: TextSpan(
        text: state.colorHex,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tagPainter.layout();

    final tagTop = center.dy + radius + 12;
    final tagRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, tagTop + tagPainter.height / 2 + 4),
        width: tagPainter.width + 16,
        height: tagPainter.height + 8,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(tagRect, Paint()..color = Colors.black87);
    tagPainter.paint(
      canvas,
      Offset(center.dx - tagPainter.width / 2, tagTop + 4),
    );
  }

  /// 根据背景色亮度选择对比色（黑/白）。
  Color _contrastColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  bool shouldRepaint(_MagnifierPainter oldDelegate) {
    return oldDelegate.state != state;
  }
}
