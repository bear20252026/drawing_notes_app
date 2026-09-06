import 'dart:io';

import 'package:drawing_notes_app/shared/application/search_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_accessor_impl.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/block_doc_search_accessor_impl.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
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

  test('全文搜索：命中块文档正文', () async {
    final store = NoteBlockDocStore(directoryProvider: () async => tempDir);
    await store.saveDocument(
      NoteBlockDoc(
        id: 'docb1',
        title: '块文档笔记',
        body: [NoteBlock.textBlock('b1', text: 'Flutter 架构学习笔记')],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    final svc = SearchService(
      notebookAccessor: NotebookAccessorImpl(
        storage: NotebookStorage(directoryProvider: () async => tempDir),
      ),
      docStorage: StorageService(directoryProvider: () async => tempDir),
      blockDocAccessor: BlockDocSearchAccessorImpl(store: store),
    );
    final results = await svc.search('flutter');
    expect(
      results.any(
        (r) =>
            r.kind == 'blockdoc' &&
            r.title == '块文档笔记' &&
            r.snippet.contains('Flutter'),
      ),
      isTrue,
      reason: '应命中块文档正文且带摘要片段',
    );
  });

  test('全文搜索：命中块文档标题', () async {
    final store = NoteBlockDocStore(directoryProvider: () async => tempDir);
    await store.saveDocument(
      NoteBlockDoc(
        id: 'docb2',
        title: 'Flutter 移动开发指南',
        body: [NoteBlock.textBlock('b0', text: '空')],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    final svc = SearchService(
      notebookAccessor: NotebookAccessorImpl(
        storage: NotebookStorage(directoryProvider: () async => tempDir),
      ),
      docStorage: StorageService(directoryProvider: () async => tempDir),
      blockDocAccessor: BlockDocSearchAccessorImpl(store: store),
    );
    final results = await svc.search('flutter');
    expect(
      results.any((r) => r.kind == 'blockdoc' && r.title == 'Flutter 移动开发指南'),
      isTrue,
      reason: '应命中块文档标题',
    );
  });
}
