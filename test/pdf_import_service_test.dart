import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/storage/pdf_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/temp_dir_cleanup.dart';

void main() {
  const pngHeader = <int>[137, 80, 78, 71, 13, 10, 26, 10];

  test('PDF 导入会将每一页持久化为可供批注的 PNG 底图', () async {
    final temp = await Directory.systemTemp.createTemp('pdf_import_test_');
    addTearDown(() => deleteTempDirWithRetry(temp));
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

  test('页范围选择：pageNumbers 仅导入指定页（本地化适配）', () async {
    final temp = await Directory.systemTemp.createTemp('pdf_range_test_');
    addTearDown(() => deleteTempDirWithRetry(temp));
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}${Platform.pathSeparator}source.pdf');
    await source.writeAsBytes(const [37, 80, 68, 70, 45], flush: true);
    final output = Directory('${temp.path}${Platform.pathSeparator}pages');

    final pages = await PdfImportService.renderPages(
      sourcePath: source.path,
      outputDirectory: output,
      importId: 'pdf_range',
      maxRenderSide: 512,
      pageNumbers: {1},
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

    expect(pages, hasLength(1), reason: 'pageNumbers={1} 只导入第 1 页');
    expect(pages.single.pageNumber, 1);
    expect(pages.single.width, 362);
  });

  test('PDF 导入拒绝非 PDF 路径，不调用渲染后端', () async {
    final temp = await Directory.systemTemp.createTemp('pdf_import_invalid_');
    addTearDown(() => deleteTempDirWithRetry(temp));
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

  test('S-01：注入密封回调时页面 PNG 以密文落盘（不再明文残留）', () async {
    final temp = await Directory.systemTemp.createTemp('pdf_seal_test_');
    addTearDown(() => deleteTempDirWithRetry(temp));
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}${Platform.pathSeparator}source.pdf');
    await source.writeAsBytes(const [37, 80, 68, 70, 45], flush: true);
    final output = Directory('${temp.path}${Platform.pathSeparator}pages');

    const marker = <int>[1, 2, 3, 4];
    final pages = await PdfImportService.renderPages(
      sourcePath: source.path,
      outputDirectory: output,
      importId: 'pdf_seal',
      maxRenderSide: 512,
      rasterizer: (_, _) async => [
        RenderedPdfPage(
          pageNumber: 1,
          pngBytes: Uint8List.fromList(pngHeader),
          width: 362,
          height: 512,
        ),
      ],
      sealBytes: (destinationPath, bytes) async {
        expect(destinationPath, contains('pdf_seal'));
        // 模拟信封加密：真实实现为 VaultFileCodec / DAN 加密。
        return Uint8List.fromList([...marker, ...bytes]);
      },
    );

    expect(pages, hasLength(1));
    final stored = await File(pages.single.filePath).readAsBytes();
    // 落盘内容是密封结果而非明文 PNG。
    expect(stored, orderedEquals([...marker, ...pngHeader]));
    // R-11：无 tmp 半成品残留。
    final leftovers = output
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tmp'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('R-11：未注入密封回调时保持明文落盘（未加密模式兼容）', () async {
    final temp = await Directory.systemTemp.createTemp('pdf_plain_test_');
    addTearDown(() => deleteTempDirWithRetry(temp));
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}${Platform.pathSeparator}source.pdf');
    await source.writeAsBytes(const [37, 80, 68, 70, 45], flush: true);
    final output = Directory('${temp.path}${Platform.pathSeparator}pages');

    final pages = await PdfImportService.renderPages(
      sourcePath: source.path,
      outputDirectory: output,
      importId: 'pdf_plain',
      maxRenderSide: 512,
      rasterizer: (_, _) async => [
        RenderedPdfPage(
          pageNumber: 1,
          pngBytes: Uint8List.fromList(pngHeader),
          width: 362,
          height: 512,
        ),
      ],
    );

    final stored = await File(pages.single.filePath).readAsBytes();
    expect(stored, orderedEquals(pngHeader));
  });
}
