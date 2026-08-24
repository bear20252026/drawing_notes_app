// V2 CanvasPainter — CustomPainter 直接 Canvas 绘画（2026-08-21 最佳实践）。
//
// 性能优化：仅 DocumentV2 变更时重绘（RepaintBoundary 隔离）。
// 分层渲染：背景层 → 内容层 → 交互层（独立 CustomPainter）。
// 遵循 industrial-drawing/Sheetifye 模式。
library;

import 'package:flutter/material.dart';
import 'package:editor_core/editor_core.dart';

/// V2 画布绘制器（CustomPainter——直接 Canvas 绘画）。
class CanvasPainterV2 extends CustomPainter {
  CanvasPainterV2({
    required this.document,
    this.isInverted = false,
    this.fillMode = FillMode.stroke,
    this.strokeColor = '#000000',
    this.fillColor = '#CCCCCC',
  });

  final DocumentV2 document;

  /// 深色反转（Saber 借鉴——白墨黑底——暗光护眼）。
  final bool isInverted;

  /// 图形填充模式（stroke/fill/both——默认 stroke 空心）。
  final FillMode fillMode;

  /// 描边颜色（#RRGGBB）。
  final String strokeColor;

  /// 填充颜色（#RRGGBB）。
  final String fillColor;

  /// 前景色（反转：白/黑）。
  Color get _foreground => isInverted ? Colors.white : Colors.black;

  @override
  void paint(Canvas canvas, Size size) {
    // 背景（反转：黑底/白底）。
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = isInverted ? Colors.black : Colors.white,
    );

    // 遍历图层绘制。
    for (final layer in document.layers) {
      if (!layer.visible) continue;

      // 笔画。
      for (final stroke in layer.strokes) {
        _paintStroke(canvas, stroke, layer.opacity);
      }

      // 形状（矩形/椭圆/箭头等）。
      for (final shape in layer.shapes) {
        _paintShape(canvas, shape, layer.opacity);
      }

      // 文本。
      for (final text in layer.texts) {
        _paintText(canvas, text, layer.opacity);
      }
    }
  }

  void _paintStroke(Canvas canvas, LineItem stroke, double layerOpacity) {
    if (stroke.points.length < 2) return;
    final paint = Paint()
      ..color = _hexToColor(stroke.color)
          .withValues(alpha: stroke.opacity * layerOpacity)
      ..strokeWidth = stroke.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 手绘风格（Excalidraw Rough.js 简化版——二次贝塞尔平滑）。
    final pts = stroke.points;
    final path = Path();
    path.moveTo(pts.first.x, pts.first.y);
    for (var i = 1; i < pts.length - 1; i++) {
      final midX = (pts[i].x + pts[i + 1].x) / 2;
      final midY = (pts[i].y + pts[i + 1].y) / 2;
      path.quadraticBezierTo(pts[i].x, pts[i].y, midX, midY);
    }
    if (pts.length > 1) {
      path.lineTo(pts.last.x, pts.last.y);
    }
    canvas.drawPath(path, paint);
  }

  void _paintShape(Canvas canvas, ShapeItem shape, double opacity) {
    final shouldStroke =
        fillMode == FillMode.stroke || fillMode == FillMode.both;
    final shouldFill =
        fillMode == FillMode.fill || fillMode == FillMode.both;

    final rect =
        Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);

    // 先填充（实心覆盖——用 fillColor）。
    if (shouldFill) {
      final fillPaint = Paint()
        ..color = _hexToColor(shape.fillColor).withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      _drawShapeBody(canvas, shape.type, rect, fillPaint);
    }

    // 后描边（空心轮廓——用 strokeColor）。
    if (shouldStroke) {
      final strokePaint = Paint()
        ..color = _hexToColor(shape.strokeColor).withValues(alpha: opacity)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      _drawShapeBody(canvas, shape.type, rect, strokePaint);
    }
  }

  /// 绘制形状主体（rect/ellipse/diamond/triangle/pyramid）。
  void _drawShapeBody(
      Canvas canvas, String shapeType, Rect rect, Paint paint) {
    switch (shapeType) {
      case 'rect':
        canvas.drawRect(rect, paint);
      case 'ellipse':
        canvas.drawOval(rect, paint);
      case 'diamond':
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path, paint);
      case 'triangle':
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
        canvas.drawPath(path, paint);
      case 'pyramid':
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
        canvas.drawPath(path, paint);
      default:
        canvas.drawRect(rect, paint);
    }
  }

  /// 十六进制颜色字符串转 Color（#RRGGBB）。
  static Color _hexToColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16) ?? 0x000000;
    return Color(0xFF000000 | value);
  }

  void _paintText(Canvas canvas, TextItem text, double opacity) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text.content,
        style: TextStyle(
          color: _foreground.withValues(alpha: opacity),
          fontSize: 14.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(text.x, text.y));
  }

  @override
  bool shouldRepaint(covariant CanvasPainterV2 oldDelegate) {
    return document != oldDelegate.document ||
        isInverted != oldDelegate.isInverted ||
        fillMode != oldDelegate.fillMode ||
        strokeColor != oldDelegate.strokeColor ||
        fillColor != oldDelegate.fillColor;
  }
}
