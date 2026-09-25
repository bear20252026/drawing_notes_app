import 'dart:isolate';
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
    ui.Rect? contentRect,
  }) => exportMultiPage(
    pages: [
      PdfPageInput(
        bounds: bounds,
        rasterPng: rasterPng,
        vectorStrokes: vectorStrokes,
        background: background,
        jpegQuality: jpegQuality,
        contentRect: contentRect,
      ),
    ],
  );

  /// 生成多页混合 PDF（W2 整本导出：每个画布页对应 PDF 一页）。
  ///
  /// `doc.save()` 是纯 Dart CPU 密集段（大位图页上秒级），在 UI 线程执行
  /// 会冻结交互（v1.17.17 用户反馈导出卡顿）——移入 [Isolate.run]：
  /// PdfPageInput 全为可跨 isolate 发送类型（Uint8List / ui.Rect /
  /// ui.Color / int?），pdf 包为纯 Dart 实现，无平台通道。
  static Future<Uint8List> exportMultiPage({
    required List<PdfPageInput> pages,
  }) {
    return Isolate.run(() {
      final doc = pw.Document();
      for (final page in pages) {
        doc.addPage(page._buildPdfPage());
      }
      return doc.save();
    });
  }

  /// 将 PNG 字节转 JPEG（[quality] 1-100，越高质量越高体积越大）。
  ///
  /// 用纯 Dart image 包编码（dart:ui 的 ImageByteFormat 不支持 JPEG 输出）；
  /// 解码失败时回退原字节，保证导出永不因压缩失败中断。
  /// 公开供笔记本单页墨迹层复用（同压缩口径）。
  static Uint8List encodeJpeg(Uint8List pngBytes, int quality) {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) return pngBytes;
    return Uint8List.fromList(
      img.encodeJpg(decoded, quality: quality.clamp(1, 100)),
    );
  }
}

/// 混合 PDF 的单页输入（矢量 + 光栅混合导出的页级数据）。
class PdfPageInput {
  const PdfPageInput({
    required this.bounds,
    required this.rasterPng,
    required this.vectorStrokes,
    this.background = const ui.Color(0xFFFFFFFF),
    this.jpegQuality,
    this.contentRect,
    this.footerText,
  });

  /// 页面导出区域（决定 PDF 页面尺寸；topLeft 为内容坐标系原点偏移）。
  final ui.Rect bounds;

  /// 光栅层位图（背景 + 高亮/铅笔/图片/形状/文字）。
  final Uint8List rasterPng;

  /// 以矢量写入的钢笔笔画。
  final List<Stroke> vectorStrokes;

  final ui.Color background;

  /// 可选 JPEG 压缩质量（1-100）；null = PNG 无损。
  final int? jpegQuality;

  /// 内容在页面中的放置矩形（纸张模式信纸居中；null = 全页填充既有行为）。
  ///
  /// 二级面板纸张档位用：调用方预先把光栅渲染到该矩形尺寸、把矢量笔画
  /// 变换到纸张坐标，引擎只负责按矩形放置（`bounds` 恒为整页尺寸）。
  final ui.Rect? contentRect;

  /// 页脚文本（v1.17.22，如「标题 · 3 / 12」）；null = 无页脚（既有行为）。
  final String? footerText;

  pw.Page _buildPdfPage() {
    final pdfBackground = PdfColor.fromInt(background.toARGB32());
    final offset = ui.Offset(-bounds.left, -bounds.top);
    final quality = jpegQuality;
    final rasterBytes = quality == null
        ? rasterPng
        : PdfHybridExporter.encodeJpeg(rasterPng, quality);
    final footer = footerText;

    return pw.Page(
      pageFormat: PdfPageFormat(bounds.width, bounds.height),
      margin: pw.EdgeInsets.zero,
      // 页脚（v1.17.22）：pdf 3.x 的 pw.Page 没有 footer 回调（那是
      // MultiPage 的能力），故在 build 内用 Column 收尾——Expanded 装既有
      // Stack（margin 为零，Stack 原点=页原点，contentRect/矢量坐标几何
      // 语义不变），页脚占底部定高条，与光栅/矢量内容互不重叠。
      build: (context) => pw.Column(
        children: [
          pw.Expanded(
            child: _buildContentStack(rasterBytes, offset, pdfBackground),
          ),
          if (footer != null)
            pw.Container(
              height: 18,
              alignment: pw.Alignment.bottomCenter,
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Text(
                footer,
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColor(0.45, 0.45, 0.45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildContentStack(
    Uint8List rasterBytes,
    ui.Offset offset,
    PdfColor pdfBackground,
  ) {
    final placement = contentRect;
    return pw.Stack(
      children: [
        if (placement == null)
          pw.Positioned.fill(
            child: pw.Image(pw.MemoryImage(rasterBytes), fit: pw.BoxFit.fill),
          )
        else
          // pw.Positioned 无 width/height 具名参数——用 Container 定尺寸
          // 再定位（pdf 4.x API 实测口径，以云 analyze 为准）。
          pw.Positioned(
            left: placement.left,
            top: placement.top,
            child: pw.Container(
              width: placement.width,
              height: placement.height,
              child: pw.Image(pw.MemoryImage(rasterBytes), fit: pw.BoxFit.fill),
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
              final color = PdfColor.fromInt(
                stroke.color.toARGB32(),
              ).flatten(background: pdfBackground);
              graphics.setFillColor(color);
              graphics.drawShape(svgPath);
              graphics.fillPath();
            }
          },
        ),
      ],
    );
  }
}
