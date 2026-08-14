import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/storage/pdf_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pngHeader = <int>[137, 80, 78, 71, 13, 10, 26, 10];

  test('PDF 导入会将每一页持久化为可供批注的 PNG 底图', () async {
    final temp = await Directory.systemTemp.createTemp('pdf_import_test_');
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}${Platform.pathSeparator}source.pdf');
    await source.writeAsBytes(const [37, 80, 68, 70, 45], flush: true);
    final output = Directory('${temp.path}${Platform.pathSeparator}pages');

    final pages = await PdfImportService.renderPages(
      sourcePath: source.path,
      outputDirectory: output,
      importId: 'pdf_test',
      maxRenderSide: 512,
      rasterizer: (_, _) async => [
        RenderedPdfPage(
          pageNumber: 1,
          pngBytes: Uint8List.fromList(pngHeader),
          width: 362,
          height: 512,
        ),
        RenderedPdfPage(
          pageNumber: 2,
          pngBytes: Uint8List.fromList(pngHeader),
          width: 362,
          height: 512,
        ),
      ],
    );

    expect(pages, hasLength(2));
    expect(pages.map((page) => page.pageNumber), [1, 2]);
    for (final page in pages) {
      expect(page.width, 362);
      expect(page.height, 512);
      final bytes = await File(page.filePath).readAsBytes();
      expect(bytes, orderedEquals(pngHeader));
    }
  });

  test('PDF 导入拒绝非 PDF 路径，不调用渲染后端', () async {
    final temp = await Directory.systemTemp.createTemp('pdf_import_invalid_');
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}${Platform.pathSeparator}source.txt');
    await source.writeAsString('not a pdf');

    await expectLater(
      PdfImportService.renderPages(
        sourcePath: source.path,
        outputDirectory: temp,
        importId: 'invalid',
        rasterizer: (_, _) => throw StateError('不应调用'),
      ),
      throwsArgumentError,
    );
  });
}
