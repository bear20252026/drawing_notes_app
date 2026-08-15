import 'dart:io';

import 'package:drawing_notes_app/features/drawing/application/search_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_accessor_impl.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('search_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('全文搜索：命中笔记本文字块内容与画作标题', () async {
    final nbStorage = NotebookStorage(directoryProvider: () async => tempDir);
    final docStorage = StorageService(directoryProvider: () async => tempDir);

    final nb = Notebook(id: 'nb1', title: '会议纪要');
    final page = NotebookPage(
      id: 'pg1',
      title: '会议记录',
      document: DrawingDocument(id: 'd1', title: '页'),
    );
    page.textItems.add(PageTextItem(id: 't1', x: 0, y: 0, text: '政府项目验收要点'));
    nb.pages.add(page);
    await nbStorage.save(nb);

    final drawing = DrawingDocument(id: 'doc2', title: '政府项目流程图');
    await docStorage.save(drawing);

    final svc = SearchService(
      notebookAccessor: NotebookAccessorImpl(storage: nbStorage),
      docStorage: docStorage,
    );
    final results = await svc.search('政府');
    expect(results.length, greaterThanOrEqualTo(2));
    expect(
      results.any((r) => r.snippet.contains('政府项目验收要点')),
      isTrue,
      reason: '应命中文字块内容',
    );
    expect(results.any((r) => r.title == '政府项目流程图'), isTrue, reason: '应命中画作标题');
  });

  test('空关键词返回空结果', () async {
    final svc = SearchService(
      notebookAccessor: NotebookAccessorImpl(
        storage: NotebookStorage(directoryProvider: () async => tempDir),
      ),
      docStorage: StorageService(directoryProvider: () async => tempDir),
    );
    expect(await svc.search('   '), isEmpty);
  });
}
