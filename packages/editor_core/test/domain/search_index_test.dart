// editor_core——SearchEngine 测试（倒排索引+手写 OCR+结果高亮）。

import 'package:test/test.dart';
import 'package:editor_core/src/domain/search_index.dart';

void main() {
  group('TextPreprocessor', () {
    const preprocessor = TextPreprocessor();

    test('tokenize empty string', () {
      expect(preprocessor.tokenize(''), []);
    });

    test('tokenize English text', () {
      final tokens = preprocessor.tokenize('Hello World');
      expect(tokens, ['hello', 'world']);
    });

    test('tokenize Chinese text', () {
      final tokens = preprocessor.tokenize('你好世界');
      expect(tokens, ['你', '好', '世', '界']);
    });

    test('tokenize mixed text', () {
      final tokens = preprocessor.tokenize('Hello 你好');
      expect(tokens, ['hello', '你', '好']);
    });

    test('tokenize removes punctuation', () {
      final tokens = preprocessor.tokenize('Hello, World!');
      expect(tokens, ['hello', 'world']);
    });
  });

  group('InvertedIndex', () {
    late InvertedIndex index;

    setUp(() {
      index = InvertedIndex();
    });

    test('addDocument and lookup', () {
      final doc = SearchDocument(
        id: 'doc1',
        type: SearchDocType.noteBlock,
        content: 'hello world',
        docRefId: 'note1',
      );

      index.addDocument(doc);

      expect(index.documentCount, 1);
      expect(index.termCount, 2);

      final entry = index.lookup('hello');
      expect(entry, isNotNull);
      expect(entry!.docIds, {'doc1'});
      expect(entry.frequencies['doc1'], 1);
    });

    test('addDocuments batch', () {
      final docs = [
        SearchDocument(
          id: 'doc1',
          type: SearchDocType.noteBlock,
          content: 'hello world',
          docRefId: 'note1',
        ),
        SearchDocument(
          id: 'doc2',
          type: SearchDocType.noteBlock,
          content: 'hello dart',
          docRefId: 'note2',
        ),
      ];

      index.addDocuments(docs);

      expect(index.documentCount, 2);
      expect(index.termCount, 3); // hello, world, dart

      final entry = index.lookup('hello');
      expect(entry!.docIds, {'doc1', 'doc2'});
      expect(entry.docFrequency, 2);
    });

    test('removeDocument', () {
      final doc = SearchDocument(
        id: 'doc1',
        type: SearchDocType.noteBlock,
        content: 'hello world',
        docRefId: 'note1',
      );

      index.addDocument(doc);
      index.removeDocument('doc1');

      expect(index.documentCount, 0);
      expect(index.termCount, 0);
    });

    test('queryAll (AND semantics)', () {
      index.addDocuments([
        SearchDocument(
          id: 'doc1',
          type: SearchDocType.noteBlock,
          content: 'hello world',
          docRefId: 'note1',
        ),
        SearchDocument(
          id: 'doc2',
          type: SearchDocType.noteBlock,
          content: 'hello dart',
          docRefId: 'note2',
        ),
        SearchDocument(
          id: 'doc3',
          type: SearchDocType.noteBlock,
          content: 'world dart',
          docRefId: 'note3',
        ),
      ]);

      final result = index.queryAll(['hello', 'world']);
      expect(result, {'doc1'});
    });

    test('queryAny (OR semantics)', () {
      index.addDocuments([
        SearchDocument(
          id: 'doc1',
          type: SearchDocType.noteBlock,
          content: 'hello world',
          docRefId: 'note1',
        ),
        SearchDocument(
          id: 'doc2',
          type: SearchDocType.noteBlock,
          content: 'hello dart',
          docRefId: 'note2',
        ),
      ]);

      final result = index.queryAny(['world', 'dart']);
      expect(result, {'doc1', 'doc2'});
    });

    test('clear', () {
      index.addDocument(SearchDocument(
        id: 'doc1',
        type: SearchDocType.noteBlock,
        content: 'hello',
        docRefId: 'note1',
      ));

      index.clear();

      expect(index.documentCount, 0);
      expect(index.termCount, 0);
    });
  });

  group('SearchEngine', () {
    late SearchEngine engine;

    setUp(() {
      engine = SearchEngine();
    });

    test('indexNoteBlock and search', () {
      engine.indexNoteBlock('note1', 'block1', 'Hello World');
      engine.indexNoteBlock('note1', 'block2', 'Hello Dart');
      engine.indexNoteBlock('note2', 'block3', 'World of Dart');

      final results = engine.search(SearchQuery(text: 'Hello'));

      expect(results.length, 2);
      expect(results[0].docRefId, 'note1');
    });

    test('indexNoteItem and search', () {
      engine.indexNoteItem('note1', 'item1', 'Sticky note content');
      engine.indexNoteItem('note1', 'item2', 'Another sticky');

      final results = engine.search(SearchQuery(text: 'sticky'));

      expect(results.length, 2);
    });

    test('indexHandwritingOcr and search', () {
      engine.indexHandwritingOcr('note1', 'stroke1', '手写内容识别');
      engine.indexHandwritingOcr('note1', 'stroke2', '更多手写');

      final results = engine.search(SearchQuery(text: '手写'));

      expect(results.length, 2);
      expect(results.every((r) => r.type == SearchDocType.handwritingOcr), true);
    });

    test('search with type filter', () {
      engine.indexNoteBlock('note1', 'block1', 'Note content');
      engine.indexNoteItem('note1', 'item1', 'Sticky content');

      final noteResults = engine.search(SearchQuery(
        text: 'content',
        types: [SearchDocType.noteBlock],
      ));

      expect(noteResults.length, 1);
      expect(noteResults[0].type, SearchDocType.noteBlock);
    });

    test('search with highlights', () {
      engine.indexNoteBlock('note1', 'block1', 'Hello World Hello Dart');

      final results = engine.search(SearchQuery(
        text: 'Hello',
        includeHighlights: true,
      ));

      expect(results.length, 1);
      expect(results[0].highlights.isNotEmpty, true);
    });

    test('search performance <100ms for 1000 docs', () {
      // 生成 1000 个文档
      for (var i = 0; i < 1000; i++) {
        engine.indexNoteBlock('note$i', 'block1', 'Document $i content with searchable text');
      }

      final sw = Stopwatch()..start();
      final results = engine.search(SearchQuery(text: 'searchable'));
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(100));
      expect(results.isNotEmpty, true);
    });

    test('removeNote removes all indexed content', () {
      engine.indexNoteBlock('note1', 'block1', 'Block content');
      engine.indexNoteItem('note1', 'item1', 'Item content');
      engine.indexHandwritingOcr('note1', 'stroke1', 'OCR content');

      engine.removeNote('note1');

      final results = engine.search(SearchQuery(text: 'content'));
      expect(results.isEmpty, true);
    });

    test('rebuildIndex', () {
      engine.indexNoteBlock('note1', 'block1', 'Old content');

      engine.rebuildIndex([
        SearchDocument(
          id: 'block:note2:block1',
          type: SearchDocType.noteBlock,
          content: 'New content',
          docRefId: 'note2',
        ),
      ]);

      final oldResults = engine.search(SearchQuery(text: 'Old'));
      expect(oldResults.isEmpty, true);

      final newResults = engine.search(SearchQuery(text: 'New'));
      expect(newResults.length, 1);
    });

    test('search returns sorted by score', () {
      engine.indexNoteBlock('note1', 'block1', 'hello world');
      engine.indexNoteBlock('note2', 'block1', 'hello hello hello');
      engine.indexNoteBlock('note3', 'block1', 'world');

      final results = engine.search(SearchQuery(text: 'hello'));

      // note2 should have higher score (more occurrences)
      expect(results[0].docRefId, 'note2');
    });
  });
}
