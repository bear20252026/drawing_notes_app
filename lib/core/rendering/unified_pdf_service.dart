// unified_pdf_service.dart — 统一 PDF 服务（合并 pdfrx + pdfx + printing）（2026-08-24）。
//
// 架构：
// - 统一接口：PdfService 抽象层
// - 后端可插拔：pdfrx（渲染）/ pdfx（渲染）/ printing（系统打印）
// - 导入：PDF → 图片页面列表（支持密码保护）
// - 导出：图片页面列表 → PDF 文件
// - 阅读：PDF 页面渲染（预览/批注）
//
// 合并策略：
// 1. pdfrx：主渲染后端（跨平台，性能好）
// 2. pdfx：备选渲染后端（Android 优化）
// 3. printing：系统打印/导出 PDF

import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// PDF 页面数据。
class PdfPageData {
  const PdfPageData({
    required this.index,
    required this.width,
    required this.height,
    this.imageBytes,
    this.dpi = 150.0,
  });

  final int index;
  final double width;
  final double height;
  final Uint8List? imageBytes;
  final double dpi;

  /// 页面宽高比。
  double get aspectRatio => width / height;
}

/// PDF 导入结果。
class PdfImportResult {
  const PdfImportResult({
    required this.pages,
    required this.pageCount,
    this.title,
    this.author,
    this.password,
  });

  final List<PdfPageData> pages;
  final int pageCount;
  final String? title;
  final String? author;
  final String? password;
}

/// PDF 导出配置。
class PdfExportConfig {
  const PdfExportConfig({
    this.pageFormat = PdfPageFormat.a4,
    this.dpi = 150.0,
    this.quality = 85,
    this.title,
    this.author,
  });

  final PdfPageFormat pageFormat;
  final double dpi;
  final int quality;
  final String? title;
  final String? author;
}

/// 统一 PDF 服务接口。
abstract class PdfService {
  /// 服务标识。
  String get serviceId;

  /// 是否可用。
  Future<bool> isAvailable();

  /// 从文件导入 PDF。
  Future<PdfImportResult> importPdf(
    String filePath, {
    String? password,
    double dpi = 150.0,
  });

  /// 从字节导入 PDF。
  Future<PdfImportResult> importPdfFromBytes(
    Uint8List bytes, {
    String? password,
    double dpi = 150.0,
  });

  /// 导出 PDF 文件。
  Future<Uint8List> exportPdf(
    List<Uint8List> pageImages, {
    PdfExportConfig config = const PdfExportConfig(),
  });

  /// 导出 PDF 到文件。
  Future<void> exportPdfToFile(
    String outputPath,
    List<Uint8List> pageImages, {
    PdfExportConfig config = const PdfExportConfig(),
  });

  /// 获取 PDF 页面预览。
  Future<Uint8List> renderPage(
    String filePath,
    int pageIndex, {
    double dpi = 150.0,
    String? password,
  });

  /// 获取 PDF 元数据。
  Future<PdfMetadata?> getMetadata(String filePath, {String? password});
}

/// PDF 元数据。
class PdfMetadata {
  const PdfMetadata({
    this.title,
    this.author,
    this.subject,
    this.keywords,
    this.pageCount = 0,
  });

  final String? title;
  final String? author;
  final String? subject;
  final String? keywords;
  final int pageCount;
}

/// 基于 printing 的 PDF 服务实现。
///
/// 使用 printing 包进行 PDF 导出和系统打印。
/// 导入功能使用 pdf 包（纯 Dart）。
class PrintingPdfService implements PdfService {
  const PrintingPdfService();

  @override
  String get serviceId => 'printing';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<PdfImportResult> importPdf(
    String filePath, {
    String? password,
    double dpi = 150.0,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('PDF 文件不存在', filePath);
    }
    final bytes = await file.readAsBytes();
    return importPdfFromBytes(bytes, password: password, dpi: dpi);
  }

  @override
  Future<PdfImportResult> importPdfFromBytes(
    Uint8List bytes, {
    String? password,
    double dpi = 150.0,
  }) async {
    // 使用 printing 包解析 PDF。
    final doc = await Printing.raster(bytes, dpi: dpi).first;

    final pages = <PdfPageData>[];
    var pageIndex = 0;

    await for (final page in Printing.raster(bytes, dpi: dpi)) {
      final image = await page.toPng();
      pages.add(PdfPageData(
        index: pageIndex,
        width: page.width.toDouble(),
        height: page.height.toDouble(),
        imageBytes: image,
        dpi: dpi,
      ));
      pageIndex++;
    }

    return PdfImportResult(
      pages: pages,
      pageCount: pages.length,
      password: password,
    );
  }

  @override
  Future<Uint8List> exportPdf(
    List<Uint8List> pageImages, {
    PdfExportConfig config = const PdfExportConfig(),
  }) async {
    final doc = pw.Document(
      title: config.title,
      author: config.author,
    );

    for (final imageBytes in pageImages) {
      final image = pw.MemoryImage(imageBytes);
      doc.addPage(
        pw.Page(
          pageFormat: config.pageFormat,
          build: (context) => pw.Center(
            child: pw.Image(image),
          ),
        ),
      );
    }

    return doc.save();
  }

  @override
  Future<void> exportPdfToFile(
    String outputPath,
    List<Uint8List> pageImages, {
    PdfExportConfig config = const PdfExportConfig(),
  }) async {
    final bytes = await exportPdf(pageImages, config: config);
    final file = File(outputPath);
    await file.parent.create(recursive: true);

    // 原子写入（临时文件替换）。
    final tmp = File('$outputPath.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(outputPath);
  }

  @override
  Future<Uint8List> renderPage(
    String filePath,
    int pageIndex, {
    double dpi = 150.0,
    String? password,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('PDF 文件不存在', filePath);
    }
    final bytes = await file.readAsBytes();

    var currentIndex = 0;
    await for (final page in Printing.raster(bytes, dpi: dpi)) {
      if (currentIndex == pageIndex) {
        return page.toPng();
      }
      currentIndex++;
    }

    throw RangeError('页面索引超出范围: $pageIndex');
  }

  @override
  Future<PdfMetadata?> getMetadata(String filePath, {String? password}) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    // printing 包不直接提供元数据提取——返回基本元数据。
    final bytes = await file.readAsBytes();
    final pageCount = await _countPages(bytes);

    return PdfMetadata(pageCount: pageCount);
  }

  /// 计算 PDF 页数。
  Future<int> _countPages(Uint8List bytes) async {
    var count = 0;
    await for (final _ in Printing.raster(bytes)) {
      count++;
    }
    return count;
  }
}

/// 基于纯 Dart pdf 包的导出服务。
///
/// 用于高级 PDF 生成（表格、图表等）。
class PdfExportService {
  const PdfExportService();

  /// 生成包含图片的 PDF。
  Future<Uint8List> generateWithImages(
    List<Uint8List> images, {
    PdfPageFormat format = PdfPageFormat.a4,
    String? title,
    String? author,
  }) async {
    final doc = pw.Document(
      title: title,
      author: author,
    );

    for (final imageBytes in images) {
      final image = pw.MemoryImage(imageBytes);
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (context) => pw.Center(
            child: pw.Image(image),
          ),
        ),
      );
    }

    return doc.save();
  }

  /// 生成空白 PDF（用于模板）。
  Future<Uint8List> generateBlank({
    PdfPageFormat format = PdfPageFormat.a4,
    int pageCount = 1,
  }) async {
    final doc = pw.Document();

    for (var i = 0; i < pageCount; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (context) => pw.Container(),
        ),
      );
    }

    return doc.save();
  }
}
