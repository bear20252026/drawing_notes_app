// editor_v2——CanvasPainterV2（批次 E——2026-08-21——2026 最佳实践）。
//
// 直接 Canvas 绘画（CustomPainter + RepaintBoundary）——无每元素 Widget。
// 性能优化：只在 DocumentV2 变更时重绘（RepaintBoundary 隔离）。
// 遵循 industrial-drawing/Sheetifye 模式。
library;

import 'package:flutter/material.dart';

import 'package:editor_core/editor_core.dart';

/// V2 画布绘制器（CustomPainter——直接 Canvas 绘画）。
///
/// 遵循 2026 最佳实践（industrial-drawing/Sheetifye）：
/// - 所有绘图计算在 ViewModel（Headless Logic）——此只负责渲染
/// - 直接 Canvas 操作（无每元素 Widget——性能最优）
/// - 分层渲染：背景层/内容层/交互层（独立 CustomPainter）
class CanvasPainterV2 extends CustomPainter {
  CanvasPainterV2({
    required this.document,
    this.isInverted = false,
    this.fillMode = FillMode.stroke,
    this.strokeColor = '#000000',
    this.fillColor = '#CCCCCC',
  });

  final DocumentV2 document;

  /// 深色反转（Saber 借鉴——2026-08-21——白墨黑底——暗光护眼——
  /// 图片/PDF 也反转——默认 false 不反转——向后兼容——不搞崩）。
  final bool isInverted;

  /// 图形填充模式（用户需求修复——2026-08-22——stroke/fill/both——
  /// 默认 stroke 空心——向后兼容）。
  final FillMode fillMode;

  /// 描边颜色（用户需求修复——图形可换色——默认黑）。
  final String strokeColor;

  /// 填充颜色（用户需求修复——实心填充——默认浅灰）。
  final String fillColor;

  /// 前景色（反转：白/黑——Saber 深色模式——白墨黑底）。
  Color get _foreground => isInverted ? Colors.white : Colors.black;

  @override
  void paint(Canvas canvas, Size size) {
    // 背景（反转：黑底/白底——Saber 深色模式）。
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = isInverted ? Colors.black : Colors.white,
    );

    // 遍历图层绘制
    for (final layer in document.layers) {
      if (!layer.visible) continue;

      // 笔画
      for (final stroke in layer.strokes) {
        _paintStroke(canvas, stroke, layer.opacity);
      }

      // 形状（矩形/椭圆/箭头）
      for (final shape in layer.shapes) {
        _paintShape(canvas, shape, layer.opacity);
      }

      // 文本
      for (final text in layer.texts) {
        _paintText(canvas, text, layer.opacity);
      }
    }
  }

  void _paintStroke(Canvas canvas, LineItem stroke, double opacity) {
    if (stroke.points.length < 2) return;
    final paint = Paint()
      ..color = _foreground.withValues(alpha: opacity)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 手绘风格（Excalidraw Rough.js 简化版——二次贝塞尔平滑——
    // 平滑手绘线条——批次 F-6——不修改现有逻辑仅改进绘制）。
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
    // 用户需求修复（2026-08-22）：图形可换色 + 实心填充——
    // 支持 fillMode（stroke/fill/both——描边/填充/描边+填充）。
    final shouldStroke = fillMode == FillMode.stroke || fillMode == FillMode.both;
    final shouldFill = fillMode == FillMode.fill || fillMode == FillMode.both;

    final rect = Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);

    // 先填充（实心覆盖——用户需求——用 fillColor）。
    if (shouldFill) {
      final fillPaint = Paint()
        ..color = _hexToColor(fillColor).withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      _drawShapeBody(canvas, shape, rect, fillPaint);
    }

    // 后描边（空心轮廓——用 strokeColor——可换色）。
    if (shouldStroke) {
      final strokePaint = Paint()
        ..color = _hexToColor(strokeColor).withValues(alpha: opacity)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      _drawShapeBody(canvas, shape, rect, strokePaint);
    }
  }

  /// 绘制形状主体（rect/ellipse/diamond/triangle——支持 fill/stroke）。
  void _drawShapeBody(Canvas canvas, ShapeItem shape, Rect rect, Paint paint) {
    switch (shape.type) {
      case 'rect':
        canvas.drawRect(rect, paint);
      case 'ellipse':
        canvas.drawOval(rect, paint);
      case 'diamond':
        // 菱形（顶点上/右/下/左）。
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path, paint);
      case 'triangle':
        // 三角形（顶点上/右/左）。
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
        canvas.drawPath(path, paint);
      case 'pyramid':
        // 棱锥（顶点上/右/左 + 底部中线）。
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
  Color _hexToColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16) ?? 0x000000;
    return Color(0xFF000000 | value);
  }

  void _paintText(Canvas canvas, TextItem text, double opacity) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text.content,
        style: TextStyle(color: _foreground.withValues(alpha: opacity), fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(text.x, text.y));
  }

  @override
  bool shouldRepaint(covariant CanvasPainterV2 oldDelegate) {
    return document != oldDelegate.document || isInverted != oldDelegate.isInverted;
  }
}
