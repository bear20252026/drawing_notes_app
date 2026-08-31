import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc_search.dart';

void main() {
  group('NoteBlockDocSearchIndex', () {
    // 共用文档：标题 "Flutter Guide"，含多块 + 递归子块。
    NoteBlockDoc buildDoc() {
      final now = DateTime(2026, 8, 28);
      return NoteBlockDoc(
        id: 'doc1',
        title: 'Flutter Guide',
        body: [
          NoteBlock.headingBlock('h1', level: 1, text: 'Getting Started'),
          NoteBlock.textBlock('t1', text: 'Flutter is a UI toolkit for building natively compiled applications.'),
          NoteBlock.textBlock('t2', text: 'Dart is the programming language used by Flutter.'),
          NoteBlock(
            id: 'b1',
            type: NoteBlockType.bullet,
            text: 'Installation',
            children: [
              NoteBlock(id: 'b1_1', type: NoteBlockType.bullet, text: 'Download the Flutter SDK'),
              NoteBlock(id: 'b1_2', type: NoteBlockType.bullet, text: 'Set up your editor'),
            ],
          ),
          NoteBlock.textBlock('t3', text: 'Widgets are the basic building blocks of a Flutter app.'),
        ],
        createdAt: now,
        updatedAt: now,
      );
    }

    NoteBlockDocSearchIndex indexed() {
      final idx = NoteBlockDocSearchIndex();
      idx.indexDocument(buildDoc());
      return idx;
    }

    test('命中文本块：query "toolkit" 命中 t1', () {
      final hits = indexed().search('toolkit');
      expect(hits, hasLength(1));
      expect(hits.first.blockId, 't1');
      expect(hits.first.snippet, contains('toolkit'));
      expect(hits.first.matchedTitle, isFalse);
    });

    test('递归子块命中：query "SDK" 命中嵌套块 b1_1', () {
      final hits = indexed().search('SDK');
      expect(hits, hasLength(1));
      expect(hits.first.blockId, 'b1_1');
      expect(hits.first.snippet, contains('SDK'));
    });

    test('不命中返回空：query "kubernetes" 无匹配', () {
      final hits = indexed().search('kubernetes');
      expect(hits, isEmpty);
    });

    test('大小写不敏感：query "FLUTTER" 命中多处', () {
      final hits = indexed().search('FLUTTER');
      // t1, t2, t3 都含 "Flutter"（大小写不敏感）
      final ids = hits.map((h) => h.blockId).toList();
      expect(ids, containsAll(['t1', 't2', 't3']));
      expect(hits.every((h) => h.snippet.isNotEmpty), isTrue);
    });

    test('多 token AND："Flutter UI" 同时含 flutter 与 ui 才命中', () {
      final hits = indexed().search('Flutter UI');
      // t1 含 "Flutter" 与 "UI"
      final ids = hits.map((h) => h.blockId).toList();
      expect(ids, contains('t1'));
      // t2 含 "Flutter" 但不含 "ui"，不应命中
      expect(ids, isNot(contains('t2')));
    });

    test('命中 doc.title → matchedTitle=true：query "Guide" 命中标题', () {
      final hits = indexed().search('Guide');
      // 标题 "Flutter Guide" 含 Guide；全文文本也含标题，故多块命中
      expect(hits, isNotEmpty);
      // 至少有一个 matchedTitle=true（标题包含 Guide）
      expect(hits.any((h) => h.matchedTitle), isTrue);
    });

    test('snippet 含 query 片段且长度受限（前后各 ~20 字符）', () {
      final hits = indexed().search('toolkit');
      expect(hits, hasLength(1));
      final snippet = hits.first.snippet;
      // 必须包含 query
      expect(snippet, contains('toolkit'));
      // 长度受限：query 长 7，前 20 + 7 + 后 20 = 47，加省略号最多 ~53
      expect(snippet.length, lessThanOrEqualTo(60));
    });

    test('空 query 返回空列表', () {
      expect(indexed().search(''), isEmpty);
      expect(indexed().search('   '), isEmpty);
    });

    test('命中 heading 块：query "Getting" 命中 h1', () {
      final hits = indexed().search('Getting');
      expect(hits.map((h) => h.blockId), contains('h1'));
    });

    test('token 含多余空格仍能正确分词："  Flutter   UI  " = AND', () {
      final hits = indexed().search('  Flutter   UI  ');
      final ids = hits.map((h) => h.blockId).toList();
      expect(ids, contains('t1'));
      expect(ids, isNot(contains('t2')));
    });
  });
}
