import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import 'package:drawing_notes_app/core/storage/local_id_generator.dart';

/// 已落盘的单个 PDF 页面底图。
///
/// 页面图像保存在应用私有目录；调用方以此创建一张同尺寸的笔记页，并将
/// [filePath] 作为最低层图片元素，从而让墨迹、文本和形状仍使用既有可编辑模型。
class ImportedPdfPage {
  const ImportedPdfPage({
    required this.pageNumber,
    required this.filePath,
    required this.width,
    required this.height,
  });

  final int pageNumber;
  final String filePath;
  final int width;
  final int height;
}

/// PDF 页渲染阶段的内存结果。
///
/// 与 [ImportedPdfPage] 分离，让磁盘写入和 PDFium 渲染可以独立测试；正式运行
/// 始终使用 PDFium 后端，测试可注入一组确定性的 PNG 页面验证持久化闭环。
class RenderedPdfPage {
  const RenderedPdfPage({
    required this.pageNumber,
    required this.pngBytes,
    required this.width,
    required this.height,
  });

  final int pageNumber;
  final Uint8List pngBytes;
  final int width;
  final int height;
}

typedef PdfRasterizer =
    Future<List<RenderedPdfPage>> Function(
      String sourcePath,
      int maxRenderSide,
    );

/// 将本地 PDF 按页渲染为笔记可持久化的 PNG 底图。
///
/// 这是“PDF 资料 + 矢量批注”的导入层：PDF 内容并不被伪装为可编辑笔画，
/// 但每页都会成为独立、可保存和重开的页面背景，用户在其上书写的内容仍由
/// [DrawingDocument] 的矢量图层承载。为避免大页 PDF 造成内存峰值，长边渲染
/// 上限控制在 [maxRenderSide]，同时保持原始比例。
class PdfImportService {
  const PdfImportService._();

  static const int defaultMaxRenderSide = 1800;

  /// 单次导入页数上限（红蓝攻防 D-6 修复 2026-08-15）：
  /// 防恶意多页 PDF 触发 OOM（拒绝服务）。
  static const int _maxImportPages = 500;

  /// H-01 补全（专家审计 2026-08-15）：PDF 源文件大小上限（防超大源文件）。
  static const int _maxSourceBytes = 200 * 1024 * 1024; // 200MB
  /// H-01 补全：导入总 PNG 输出字节预算（防累积输出耗尽磁盘/内存）。
  static const int _maxTotalOutputBytes = 500 * 1024 * 1024; // 500MB

  static Future<List<ImportedPdfPage>> renderPages({
    required String sourcePath,
    required Directory outputDirectory,
    required String importId,
    int maxRenderSide = defaultMaxRenderSide,
    Set<int>? pageNumbers,
    PdfRasterizer? rasterizer,
  }) async {
    if (maxRenderSide < 256) {
      throw ArgumentError.value(
        maxRenderSide,
        'maxRenderSide',
        '渲染边长必须至少为 256',
      );
    }
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('PDF 文件不存在', sourcePath);
    }
    // H-01 补全：源文件大小预检（解析前——防超大 PDF 源资源耗尽）。
    if (await source.length() > _maxSourceBytes) {
      throw StateError('PDF 源文件过大（超过 200MB 限制），拒绝导入');
    }
    if (!sourcePath.toLowerCase().endsWith('.pdf')) {
      throw ArgumentError.value(sourcePath, 'sourcePath', '仅支持导入 .pdf 文件');
    }
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final rendered = await (rasterizer ?? _renderWithPdfium)(
      sourcePath,
      maxRenderSide,
    );
    // D-6 修复：页数上限，防恶意多页 PDF 耗尽内存。
    if (rendered.length > _maxImportPages) {
      throw StateError('PDF 页数超过 $_maxImportPages 页限制，拒绝导入');
    }
    final results = <ImportedPdfPage>[];
    // H-01 补全：累积 PNG 输出字节预算（防多页累积耗尽磁盘/内存）。
    var totalOutputBytes = 0;
    try {
      for (final page in rendered) {
        // 页范围选择（本地化适配 2026-08-15）：pageNumbers 为空表示导入全部页。
        if (pageNumbers != null && !pageNumbers.contains(page.pageNumber)) {
          continue;
        }
        if (page.width <= 0 || page.height <= 0 || page.pngBytes.isEmpty) {
          throw StateError('PDF 第 ${page.pageNumber} 页渲染结果无效');
        }
        totalOutputBytes += page.pngBytes.length;
        if (totalOutputBytes > _maxTotalOutputBytes) {
          throw StateError('PDF 导入输出总量超限（超过 500MB），拒绝继续');
        }
        final filename =
            '${importId}_pdf_${page.pageNumber}_${LocalIdGenerator.next('page')}.png';
        final destination = File(
          '${outputDirectory.path}${Platform.pathSeparator}$filename',
        );
        await destination.writeAsBytes(page.pngBytes, flush: true);
        results.add(
          ImportedPdfPage(
            pageNumber: page.pageNumber,
            filePath: destination.path,
            width: page.width,
            height: page.height,
          ),
        );
      }
    } catch (_) {
      // 失败时清理本次已经生成的页面，避免留下半导入资源。
      for (final result in results) {
        try {
          await File(result.filePath).delete();
        } catch (_) {
          // 清理失败不覆盖原始导入异常。
        }
      }
      rethrow;
    }
    return List<ImportedPdfPage>.unmodifiable(results);
  }

  static Future<List<RenderedPdfPage>> _renderWithPdfium(
    String sourcePath,
    int maxRenderSide,
  ) async {
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(sourcePath);
    // 链 B 修复（军工审计 2026-08-15）：页数渲染前预检——D-6 原检查在
    // 渲染完成后才执行，恶意数千页 PDF 会先被完整渲染（内存 OOM）再
    // 被拒绝（等于没有上限）。
    if (document.pages.length > _maxImportPages) {
      throw StateError('PDF 页数超过 $_maxImportPages 页限制，拒绝导入');
    }
    final results = <RenderedPdfPage>[];
    for (final initialPage in document.pages) {
      final page = await initialPage.ensureLoaded();
      final longest = page.width > page.height ? page.width : page.height;
      final scale = (maxRenderSide / longest).clamp(1.0, 2.0);
      final targetWidth = (page.width * scale).round().clamp(1, maxRenderSide);
      final targetHeight = (page.height * scale).round().clamp(
        1,
        maxRenderSide,
      );
      final image = await page.render(
        fullWidth: targetWidth.toDouble(),
        fullHeight: targetHeight.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (image == null) {
        throw StateError('无法渲染 PDF 第 ${page.pageNumber} 页');
      }
      try {
        results.add(
          RenderedPdfPage(
            pageNumber: page.pageNumber,
            pngBytes: await _encodePng(image),
            width: image.width,
            height: image.height,
          ),
        );
      } finally {
        image.dispose();
      }
    }
    return results;
  }

  static Future<Uint8List> _encodePng(PdfImage source) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      source.pixels,
      source.width,
      source.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
      rowBytes: source.width * 4,
    );
    final image = await completer.future;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('无法编码 PDF 页面 PNG');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
