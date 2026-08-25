/// 笔记（NoteDocument / NotebookPage）→ PDF 导出服务。
///
/// 将笔记本页面导出为 PDF：文字块 + 笔画渲染。
/// 每个 [NotebookPage] 对应一个 PDF 页面。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/drawing/domain/stroke.dart';
import '../../features/drawing/domain/document.dart';
import '../../features/notes/domain/notebook.dart';
import '../rendering/stroke_renderer.dart';

/// 笔记 → PDF 导出服务。
///
/// 将 [NotebookPage] 列表导出为多页 PDF，支持文字、笔画混合排版。
class NotePdfExporter {
  const NotePdfExporter();

  /// 默认页面宽度（A4 横向）。
  static const double _defaultPageWidth = 842;

  /// 默认页面高度（A4 横向）。
  static const double _defaultPageHeight = 595;

  /// 默认字体大小。
  static const double _defaultFontSize = 12;

  /// 标题字体大小。
  static const double _titleFontSize = 24;

  /// 标题到内容的间距。
  static const double _titleSpacing = 20;

  /// 笔画渲染区域占页面高度的比例。
  static const double _strokeAreaRatio = 0.5;

  /// 将笔记本页面列表导出为 PDF 字节。
  Future<Uint8List> export({
    required List<NotebookPage> pages,
    String? title,
    String? author,
    double? pageWidth,
    double? pageHeight,
    bool landscape = true,
    void Function(int current, int total)? onProgress,
  }) async {
    final doc = pw.Document(
      title: title ?? '笔记导出',
      author: author,
    );

    final w = pageWidth ?? (landscape ? _defaultPageWidth : _defaultPageHeight);
    final h = pageHeight ?? (landscape ? _defaultPageHeight : _defaultPageWidth);
    final format = PdfPageFormat(w, h);

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];

      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (context) => _buildPage(page, w, h),
        ),
      );

      onProgress?.call(i + 1, pages.length);
    }

    return doc.save();
  }

  /// 构建单页笔记 PDF 内容。
  pw.Widget _buildPage(
    NotebookPage page,
    double pageWidth,
    double pageHeight,
  ) {
    final children = <pw.Widget>[];
    final pdfBg = PdfColor.fromInt(0xFFFFFFFF);
    final pdfText = PdfColor.fromInt(0xFF000000);

    // 标题
    if (page.title.isNotEmpty) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: _titleSpacing),
          child: pw.Text(
            page.title,
            style: pw.TextStyle(
              fontSize: _titleFontSize,
              fontWeight: pw.FontWeight.bold,
              color: pdfText,
            ),
          ),
        ),
      );
    }

    // 文字块
    for (final textItem in page.textItems) {
      if (textItem.text.isNotEmpty) {
        children.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              textItem.text,
              style: pw.TextStyle(
                fontSize: _defaultFontSize,
                color: pdfText,
              ),
            ),
          ),
        );
      }
    }

    // 笔画渲染为矢量图形。
    final strokes = _extractStrokes(page.document);
    if (strokes.isNotEmpty) {
      final strokeHeight = pageHeight * _strokeAreaRatio;
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.CustomPaint(
            size: PdfPoint(pageWidth - 40, strokeHeight),
            foregroundPainter: (PdfGraphics canvas, PdfPoint size) {
              _drawStrokes(canvas, strokes, size, pdfBg);
            },
          ),
        ),
      );
    }

    return pw.Container(
      width: pageWidth,
      height: pageHeight,
      padding: const pw.EdgeInsets.all(20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// 从 DrawingDocument 提取笔画列表。
  List<Stroke> _extractStrokes(DrawingDocument document) {
    final strokes = <Stroke>[];
    for (final layer in document.layers) {
      strokes.addAll(layer.strokes);
    }
    return strokes;
  }

  /// 在 PDF 画布上绘制笔画列表。
  void _drawStrokes(
    PdfGraphics canvas,
    List<Stroke> strokes,
    PdfPoint size,
    PdfColor background,
  ) {
    if (strokes.isEmpty) return;

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

    if (minX == maxX || minY == maxY) return;

    // 使用 StrokeRenderer 的 SVG path 生成器，保证矢量质量。
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final svgPath = StrokeRenderer.strokeToSvgPath(
        stroke,
        offset: ui.Offset(-minX, -minY),
      );
      if (svgPath == null) continue;
      final color = PdfColor.fromInt(stroke.color.toARGB32())
          .flatten(background: background);
      canvas
        ..setFillColor(color)
        ..drawShape(svgPath)
        ..fillPath();
    }
  }
}
