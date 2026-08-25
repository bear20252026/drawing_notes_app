// editor_v2——PdfImportService（批次 F-4——2026-08-21）。
//
// PDF 导入服务（pdfx 渲染 + 多页背景——批次 F-4 方案已就绪）。
// 用户选文件 → pdfx 读取 PDF → 每页渲染为图片 → 作为 ImageItem 添加到
// PageV2（背景层）。
// 纯 Dart 逻辑（可独立测试——不搞崩）。
// 注意：不 import dart:io（V-006 架构边界——UI/app 层不得直接访问文件）。
// pdfx PdfDocument.openFile 内部处理文件 I/O。
library;

import 'package:editor_core/editor_core.dart';
import 'package:pdfx/pdfx.dart';

/// PDF 导入服务（批次 F-4——pdfx 渲染 + 多页背景）。
class PdfImportService {
  /// 预检（页数/大小限制——安全）。
  /// 注意：不使用 dart:io File（V-006 架构边界）。
  /// 直接让 pdfx 尝试打开——失败则返回 false。
  static Future<bool> preflight(String filePath,
      {int maxPages = 100}) async {
    try {
      final doc = await PdfDocument.openFile(filePath);
      final pageCount = doc.pagesCount;
      doc.close();
      return pageCount <= maxPages;
    } catch (_) {
      return false;
    }
  }

  /// 导入 PDF（返回多页 PageV2 列表——每页含图片背景）。
  static Future<List<PageV2>> importPdf(String filePath) async {
    final doc = await PdfDocument.openFile(filePath);
    final pages = <PageV2>[];

    for (var i = 0; i < doc.pagesCount; i++) {
      final page = await doc.getPage(i + 1); // pdfx 页码从 1 开始。
      final pageImage = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.png,
      );

      if (pageImage != null) {
        final imageId = 'pdf-${DateTime.now().millisecondsSinceEpoch}-$i';
        final image = ImageItem(
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
                images: [image],
              ),
            ],
          ),
        ));
      }
      page.close();
    }

    doc.close();
    return pages;
  }
}
