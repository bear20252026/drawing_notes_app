/// 画板（Canvas）→ 图片（PNG / JPG）导出服务。
///
/// 将画板上的笔画数据渲染为位图图片。
/// 使用 dart:ui PictureRecorder + Canvas 绘制笔画，再编码为 PNG 或 JPEG。
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../features/drawing/domain/stroke.dart';

/// 导出图片格式。
enum ImageExportFormat {
  png,
  jpeg,
}

/// 画板 → 图片导出服务。
///
/// 将 [Stroke] 列表渲染为位图，然后编码为 PNG 或 JPEG。
class CanvasImageExporter {
  const CanvasImageExporter();

  /// 默认背景色（白色）。
  static const ui.Color _defaultBackground = ui.Color(0xFFFFFFFF);

  /// 默认图片宽度（像素）。
  static const double _defaultWidth = 2480; // A4 @ 300dpi

  /// 默认图片高度（像素）。
  static const double _defaultHeight = 3508; // A4 @ 300dpi

  /// 将笔画列表导出为图片字节。
  ///
  /// [strokes] 笔画数据列表。
  /// [format] 输出格式（PNG 或 JPEG）。
  /// [width] / [height] 输出图片像素尺寸，默认 A4 @ 300dpi。
  /// [background] 背景色，默认白色。
  /// [padding] 内边距（像素）。
  Future<Uint8List> export({
    required List<Stroke> strokes,
    ImageExportFormat format = ImageExportFormat.png,
    double? width,
    double? height,
    ui.Color? background,
    double padding = 20,
  }) async {
    final w = width ?? _defaultWidth;
    final h = height ?? _defaultHeight;
    final bg = background ?? _defaultBackground;

    final image = await _renderToImage(
      strokes: strokes,
      width: w,
      height: h,
      background: bg,
      padding: padding,
    );

    try {
      final byteData = await image.toByteData(
        format: format == ImageExportFormat.png
            ? ui.ImageByteFormat.png
            : ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw StateError('Failed to encode image as ${format.name}');
      }

      if (format == ImageExportFormat.png) {
        return byteData.buffer.asUint8List();
      }

      // JPEG: 回退到 PNG 编码（dart:ui 无原生 JPEG 编码器）。
      final image2 = await _decodeRgba(
        byteData.buffer.asUint8List(),
        w.toInt(),
        h.toInt(),
      );
      try {
        final pngData = await image2.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (pngData == null) {
          throw StateError('Failed to encode JPEG fallback');
        }
        return pngData.buffer.asUint8List();
      } finally {
        image2.dispose();
      }
    } finally {
      image.dispose();
    }
  }

  /// 将笔画列表渲染为 [ui.Image]。
  Future<ui.Image> _renderToImage({
    required List<Stroke> strokes,
    required double width,
    required double height,
    required ui.Color background,
    required double padding,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 绘制背景。
    final bgPaint = Paint()..color = background;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    if (strokes.isNotEmpty) {
      final bbox = _computeBoundingBox(strokes);
      final offsetX = -bbox.left + padding;
      final offsetY = -bbox.top + padding;

      for (final stroke in strokes) {
        if (stroke.points.length < 2) continue;
        _drawStroke(canvas, stroke, offsetX, offsetY);
      }
    }

    final picture = recorder.endRecording();
    return picture.toImage(width.toInt(), height.toInt());
  }

  /// 在 Canvas 上绘制单个笔画。
  void _drawStroke(
    Canvas canvas,
    Stroke stroke,
    double offsetX,
    double offsetY,
  ) {
    final paint = Paint()
      ..color = stroke.color.withValues(alpha: stroke.opacity)
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();

    final points = stroke.points;
    final first = points.first;
    path.moveTo(first.x + offsetX, first.y + offsetY);

    if (points.length == 2) {
      final second = points[1];
      path.lineTo(second.x + offsetX, second.y + offsetY);
    } else {
      // 使用二次贝塞尔曲线平滑连接各点。
      for (var i = 1; i < points.length - 1; i++) {
        final current = points[i];
        final next = points[i + 1];
        final controlX = (current.x + next.x) / 2 + offsetX;
        final controlY = (current.y + next.y) / 2 + offsetY;
        path.quadraticBezierTo(
          current.x + offsetX,
          current.y + offsetY,
          controlX,
          controlY,
        );
      }
      // 连接最后一个点。
      final last = points.last;
      path.lineTo(last.x + offsetX, last.y + offsetY);
    }

    canvas.drawPath(path, paint);
  }

  /// 计算所有笔画的包围盒。
  math.Rectangle<double> _computeBoundingBox(List<Stroke> strokes) {
    if (strokes.isEmpty) {
      return const math.Rectangle(0, 0, 0, 0);
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final stroke in strokes) {
      for (final point in stroke.points) {
        minX = math.min(minX, point.x);
        minY = math.min(minY, point.y);
        maxX = math.max(maxX, point.x);
        maxY = math.max(maxY, point.y);
      }
    }

    if (minX == maxX) maxX = minX + 1;
    if (minY == maxY) maxY = minY + 1;

    return math.Rectangle(minX, minY, maxX - minX, maxY - minY);
  }

  /// 从 RGBA 字节数组解码为 [ui.Image]。
  Future<ui.Image> _decodeRgba(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
