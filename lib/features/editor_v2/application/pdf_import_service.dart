// editor_v2——PdfImportService（批次 F-4——2026-08-21，pdfx→pdfrx 迁移）。
//
// PDF 导入服务（pdfrx 渲染 + 多页背景——批次 F-4 方案已就绪）。
// 用户选文件 → pdfrx 读取 PDF → 每页渲染为图片 → 作为 ImageItem 添加到
// PageV2（背景层）。
// 纯 Dart 逻辑（可独立测试——不搞崩）。
// 注意：不 import dart:io（V-006 架构边界——UI/app 层不得直接访问文件）。
// pdfrx PdfDocument.openFile 内部处理文件 I/O。
library;

import 'package:editor_core/editor_core.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF 导入服务（批次 F-4——pdfrx 渲染 + 多页背景）。
class PdfImportService {
  /// 预检（页数/大小限制——安全）。
  /// 注意：不使用 dart:io File（V-006 架构边界）。
  /// 直接让 pdfrx 尝试打开——失败则返回 false。
  static Future<bool> preflight(String filePath,
      {int maxPages = 100}) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(filePath);
      final pageCount = doc.pages.length;
      return pageCount <= maxPages;
    } catch (_) {
      return false;
    } finally {
      doc?.dispose();
    }
  }

  /// 导入 PDF（返回多页 PageV2 列表——每页含图片背景）。
  static Future<List<PageV2>> importPdf(String filePath) async {
    final doc = await PdfDocument.openFile(filePath);
    final pages = <PageV2>[];

    try {
      for (var i = 0; i < doc.pages.length; i++) {
        final initialPage = doc.pages[i];
        final page = await initialPage.ensureLoaded();

        final longest = page.width > page.height ? page.width : page.height;
        final scale = (360 / longest).clamp(1.0, 3.0);
        final targetWidth = (page.width * scale).round().clamp(1, 360);
        final targetHeight = (page.height * scale).round().clamp(1, 360);

        final image = await page.render(
          fullWidth: targetWidth.toDouble(),
          fullHeight: targetHeight.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );

        if (image != null) {
          try {
            final imageId =
                'pdf-${DateTime.now().millisecondsSinceEpoch}-$i';
            final imageItem = ImageItem(
              id: imageId,
              mediaId: '$imageId.png',
              x: 0,
              y: 0,
              width: page.width,
              height: page.height,
            );
            pages.add(PageV2(
              id: 'page-$imageId',
              index: i,
              document: DocumentV2(
                id: 'doc-$imageId',
                pageCount: 1,
                layers: [
                  LayerV2(
                    id: 'layer-$imageId',
                    name: 'Background',
                    images: [imageItem],
                  ),
                ],
              ),
            ));
          } finally {
            image.dispose();
          }
        }
      }
    } finally {
      doc.dispose();
    }

    return pages;
  }

}
