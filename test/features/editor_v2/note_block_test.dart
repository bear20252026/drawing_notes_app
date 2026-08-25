// NoteBlock 测试（AFFiNE BlockSuite 借鉴——2026-08-24）。
import 'package:flutter_test/flutter_test.dart';

import 'package:editor_core/editor_core.dart';

void main() {
  group('NoteBlock', () {
    test('创建基本块', () {
      const block = NoteBlock(
        id: 'b1',
        type: NoteBlockType.paragraph,
        content: 'Hello',
      );
      expect(block.id, 'b1');
      expect(block.type, NoteBlockType.paragraph);
      expect(block.content, 'Hello');
      expect(block.isEmpty, false);
    });

    test('空块判断', () {
      const emptyBlock = NoteBlock(
        id: 'b1',
        type: NoteBlockType.paragraph,
      );
      expect(emptyBlock.isEmpty, true);

      const nonEmpty = NoteBlock(
        id: 'b2',
        type: NoteBlockType.paragraph,
        content: 'not empty',
      );
      expect(nonEmpty.isEmpty, false);
    });

    test('标题块判断', () {
      expect(
        const NoteBlock(id: 'h1', type: NoteBlockType.heading1).isHeading,
        true,
      );
      expect(
        const NoteBlock(id: 'h2', type: NoteBlockType.heading2).isHeading,
        true,
      );
      expect(
        const NoteBlock(id: 'h3', type: NoteBlockType.heading3).isHeading,
        true,
      );
      expect(
        const NoteBlock(id: 'p', type: NoteBlockType.paragraph).isHeading,
        false,
      );
    });

    test('列表块判断', () {
      expect(
        const NoteBlock(id: 'b', type: NoteBlockType.bulletList).isList,
        true,
      );
      expect(
        const NoteBlock(id: 'n', type: NoteBlockType.numberedList).isList,
        true,
      );
      expect(
        const NoteBlock(id: 'p', type: NoteBlockType.paragraph).isList,
        false,
      );
    });

    test('标题级别', () {
      expect(
        const NoteBlock(id: 'h1', type: NoteBlockType.heading1).headingLevel,
        1,
      );
      expect(
        const NoteBlock(id: 'h2', type: NoteBlockType.heading2).headingLevel,
        2,
      );
      expect(
        const NoteBlock(id: 'h3', type: NoteBlockType.heading3).headingLevel,
        3,
      );
      expect(
        const NoteBlock(id: 'p', type: NoteBlockType.paragraph).headingLevel,
        0,
      );
    });

    test('fromSlashType 转换', () {
      expect(
        NoteBlock.fromSlashType(SlashBlockType.paragraph),
        NoteBlockType.paragraph,
      );
      expect(
        NoteBlock.fromSlashType(SlashBlockType.heading),
        NoteBlockType.heading1,
      );
      expect(
        NoteBlock.fromSlashType(SlashBlockType.list),
        NoteBlockType.bulletList,
      );
      expect(
        NoteBlock.fromSlashType(SlashBlockType.quote),
        NoteBlockType.quote,
      );
      expect(
        NoteBlock.fromSlashType(SlashBlockType.code),
        NoteBlockType.code,
      );
      expect(
        NoteBlock.fromSlashType(SlashBlockType.divider),
        NoteBlockType.divider,
      );
    });

    test('copyWith', () {
      const original = NoteBlock(
        id: 'b1',
        type: NoteBlockType.paragraph,
        content: 'original',
      );

      final copied = original.copyWith(
        type: NoteBlockType.heading1,
        content: 'heading',
      );

      expect(copied.id, 'b1'); // id 不变
      expect(copied.type, NoteBlockType.heading1);
      expect(copied.content, 'heading');

      // 原始不变
      expect(original.type, NoteBlockType.paragraph);
      expect(original.content, 'original');
    });

    test('相等性', () {
      const a = NoteBlock(id: 'b1', type: NoteBlockType.paragraph, content: 'x');
      const b = NoteBlock(id: 'b1', type: NoteBlockType.paragraph, content: 'x');
      const c = NoteBlock(id: 'b2', type: NoteBlockType.paragraph, content: 'x');

      expect(a == b, true);
      expect(a == c, false);
    });

    test('icon 属性', () {
      expect(const NoteBlock(id: 'p', type: NoteBlockType.paragraph).icon, '📄');
      expect(const NoteBlock(id: 'h1', type: NoteBlockType.heading1).icon, '🔠');
      expect(const NoteBlock(id: 'code', type: NoteBlockType.code).icon, '💻');
    });
  });
}
