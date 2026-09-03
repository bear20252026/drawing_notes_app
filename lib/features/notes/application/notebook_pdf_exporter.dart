import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart' show Stroke;
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/core/storage/vfs/vault_service.dart';
import 'package:drawing_notes_app/features/drawing/rendering/pdf_hybrid_exporter.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/rendering/notebook_page_canvas_painter.dart';

/// 整本/多页导出的单页数据（与 [NotebookPage] 解耦的最小结构——
/// 笔记本整本与编辑器多会话共用同一管线，drawing 侧只需按此结构供数，
/// 不触碰 notes 聚合根）。
class NotebookPrintPageData {
  const NotebookPrintPageData({
    required this.id,
    required this.title,
    required this.document,
    required this.textItems,
    required this.imageItems,
    required this.shapes,
  });

  final String id;
  final String title;
  final DrawingDocument document;
  final List<PageTextItem> textItems;
  final List<PageImageItem> imageItems;
  final List<PageShapeItem> shapes;
}

/// 分页画布整本多页 PDF 导出（W2 核心能力）。
///
/// 每个画布页对应 PDF 一页（页面尺寸 = 画布逻辑尺寸），整本合成单个
/// PDF 文件——对齐用户定义的「分页画布 = 一本多页画册 / PDF 文档」。
///
/// 渲染管线与编辑器单页导出一致（单一事实来源）：
/// - 光栅层：[NotebookPageCanvasPainter] 离屏 PictureRecorder 渲染
///   （背景 + 高亮/铅笔/图片/形状/文字，排除钢笔笔画）；
/// - 矢量层：钢笔笔画经 [PdfHybridExporter] 转 SVG path 写入，缩放清晰。
///
/// 二级面板泛化：[exportPages] 接受任意页数据（笔记本整本 / 编辑器多会话），
/// 与 [exportNotebook] 同一管线（零重复实现）。
class NotebookPdfExporter {
  const NotebookPdfExporter._();

  /// 导出整本为多页 PDF 字节（既有行为：页尺寸 = 画布逻辑尺寸）。
  static Future<Uint8List> exportNotebook(
    Notebook notebook, {
    int? jpegQuality,
  }) =>
      exportPages(
        [
          for (final page in notebook.pages)
            NotebookPrintPageData(
              id: page.id,
              title: page.title,
              document: page.document,
              textItems: page.textItems,
              imageItems: page.imageItems,
              shapes: page.shapes,
            ),
        ],
        jpegQuality: jpegQuality,
      );

  /// 导出给定页数据为多页 PDF 字节（[jpegQuality] 透传 hybrid 引擎）。
  static Future<Uint8List> exportPages(
    List<NotebookPrintPageData> pages, {
    int? jpegQuality,
  }) async {
    final inputs = <PdfPageInput>[];
    for (final page in pages) {
      final doc = page.document;
      final width = doc.width.toDouble();
      final height = doc.height.toDouble();
      if (width <= 0 || height <= 0) continue;

      // 光栅层：离屏渲染整页内容（排除钢笔笔画，走矢量通道）。
      // 画家要 NotebookPage：用数据现场组装轻量页（仅 paintContent 通道，
      // 不进存储/历史——createdAt/updatedAt 取默认值无影响）。
      ui.Image? rendered;
      try {
        final paintPage = NotebookPage(
          id: page.id,
          title: page.title,
          document: page.document,
          textItems: page.textItems,
          imageItems: page.imageItems,
          shapes: page.shapes,
        );
        final images = await _decodePageImages(page.imageItems);
        final painter = NotebookPageCanvasPainter(
          page: paintPage,
          images: images,
          excludePenStrokes: true,
        );
        final recorder = ui.PictureRecorder();
        painter.paintContent(ui.Canvas(recorder), ui.Size(width, height));
        final picture = recorder.endRecording();
        try {
          rendered = await picture.toImage(
            width.round().clamp(1, 8192),
            height.round().clamp(1, 8192),
          );
        } finally {
          picture.dispose();
        }
      } catch (_) {
        rendered = null;
      }
      if (rendered == null) continue;
      try {
        final pngData = await rendered.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (pngData == null) continue;

        // 矢量层：可见图层的钢笔笔画。
        final vectorStrokes = <Stroke>[
          for (final layer in doc.layers)
            if (layer.visible && layer.opacity > 0)
              for (final stroke in layer.strokes)
                if (!PdfHybridExporter.shouldRasterize(stroke)) stroke,
        ];

        inputs.add(
          PdfPageInput(
            bounds: ui.Rect.fromLTWH(0, 0, width, height),
            rasterPng: pngData.buffer.asUint8List(),
            vectorStrokes: vectorStrokes,
            jpegQuality: jpegQuality,
          ),
        );
      } finally {
        rendered.dispose();
      }
    }
    return PdfHybridExporter.exportMultiPage(pages: inputs);
  }

  /// 预解码页面图片（与 EncryptedFileImage 三级嗅探同一解密管线）：
  /// VFS 对象 → VaultService；DNV 信封 → 保险库解密；DAN/明文 → 媒体解密。
  /// 单图失败不阻断整本导出（该图退化为渲染器内置占位块）。
  static Future<Map<String, ui.Image>> _decodePageImages(
    List<PageImageItem> items,
  ) async {
    final images = <String, ui.Image>{};
    for (final item in items) {
      final path = item.filePath;
      if (path.isEmpty || images.containsKey(path)) continue;
      try {
        final Uint8List clear;
        if (path.startsWith('vfs:')) {
          clear = await VaultService.instance.getObject(path.substring(4));
        } else {
          final bytes = await File(path).readAsBytes();
          clear = VaultFileCodec.isEncrypted(bytes)
              ? await VaultFileCodec.readImageBytes(File(path))
              : await MediaCryptoService.instance.readMediaFile(bytes);
        }
        if (clear.isEmpty) continue;
        final codec = await ui.instantiateImageCodec(clear);
        final frame = await codec.getNextFrame();
        images[path] = frame.image;
      } catch (_) {
        // 解码失败：留空 → 渲染器画占位块。
      }
    }
    return images;
  }
}
