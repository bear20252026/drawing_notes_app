/// 画板（Canvas）→ PDF 导出服务。
///
/// 将画板上的笔画数据渲染为 PDF 页面。
/// 使用 StrokeRenderer.strokeToSvgPath + PdfGraphics API。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/drawing/domain/stroke.dart';
import '../rendering/stroke_renderer.dart';

/// 画板 → PDF 导出服务。
///
/// 将 [Stroke] 列表渲染为矢量 PDF 页面。
class CanvasPdfExporter {
  const CanvasPdfExporter();

  static const ui.Color _defaultBackground = ui.Color(0xFFFFFFFF);
  static const double _defaultPageWidth = 595;
  static const double _defaultPageHeight = 842;

  /// 将笔画列表导出为 PDF 字节。
  Future<Uint8List> export({
    required List<Stroke> strokes,
    String? title,
    String? author,
    double? pageWidth,
    double? pageHeight,
    double padding = 20,
  }) async {
    final doc = pw.Document(title: title, author: author);
    final w = pageWidth ?? _defaultPageWidth;
    final h = pageHeight ?? _defaultPageHeight;
    final format = PdfPageFormat(w, h);
    final bbox = _computeBoundingBox(strokes);

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) => _buildPage(strokes, bbox, w, h, padding),
      ),
    );

    return doc.save();
  }

  /// 将多页画板导出为多页 PDF。
  Future<Uint8List> exportMultiPage({
    required List<List<Stroke>> pages,
    String? title,
    String? author,
    double? pageWidth,
    double? pageHeight,
    double padding = 20,
    void Function(int current, int total)? onProgress,
  }) async {
    final doc = pw.Document(title: title, author: author);
    final w = pageWidth ?? _defaultPageWidth;
    final h = pageHeight ?? _defaultPageHeight;
    final format = PdfPageFormat(w, h);

    for (var i = 0; i < pages.length; i++) {
      final bbox = _computeBoundingBox(pages[i]);
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (context) => _buildPage(pages[i], bbox, w, h, padding),
        ),
      );
      onProgress?.call(i + 1, pages.length);
    }

    return doc.save();
  }

  /// 构建单页 PDF 内容。
  pw.Widget _buildPage(
    List<Stroke> strokes,
    math.Rectangle<double> bbox,
    double pageWidth,
    double pageHeight,
    double padding,
  ) {
    final pdfBg = PdfColor.fromInt(_defaultBackground.toARGB32());

    if (strokes.isEmpty) {
      return pw.Container(
        width: pageWidth,
        height: pageHeight,
        color: pdfBg,
      );
    }

    return pw.Stack(
      children: [
        pw.Container(
          width: pageWidth,
          height: pageHeight,
          color: pdfBg,
        ),
        pw.CustomPaint(
          size: PdfPoint(pageWidth, pageHeight),
          foregroundPainter: (PdfGraphics graphics, PdfPoint size) {
            for (final stroke in strokes) {
              if (stroke.points.isEmpty) continue;
              final svgPath = StrokeRenderer.strokeToSvgPath(
                stroke,
                offset: ui.Offset(-bbox.left, -bbox.top),
              );
              if (svgPath == null) continue;
              final color = PdfColor.fromInt(stroke.color.toARGB32())
                  .flatten(background: pdfBg);
              graphics
                ..setFillColor(color)
                ..drawShape(svgPath)
                ..fillPath();
            }
          },
        ),
      ],
    );
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
}
