import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/search/search_index.dart';

void main() {
  group('SearchIndex', () {
    late SearchIndex index;

    setUp(() {
      index = SearchIndex();
    });

    test('初始状态为空', () {
      expect(index.documentCount, 0);
      expect(index.search('test'), isEmpty);
    });

    test('索引文档后可搜索', () {
      index.indexDocument(
        docId: 'note1',
        title: 'First Note',
        text: 'Hello world, this is a test note.',
      );

      final results = index.search('world');
      expect(results, hasLength(1));
      expect(results.first.noteId, 'note1');
      expect(results.first.noteTitle, 'First Note');
      expect(results.first.matchedText, contains('world'));
    });

    test('搜索不区分大小写', () {
      index.indexDocument(
        docId: 'note1',
        title: 'First Note',
        text: 'Hello World',
      );

      expect(index.search('world'), hasLength(1));
      expect(index.search('WORLD'), hasLength(1));
      expect(index.search('World'), hasLength(1));
    });

    test('搜索不存在的词返回空', () {
      index.indexDocument(
        docId: 'note1',
        title: 'First Note',
        text: 'Hello world',
      );

      expect(index.search('flutter'), isEmpty);
    });

    test('多个文档搜索', () {
      index.indexDocument(
        docId: 'note1',
        title: 'Flutter Guide',
        text: 'Flutter is a UI toolkit',
      );
      index.indexDocument(
        docId: 'note2',
        title: 'Dart Guide',
        text: 'Dart is a programming language',
      );
      index.indexDocument(
        docId: 'note3',
        title: 'Both',
        text: 'Flutter uses Dart',
      );

      final results = index.search('Flutter');
      expect(results, hasLength(2));
      expect(results.map((r) => r.noteId), containsAll(['note1', 'note3']));
    });

    test('移除文档后搜索不到', () {
      index.indexDocument(
        docId: 'note1',
        title: 'First Note',
        text: 'Hello world',
      );

      expect(index.search('hello'), hasLength(1));

      index.removeDocument('note1');
      expect(index.search('hello'), isEmpty);
      expect(index.documentCount, 0);
    });

    test('重新索引覆盖旧数据', () {
      index.indexDocument(
        docId: 'note1',
        title: 'Original',
        text: 'Original text',
      );

      index.indexDocument(
        docId: 'note1',
        title: 'Updated',
        text: 'Updated content',
      );

      expect(index.search('original'), isEmpty);
      expect(index.search('updated'), hasLength(1));
      expect(index.documentCount, 1);
    });

    test('限制结果数量', () {
      for (int i = 0; i < 10; i++) {
        index.indexDocument(
          docId: 'note$i',
          title: 'Note $i',
          text: 'common word in all notes',
        );
      }

      final results = index.search('common', limit: 5);
      expect(results, hasLength(5));
    });

    test('匹配结果包含上下文', () {
      index.indexDocument(
        docId: 'note1',
        title: 'Long Note',
        text: 'This is a very long text with the target word in the middle of it',
      );

      final results = index.search('target');
      expect(results, hasLength(1));
      expect(results.first.matchedText, contains('target'));
      // 匹配片段长度应大于匹配词本身
      expect(results.first.matchedText.length, greaterThan('target'.length));
    });
  });

  group('SearchResult', () {
    test('基本属性', () {
      const result = SearchResult(
        noteId: 'note1',
        noteTitle: 'Test Note',
        matchedText: 'Hello world',
        matchStart: 0,
        matchLength: 5,
      );

      expect(result.noteId, 'note1');
      expect(result.noteTitle, 'Test Note');
      expect(result.matchedText, 'Hello world');
      expect(result.matchStart, 0);
      expect(result.matchLength, 5);
      expect(result.isOcrMatch, isFalse);
    });

    test('OCR 匹配标记', () {
      const result = SearchResult(
        noteId: 'note1',
        noteTitle: 'Test Note',
        matchedText: 'handwritten text',
        matchStart: 0,
        matchLength: 10,
        isOcrMatch: true,
      );

      expect(result.isOcrMatch, isTrue);
    });
  });
}
