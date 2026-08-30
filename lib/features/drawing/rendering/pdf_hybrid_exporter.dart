import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_renderer.dart';

/// PDF 矢量 + 光栅混合导出器。
///
/// 参考 Saber 的导出策略（独立实现）：可矢量化的钢笔笔画以 SVG path 矢量
/// 写入 PDF，保证任意缩放清晰；需要透明度混合（高亮笔）或着色器效果
/// （铅笔）的内容，以及图片与形状，以光栅位图嵌入。光栅层由调用方通过
/// [DrawingController.renderToPng]（配合 excludedTypes 排除矢量笔画）渲染。
class PdfHybridExporter {
  const PdfHybridExporter._();

  /// 哪些笔画必须走光栅化：PDF 不支持透明混合与着色器效果。
  ///
  /// 高亮笔依赖 darken 分层叠色、铅笔依赖颗粒 Shader，均无法以
  /// 不透明矢量路径表达；钢笔是唯一可矢量化笔型。
  static bool shouldRasterize(Stroke stroke) =>
      stroke.type == BrushType.marker || stroke.type == BrushType.pencil;

  /// 生成混合 PDF。
  ///
  /// [bounds] 为画布导出区域（决定页面尺寸）；[rasterPng] 为光栅层位图
  /// （背景 + 高亮/铅笔/图片/形状，即“排除矢量笔画后的全部内容”）；
  /// [vectorStrokes] 为以矢量写入的钢笔笔画。位图与矢量共用同一坐标系，
  /// [bounds.topLeft] 作为偏移，保证无限画布下两者精确对齐。
  /// [jpegQuality] 可选：1-100 时把光栅层转 JPEG 压缩（导出体积优化，
  /// 有损；默认 null 保持 PNG 无损质量）。含文本/形状时建议保持 PNG。
  static Future<Uint8List> export({
    required ui.Rect bounds,
    required Uint8List rasterPng,
    required List<Stroke> vectorStrokes,
    ui.Color background = const ui.Color(0xFFFFFFFF),
    int? jpegQuality,
  }) async {
    final pdfBackground = PdfColor.fromInt(background.toARGB32());
    final offset = ui.Offset(-bounds.left, -bounds.top);
    final rasterBytes = jpegQuality == null
        ? rasterPng
        : _encodeJpeg(rasterPng, jpegQuality);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(bounds.width, bounds.height),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Image(
                pw.MemoryImage(rasterBytes),
                fit: pw.BoxFit.fill,
              ),
            ),
            // 显式尺寸：Stack 以非定位子级定尺寸，若 CustomPaint 为 0×0
            // 会让 Stack 塌缩，Positioned.fill 的图片拿到 0 约束产生 NaN。
            pw.CustomPaint(
              size: PdfPoint(bounds.width, bounds.height),
              foregroundPainter: (PdfGraphics graphics, PdfPoint size) {
                for (final stroke in vectorStrokes) {
                  final svgPath = StrokeRenderer.strokeToSvgPath(
                    stroke,
                    offset: offset,
                  );
                  if (svgPath == null) continue;
                  final color = PdfColor.fromInt(stroke.color.toARGB32())
                      .flatten(background: pdfBackground);
                  graphics.setFillColor(color);
                  graphics.drawShape(svgPath);
                  graphics.fillPath();
                }
              },
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// 将 PNG 字节转 JPEG（[quality] 1-100，越高质量越高体积越大）。
  ///
  /// 用纯 Dart image 包编码（dart:ui 的 ImageByteFormat 不支持 JPEG 输出）；
  /// 解码失败时回退原字节，保证导出永不因压缩失败中断。
  static Uint8List _encodeJpeg(Uint8List pngBytes, int quality) {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) return pngBytes;
    return Uint8List.fromList(
      img.encodeJpg(decoded, quality: quality.clamp(1, 100)),
    );
  }
}
