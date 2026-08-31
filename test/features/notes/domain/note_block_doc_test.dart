// 由 Claude 团队生成 | Drawing Notes App
// note_block_doc.dart 单元测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

void main() {
  group('NoteBlockDoc', () {
    test('empty 工厂生成含一个空 paragraph 的最小文档', () {
      final doc = NoteBlockDoc.empty('doc1');

      expect(doc.id, 'doc1');
      expect(doc.body.length, 1);
      expect(doc.body.first.type, NoteBlockType.text);
      expect(doc.body.first.text, '');
      expect(doc.hasBlocks, isTrue);
    });

    test('empty 工厂可自定义 title', () {
      final doc = NoteBlockDoc.empty('doc1', title: 'My Note');
      expect(doc.title, 'My Note');
    });

    test('copyWith 返回修改字段后的新对象，原对象不变', () {
      final doc = NoteBlockDoc.empty('doc1');
      final updated = doc.copyWith(title: 'Updated');

      expect(doc.title, '');
      expect(updated.title, 'Updated');
      expect(updated.id, 'doc1');
    });

    test('hasBlocks 反映 body 是否为空', () {
      final empty = NoteBlockDoc(
        id: 'd',
        body: [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(empty.hasBlocks, isFalse);

      final nonEmpty = NoteBlockDoc.empty('d');
      expect(nonEmpty.hasBlocks, isTrue);
    });

    test('toJson / fromJson 往返一致', () {
      final doc = NoteBlockDoc(
        id: 'doc1',
        title: 'Test',
        body: [
          NoteBlock.textBlock('b1', text: 'hello'),
          NoteBlock.headingBlock('b2', level: 2, text: 'world'),
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 6, 15),
      );

      final json = doc.toJson();
      final restored = NoteBlockDoc.fromJson(json);

      expect(restored.id, doc.id);
      expect(restored.title, doc.title);
      expect(restored.body.length, 2);
      expect(restored.body[0].text, 'hello');
      expect(restored.body[1].props['level'], 2);
      expect(restored.createdAt, doc.createdAt);
      expect(restored.updatedAt, doc.updatedAt);
    });

    test('fromJson 兼容缺省字段', () {
      final json = {'id': 'legacy'};
      final doc = NoteBlockDoc.fromJson(json);

      expect(doc.id, 'legacy');
      expect(doc.title, '');
      expect(doc.body, isEmpty);
    });

    test('相等性：相同字段相等，不同字段不等', () {
      final a = NoteBlockDoc.empty('x');
      final b = NoteBlockDoc.empty('x');
      final c = NoteBlockDoc.empty('y');

      expect(a == b, isTrue);
      expect(a == c, isFalse);
      expect(a.hashCode == b.hashCode, isTrue);
    });
  });
}
