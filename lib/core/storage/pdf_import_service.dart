import 'dart:async';
import 'dart:io';
import 'dart:isolate';
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

/// Isolate 渲染消息：主线程 → 后台 Isolate。
class _IsolateRenderMessage {
  _IsolateRenderMessage({
    required this.sourcePath,
    required this.maxRenderSide,
    required this.progressPort,
  });

  final String sourcePath;
  final int maxRenderSide;
  final SendPort progressPort;
}

/// 后台 Isolate 渲染结果：后台 Isolate → 主线程。
class _IsolateRenderResult {
  _IsolateRenderResult({
    required this.pages,
    required this.totalPageCount,
  });

  final List<RenderedPdfPage> pages;
  final int totalPageCount;
}

/// 后台 Isolate 入口函数（顶层函数，Isolate 无法访问闭包）。
///
/// 负责执行 PDFium 渲染并将结果返回主线程。通过 [SendPort] 实时报告
/// 渲染进度（当前页码, 总页数），让 UI 层可以展示进度条。
Future<_IsolateRenderResult> _renderPdfInIsolate(
  _IsolateRenderMessage message,
) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openFile(message.sourcePath);
  final totalPages = document.pages.length;

  // 通过 SendPort 向主线程报告总页数。
  message.progressPort.send(_IsolateProgress(totalPages: totalPages));

  final results = <RenderedPdfPage>[];
  for (var i = 0; i < document.pages.length; i++) {
    final initialPage = document.pages[i];
    final page = await initialPage.ensureLoaded().timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException(
            'PDF 页面加载超时（30秒），可能文件已损坏',
          ),
        );
    final longest = page.width > page.height ? page.width : page.height;
    final scale =
        (message.maxRenderSide / longest).clamp(1.0, 2.0);
    final targetWidth =
        (page.width * scale).round().clamp(1, message.maxRenderSide);
    final targetHeight =
        (page.height * scale).round().clamp(1, message.maxRenderSide);
    final image = await page.render(
      fullWidth: targetWidth.toDouble(),
      fullHeight: targetHeight.toDouble(),
      backgroundColor: 0xFFFFFFFF,
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'PDF 页面渲染超时（30秒），可能页面过大或已损坏',
      ),
    );
    if (image == null) {
      throw StateError('无法渲染 PDF 第 ${initialPage.pageNumber} 页');
    }
    try {
      results.add(
        RenderedPdfPage(
          pageNumber: initialPage.pageNumber,
          pngBytes: await _encodePngInIsolate(image),
          width: image.width,
          height: image.height,
        ),
      );
    } finally {
      image.dispose();
    }

    // 向主线程报告当前页码（i+1 从 1 开始）。
    message.progressPort.send(_IsolateProgress(
      totalPages: totalPages,
      currentPage: i + 1,
    ));
  }

  // 发送最终完成信号。
  message.progressPort.send(_IsolateProgress(
    totalPages: totalPages,
    currentPage: totalPages,
    done: true,
  ));

  return _IsolateRenderResult(
    pages: results,
    totalPageCount: totalPages,
  );
}

/// Isolate 内的进度消息。
class _IsolateProgress {
  _IsolateProgress({
    required this.totalPages,
    this.currentPage = 0,
    this.done = false,
  });

  final int totalPages;
  final int currentPage;
  final bool done;
}

/// Isolate 内的 PNG 编码（使用 dart:ui decodeImageFromPixels）。
Future<Uint8List> _encodePngInIsolate(PdfImage source) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    source.pixels,
    source.width,
    source.height,
    ui.PixelFormat.bgra8888,
    completer.complete,
    rowBytes: source.width * 4,
  );
  final image = await completer.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException(
      'PDF 页面 PNG 编码超时（30秒），可能页面过大或已损坏',
    ),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('无法编码 PDF 页面 PNG');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Isolate 入口函数（顶层函数），负责渲染并将结果发送回主线程。
Future<void> _renderPdfEntry(
  _IsolateRenderMessage message,
) async {
  final result = await _renderPdfInIsolate(message);
  message.progressPort.send(result);
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

  /// 整体渲染超时（秒），防止多页 PDF 累积阻塞。
  static const int _totalRenderTimeoutSeconds = 300;

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
    void Function(int current, int total)? onProgress,
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

    late final List<RenderedPdfPage> rendered;
    if (rasterizer != null) {
      // 测试注入的 rasterizer：直接调用，无需 Isolate。
      rendered = await rasterizer(
        sourcePath,
        maxRenderSide,
      ).timeout(
        Duration(seconds: _totalRenderTimeoutSeconds),
        onTimeout: () => throw TimeoutException(
          'PDF 渲染超时（$_totalRenderTimeoutSeconds秒），文件可能过大或已损坏',
        ),
      );
    } else {
      // 正式运行：PDFium 渲染迁移到后台 Isolate，不阻塞 UI 线程。
      rendered = await _renderViaIsolate(
        sourcePath,
        maxRenderSide,
        onProgress,
      );
    }
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

  /// 通过后台 Isolate 执行 PDF 渲染，避免阻塞 UI 线程。
  ///
  /// 渲染进度通过 [onProgress] 回调实时反馈。Isolate 内部通过 [SendPort]
  /// 向主线程发送 [_IsolateProgress] 消息，主线程监听后转发给回调。
  static Future<List<RenderedPdfPage>> _renderViaIsolate(
    String sourcePath,
    int maxRenderSide,
    void Function(int current, int total)? onProgress,
  ) async {
    final receivePort = ReceivePort();
    final message = _IsolateRenderMessage(
      sourcePath: sourcePath,
      maxRenderSide: maxRenderSide,
      progressPort: receivePort.sendPort,
    );

    final isolate = await Isolate.spawn(
      _renderPdfEntry,
      message,
      onError: receivePort.sendPort,
      onExit: receivePort.sendPort,
    );

    final completer = Completer<List<RenderedPdfPage>>();

    // 单一监听器：处理进度消息、渲染结果、错误和 Isolate 退出。
    receivePort.listen(
      (message) {
        if (message is _IsolateProgress) {
          if (onProgress != null && message.totalPages > 0) {
            onProgress(message.currentPage, message.totalPages);
          }
        } else if (message is _IsolateRenderResult && !completer.isCompleted) {
          completer.complete(message.pages);
        } else if (message is Error && !completer.isCompleted) {
          completer.completeError(StateError('PDF 渲染 Isolate 错误: ${message.stackTrace}'));
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('PDF 渲染 Isolate 意外退出'),
          );
        }
      },
    );

    return completer.future.timeout(
      Duration(seconds: _totalRenderTimeoutSeconds),
      onTimeout: () {
        receivePort.close();
        isolate.kill(priority: Isolate.immediate);
        throw TimeoutException(
          'PDF 渲染超时（$_totalRenderTimeoutSeconds秒），文件可能过大或已损坏',
        );
      },
    );
  }
}
