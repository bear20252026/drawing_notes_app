import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——DocumentImporter 文档导入系统测试（纯逻辑——不搞崩）。
void main() {
  test('ImportFormat：扩展名', () {
    expect(ImportFormat.markdown.extension, '.md');
    expect(ImportFormat.html.extension, '.html');
    expect(ImportFormat.json.extension, '.json');
    expect(ImportFormat.pdf.extension, '.pdf');
    expect(ImportFormat.image.extension, '.png');
  });

  test('detectFormat：从文件名检测格式', () {
    expect(DocumentImporter.detectFormat('readme.md'), ImportFormat.markdown);
    expect(DocumentImporter.detectFormat('page.html'), ImportFormat.html);
    expect(DocumentImporter.detectFormat('notes.txt'), ImportFormat.plainText);
    expect(DocumentImporter.detectFormat('drawing.json'), ImportFormat.json);
    expect(DocumentImporter.detectFormat('document.pdf'), ImportFormat.pdf);
    expect(DocumentImporter.detectFormat('image.png'), ImportFormat.image);
    expect(DocumentImporter.detectFormat('photo.jpg'), ImportFormat.image);
    expect(DocumentImporter.detectFormat('photo.jpeg'), ImportFormat.image);
    expect(DocumentImporter.detectFormat('icon.svg'), ImportFormat.image);
    expect(DocumentImporter.detectFormat('unknown.xyz'), ImportFormat.unknown);
  });

  test('detectFormat：大小写不敏感', () {
    expect(DocumentImporter.detectFormat('README.MD'), ImportFormat.markdown);
    expect(DocumentImporter.detectFormat('Page.HTML'), ImportFormat.html);
    expect(DocumentImporter.detectFormat('Image.PNG'), ImportFormat.image);
  });

  test('ImportResult：默认值 + isSuccess/isFailed', () {
    const result = ImportResult(status: ImportStatus.pending);
    expect(result.isSuccess, false);
    expect(result.isFailed, false);
    expect(result.hasErrors, false);
    expect(result.message, '');

    const success = ImportResult(status: ImportStatus.completed, documentId: 'doc1', pageCount: 3, elementCount: 10);
    expect(success.isSuccess, true);
    expect(success.documentId, 'doc1');
    expect(success.pageCount, 3);
    expect(success.elementCount, 10);

    const failed = ImportResult(status: ImportStatus.failed, errors: ['File not found']);
    expect(failed.isFailed, true);
    expect(failed.hasErrors, true);
  });

  test('ImportResult：copyWith 不可变', () {
    const original = ImportResult(status: ImportStatus.pending);
    final updated = original.copyWith(status: ImportStatus.completed, documentId: 'doc1');
    expect(original.status, ImportStatus.pending); // 原实例不变。
    expect(updated.status, ImportStatus.completed);
    expect(updated.documentId, 'doc1');
  });

  test('ImportConfig：默认值 + copyWith 不可变', () {
    const config = ImportConfig();
    expect(config.format, ImportFormat.unknown);
    expect(config.mergeIntoCurrent, false);
    expect(config.preserveFormatting, true);
    expect(config.extractImages, true);
    expect(config.maxFileSize, 50 * 1024 * 1024);
    final updated = config.copyWith(format: ImportFormat.markdown, mergeIntoCurrent: true);
    expect(config.format, ImportFormat.unknown); // 原实例不变。
    expect(updated.format, ImportFormat.markdown);
    expect(updated.mergeIntoCurrent, true);
  });

  test('validate：格式验证通过', () {
    final result = DocumentImporter.validate('readme.md', 1024);
    expect(result.status, ImportStatus.pending);
    expect(result.message, 'Validation passed');
  });

  test('validate：不支持的格式', () {
    final result = DocumentImporter.validate('unknown.xyz', 1024);
    expect(result.isFailed, true);
    expect(result.errors, contains('Unsupported file format'));
  });

  test('validate：文件太大', () {
    final result = DocumentImporter.validate('large.pdf', 100 * 1024 * 1024);
    expect(result.isFailed, true);
    expect(result.errors, contains('File too large'));
  });

  test('validate：自定义配置（更小的大小限制）', () {
    const config = ImportConfig(maxFileSize: 1024);
    final result = DocumentImporter.validate('big.md', 2048, config: config);
    expect(result.isFailed, true);
  });

  test('preview：预览导入', () {
    final result = DocumentImporter.preview('document.pdf', 1024);
    expect(result.status, ImportStatus.pending);
    expect(result.message, contains('document.pdf'));
    expect(result.pageCount, 1); // PDF 可能多页。
  });

  test('preview：验证失败时返回失败结果', () {
    final result = DocumentImporter.preview('unknown.xyz', 1024);
    expect(result.isFailed, true);
  });

  test('ImportStatus/ImportFormat 枚举', () {
    expect(ImportStatus.values.length, 4);
    expect(ImportFormat.values.length, 7);
  });
}
