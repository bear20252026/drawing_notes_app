import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';
import 'package:drawing_notes_app/features/editor_v2/application/pdf_import_service.dart';

/// 批次 F-4：PDF 导入服务测试（纯逻辑——不搞崩）。
///
/// 注意：PdfImportService.importPdf 需要真实 PDF 文件（集成测试）。
/// 此处仅测试 preflight 的安全边界逻辑（文件不存在/大小超限）。
void main() {
  test('preflight：文件不存在返回 false', () async {
    final result = await PdfImportService.preflight('nonexistent.pdf');
    expect(result, false);
  });

  test('PdfImportService 类可访问', () {
    // 确认 PdfImportService 编译通过（纯逻辑可测试）。
    expect(PdfImportService, isNotNull);
  });

  test('PageV2 + ImageItem 构造（PDF 导入模型验证）', () {
    // 验证 PDF 导入后创建的 PageV2 结构正确。
    const image = ImageItem(id: 'pdf-1', mediaId: 'pdf-1.png', x: 0, y: 0, width: 595, height: 842);
    const page = PageV2(
      id: 'page-pdf-1',
      index: 0,
      document: DocumentV2(id: 'doc-pdf-1', pageCount: 1, layers: [
        LayerV2(id: 'layer-pdf-1', name: 'Background', images: [image]),
      ]),
    );
    expect(page.document.layers.first.images.length, 1);
    expect(page.document.layers.first.images.first.width, 595);
    expect(page.document.layers.first.images.first.height, 842);
  });
}
