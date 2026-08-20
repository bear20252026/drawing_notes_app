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
  CanvasPainterV2({required this.document});

  final DocumentV2 document;

  @override
  void paint(Canvas canvas, Size size) {
    // 背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
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
      ..color = Colors.black.withValues(alpha: opacity)
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
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: opacity)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    switch (shape.type) {
      case 'rect':
        canvas.drawRect(
          Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height),
          paint,
        );
        break;
      case 'ellipse':
        canvas.drawOval(
          Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height),
          paint,
        );
        break;
    }
  }

  void _paintText(Canvas canvas, TextItem text, double opacity) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text.content,
        style: TextStyle(color: Colors.black.withValues(alpha: opacity), fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(text.x, text.y));
  }

  @override
  bool shouldRepaint(covariant CanvasPainterV2 oldDelegate) {
    return document != oldDelegate.document;
  }
}
