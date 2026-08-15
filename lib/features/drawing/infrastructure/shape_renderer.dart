import 'dart:math' as math;
import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';

/// 无 UI 依赖的几何形状渲染器。
///
/// 屏幕画布与文件导出共用本实现，防止出现“编辑器里看得到，导出后丢失”的
/// 伪功能。所有坐标均为逻辑画布坐标。
class ShapeRenderer {
  const ShapeRenderer._();

  static Rect bounds(PageShapeItem shape) => Rect.fromLTWH(
    shape.x,
    shape.y,
    shape.width,
    shape.height,
  ).inflate(shape.strokeWidth + 20);

  static void drawDocumentShape(Canvas canvas, PageShapeItem shape) {
    canvas.save();
    canvas.translate(shape.x + shape.width / 2, shape.y + shape.height / 2);
    canvas.rotate(shape.rotation);
    canvas.scale(shape.flipX ? -1 : 1, shape.flipY ? -1 : 1);
    canvas.translate(-shape.width / 2, -shape.height / 2);
    drawLocal(canvas, shape, Size(shape.width, shape.height));
    canvas.restore();
  }

  /// 在元素自身的 `0,0 → size` 坐标系中绘制形状。
  static void drawLocal(Canvas canvas, PageShapeItem shape, Size size) {
    final stroke = Paint()
      ..color = Color(shape.color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = shape.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = shape.fillColor == null
        ? null
        : (Paint()
            ..color = Color(shape.fillColor!).withValues(alpha: 0.25)
            ..style = PaintingStyle.fill
            ..isAntiAlias = true);
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final random = math.Random(shape.id.hashCode);

    Path dashed(Path path) {
      if (!shape.dash) return path;
      final result = Path();
      for (final metric in path.computeMetrics()) {
        for (var offset = 0.0; offset < metric.length; offset += 16) {
          result.addPath(metric.extractPath(offset, offset + 8), Offset.zero);
        }
      }
      return result;
    }

    Offset jitter(Offset point) => shape.rough
        ? point +
              Offset(random.nextDouble() * 4 - 2, random.nextDouble() * 4 - 2)
        : point;

    void drawOutline(Path path) {
      canvas.drawPath(dashed(path), stroke);
      if (!shape.rough) return;
      final shifted = path.shift(
        Offset(random.nextDouble() * 3 - 1.5, random.nextDouble() * 3 - 1.5),
      );
      canvas.drawPath(dashed(shifted), stroke);
    }

    void drawFill(Path path) {
      if (fill != null) canvas.drawPath(path, fill);
      if (!shape.rough || shape.fillColor == null) return;
      final hatch = Paint()
        ..color = Color(shape.fillColor!).withValues(alpha: 0.55)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      final diagonal = math.sqrt(
        size.width * size.width + size.height * size.height,
      );
      canvas.save();
      canvas.clipPath(path);
      for (var offset = -diagonal; offset < diagonal; offset += 7) {
        canvas.drawLine(
          Offset(offset, 0),
          Offset(offset + diagonal, diagonal),
          hatch,
        );
      }
      canvas.restore();
    }

    switch (shape.shapeType) {
      case ShapeType.rect:
        final path = Path()..addRect(rect);
        drawFill(path);
        drawOutline(
          Path()
            ..moveTo(jitter(rect.topLeft).dx, jitter(rect.topLeft).dy)
            ..lineTo(jitter(rect.topRight).dx, jitter(rect.topRight).dy)
            ..lineTo(jitter(rect.bottomRight).dx, jitter(rect.bottomRight).dy)
            ..lineTo(jitter(rect.bottomLeft).dx, jitter(rect.bottomLeft).dy)
            ..close(),
        );
      case ShapeType.ellipse:
        final path = Path()..addOval(rect);
        drawFill(path);
        drawOutline(path);
      case ShapeType.diamond:
        final path = Path()
          ..moveTo(
            jitter(Offset(center.dx, 0)).dx,
            jitter(Offset(center.dx, 0)).dy,
          )
          ..lineTo(
            jitter(Offset(size.width, center.dy)).dx,
            jitter(Offset(size.width, center.dy)).dy,
          )
          ..lineTo(
            jitter(Offset(center.dx, size.height)).dx,
            jitter(Offset(center.dx, size.height)).dy,
          )
          ..lineTo(
            jitter(Offset(0, center.dy)).dx,
            jitter(Offset(0, center.dy)).dy,
          )
          ..close();
        drawFill(path);
        drawOutline(path);
      case ShapeType.line:
        // 优先使用保存的真实端点（相对外接框左上角），确保方向与
        // 鼠标轨迹一致；旧文档无端点时回退为"左下→右上"对角线。
        final lineStart = shape.lineStart ?? Offset(0, size.height);
        final lineEnd = shape.lineEnd ?? Offset(size.width, 0);
        drawOutline(
          Path()
            ..moveTo(jitter(lineStart).dx, jitter(lineStart).dy)
            ..lineTo(jitter(lineEnd).dx, jitter(lineEnd).dy),
        );
      case ShapeType.arrow:
        final start = shape.lineStart ?? Offset(0, size.height);
        final end = shape.lineEnd ?? Offset(size.width, 0);
        if (shape.elbow) {
          // 弯折箭头（对齐 Excalidraw binding.ts 的 elbow arrow）：
          // 以两端点中点为拐点做 90° 直角三段式（先水平再垂直），
          // 规避流程图中横跨的文本/元素，视觉更清晰。
          final corner = Offset((start.dx + end.dx) / 2, start.dy);
          drawOutline(
            Path()
              ..moveTo(start.dx, start.dy)
              ..lineTo(corner.dx, corner.dy)
              ..lineTo(end.dx, end.dy),
          );
          // 箭头头部仍指向末端（按末端附近线段方向计算）。
          final lastSegment = end - corner;
          final angle = lastSegment.direction;
          const length = 14.0;
          drawOutline(
            Path()
              ..moveTo(end.dx, end.dy)
              ..lineTo(
                end.dx - length * math.cos(angle - 0.4),
                end.dy - length * math.sin(angle - 0.4),
              )
              ..lineTo(
                end.dx - length * math.cos(angle + 0.4),
                end.dy - length * math.sin(angle + 0.4),
              ),
          );
        } else {
          drawOutline(
            Path()
              ..moveTo(start.dx, start.dy)
              ..lineTo(end.dx, end.dy),
          );
          final angle = (end - start).direction;
          const length = 14.0;
          drawOutline(
            Path()
              ..moveTo(end.dx, end.dy)
              ..lineTo(
                end.dx - length * math.cos(angle - 0.4),
                end.dy - length * math.sin(angle - 0.4),
              )
              ..lineTo(
                end.dx - length * math.cos(angle + 0.4),
                end.dy - length * math.sin(angle + 0.4),
              ),
          );
        }
    }
  }
}
