// 由 Claude 团队生成 | Drawing Notes App
// PDF 首页内存渲染器：把本地 PDF 渲成内存里的一张 PNG（附件内嵌预览用）。
//
// 定位：core 中立能力，无 feature 依赖。生产默认走 pdfrx/PDFium；测试与组合根可
// 注入轻量实现（纯 Dart 环境下不应加载 pdfrx 原生库）。对外只暴露一个无 UI 的
// renderPage(...) 门面 + 一份 [PdfPreviewPage] 数据；不碰存储、不碰 UI。

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// 单页渲染结果（内存 PNG 字节 + 像素尺寸）。
@immutable
class PdfPreviewPage {
  const PdfPreviewPage({
    required this.pngBytes,
    required this.width,
    required this.height,
  });

  final Uint8List pngBytes;
  final double width;
  final double height;
}

/// 把 PDF 单页渲染为内存 PNG 的无 UI 门面。
///
/// - 生产默认用 [PdfiumPreviewRenderer]（pdfrx/PDFium）。
/// - 测试/组合根可注入轻量实现，避免在纯 dart/widget 测试里加载原生库。
abstract class PdfPreviewRenderer {
  /// 渲染 [filePath] 的第 [pageNumber] 页（1 起），最长边不超过 [maxWidth]。
  /// 无法渲染（文件不存在/非 PDF/加密/path 为空）一律返回 null（上层回退卡片）。
  Future<PdfPreviewPage?> renderPage(
    String filePath, {
    int pageNumber = 1,
    double maxWidth = 320,
  });
}

/// 默认实现：基于 pdfrx（PDFium）。任何异常都吞掉并返回 null。
class PdfiumPreviewRenderer implements PdfPreviewRenderer {
  const PdfiumPreviewRenderer();

  @override
  Future<PdfPreviewPage?> renderPage(
    String filePath, {
    int pageNumber = 1,
    double maxWidth = 320,
  }) async {
    if (filePath.isEmpty) return null;
    try {
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openFile(filePath);
      try {
        if (document.pages.isEmpty) return null;
        final index = (pageNumber - 1).clamp(0, document.pages.length - 1);
        final page = await document.pages[index].ensureLoaded();
        final w = page.width.toDouble();
        final h = page.height.toDouble();
        if (w <= 0 || h <= 0) return null;
        // 以最长边为基准计算缩放，避免超大页把内存撑爆。
        var scale = 1.0;
        final longest = w > h ? w : h;
        if (maxWidth > 0 && longest > maxWidth) scale = maxWidth / longest;
        final targetW = (w * scale).round().clamp(1, 1 << 15);
        final targetH = (h * scale).round().clamp(1, 1 << 15);
        final image = await page.render(
          fullWidth: targetW.toDouble(),
          fullHeight: targetH.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );
        if (image == null) return null;
        try {
          final png = await _encodePng(image);
          return PdfPreviewPage(
            pngBytes: png,
            width: image.width.toDouble(),
            height: image.height.toDouble(),
          );
        } finally {
          image.dispose();
        }
      } finally {
        document.dispose();
      }
    } catch (_) {
      // 任何失败（缺文件/非 PDF/原生未初始化）都回退，不影响卡片布局。
      return null;
    }
  }

  /// bgra8888 像素 → PNG 字节。
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
      if (data == null) {
        throw StateError('无法编码 PDF 页面 PNG');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
