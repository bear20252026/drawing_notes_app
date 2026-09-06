// 由 Claude 团队生成 | Drawing Notes App
// note_block.dart 单元测试。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_attachment.dart';

void main() {
  group('NoteBlock', () {
    test('copyWith 返回修改字段后的新对象，原对象不变', () {
      final block = NoteBlock.textBlock('b1', text: 'hello');
      final updated = block.copyWith(text: 'world');

      expect(block.text, 'hello'); // 原对象不变
      expect(updated.text, 'world');
      expect(updated.id, 'b1');
    });

    test('textual 属性：文本类块为 true，divider 为 false', () {
      expect(NoteBlock.textBlock('a').isTextual, isTrue);
      expect(NoteBlock.headingBlock('b', level: 1).isTextual, isTrue);
      expect(NoteBlock.todoBlock('c').isTextual, isTrue);
      expect(NoteBlock.dividerBlock('d').isTextual, isFalse);
      expect(NoteBlock.imageBlock('e', src: 'x.png').isTextual, isFalse);
    });

    test('heading level 被 clamp 到 1-6', () {
      expect(NoteBlock.headingBlock('h', level: 0).props['level'], 1);
      expect(NoteBlock.headingBlock('h', level: 2).props['level'], 2);
      expect(NoteBlock.headingBlock('h', level: 5).props['level'], 5);
      expect(NoteBlock.headingBlock('h', level: 6).props['level'], 6);
      expect(NoteBlock.headingBlock('h', level: 7).props['level'], 6);
    });

    test('attachmentBlock 工厂：payload 存 attachment JSON', () {
      final a = NoteAttachment(
        id: 'a1',
        name: '报告.pdf',
        kind: AttachmentKind.pdf,
        url: 'https://cdn.example.com/report.pdf',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final block = NoteBlock.attachmentBlock('x', attachment: a);
      expect(block.type, NoteBlockType.attachment);
      final raw = block.props['attachment'] as String;
      final decoded = NoteAttachment.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      expect(decoded, a);
    });

    test('toJson / fromJson 往返一致', () {
      final block = NoteBlock(
        id: 'root',
        type: NoteBlockType.text,
        text: 'parent',
        children: [
          NoteBlock.todoBlock('c1', text: 'task', checked: true),
          NoteBlock.headingBlock('c2', level: 2, text: 'title'),
        ],
      );

      final json = block.toJson();
      final restored = NoteBlock.fromJson(json);

      expect(restored.id, block.id);
      expect(restored.type, block.type);
      expect(restored.text, block.text);
      expect(restored.children.length, 2);
      expect(restored.children[0].props['checked'], true);
      expect(restored.children[1].props['level'], 2);
    });

    test('相等性：相同字段相等，不同字段不等', () {
      final a = NoteBlock.textBlock('x', text: 'same');
      final b = NoteBlock.textBlock('x', text: 'same');
      final c = NoteBlock.textBlock('x', text: 'diff');

      expect(a == b, isTrue);
      expect(a == c, isFalse);
      expect(a.hashCode == b.hashCode, isTrue);
    });

    test('props 为空时不序列化', () {
      final block = NoteBlock.textBlock('b');
      final json = block.toJson();
      expect(json.containsKey('props'), isFalse);
      expect(json.containsKey('children'), isFalse);
    });

    test('fromJson 兼容缺省字段', () {
      final json = {'id': 'legacy', 'type': 'text'};
      final block = NoteBlock.fromJson(json);

      expect(block.id, 'legacy');
      expect(block.type, NoteBlockType.text);
      expect(block.text, '');
      expect(block.props, isEmpty);
      expect(block.children, isEmpty);
    });

    test('fromJson 未知类型回退为 text', () {
      final json = {'id': 'x', 'type': 'unknown_type'};
      final block = NoteBlock.fromJson(json);
      expect(block.type, NoteBlockType.text);
    });
  });
}
