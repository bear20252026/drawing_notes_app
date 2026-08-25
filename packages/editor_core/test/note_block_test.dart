import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// NoteBlock 块模型测试（AFFiNE BlockSuite 借鉴——纯 Dart 不可变——不搞崩）。
void main() {
  // ── NoteBlockType 枚举 ─────────────────────────────────────────

  group('NoteBlockType', () {
    test('包含所有预期类型', () {
      expect(NoteBlockType.values.length, 11);
      expect(NoteBlockType.values, contains(NoteBlockType.paragraph));
      expect(NoteBlockType.values, contains(NoteBlockType.heading1));
      expect(NoteBlockType.values, contains(NoteBlockType.heading2));
      expect(NoteBlockType.values, contains(NoteBlockType.heading3));
      expect(NoteBlockType.values, contains(NoteBlockType.bulletList));
      expect(NoteBlockType.values, contains(NoteBlockType.numberedList));
      expect(NoteBlockType.values, contains(NoteBlockType.code));
      expect(NoteBlockType.values, contains(NoteBlockType.quote));
      expect(NoteBlockType.values, contains(NoteBlockType.divider));
      expect(NoteBlockType.values, contains(NoteBlockType.image));
      expect(NoteBlockType.values, contains(NoteBlockType.table));
    });
  });

  // ── NoteBlock 基础 ─────────────────────────────────────────────

  group('NoteBlock 基础', () {
    test('默认 content 为空串', () {
      const block = NoteBlock(id: 'b1', type: NoteBlockType.paragraph);
      expect(block.content, '');
      expect(block.spans, isEmpty);
      expect(block.meta, isEmpty);
      expect(block.children, isEmpty);
    });

    test('isEmpty — content 和 spans 都空', () {
      const block = NoteBlock(id: 'b1', type: NoteBlockType.paragraph);
      expect(block.isEmpty, isTrue);
    });

    test('isEmpty — 有 content 则非空', () {
      const block = NoteBlock(
        id: 'b1',
        type: NoteBlockType.paragraph,
        content: 'Hello',
      );
      expect(block.isEmpty, isFalse);
    });

    test('isEmpty — 有 spans 则非空', () {
      const block = NoteBlock(
        id: 'b1',
        type: NoteBlockType.paragraph,
        spans: [RichTextSpan(text: 'Hi')],
      );
      expect(block.isEmpty, isFalse);
    });
  });

  // ── 标题判定 ────────────────────────────────────────────────────

  group('isHeading', () {
    test('heading1/2/3 返回 true', () {
      expect(
        const NoteBlock(id: 'b1', type: NoteBlockType.heading1).isHeading,
        isTrue,
      );
      expect(
        const NoteBlock(id: 'b2', type: NoteBlockType.heading2).isHeading,
        isTrue,
      );
      expect(
        const NoteBlock(id: 'b3', type: NoteBlockType.heading3).isHeading,
        isTrue,
      );
    });

    test('其他类型返回 false', () {
      expect(
        const NoteBlock(id: 'b1', type: NoteBlockType.paragraph).isHeading,
        isFalse,
      );
      expect(
        const NoteBlock(id: 'b2', type: NoteBlockType.code).isHeading,
        isFalse,
      );
    });
  });

  // ── 列表判定 ────────────────────────────────────────────────────

  group('isList', () {
    test('bulletList 和 numberedList 返回 true', () {
      expect(
        const NoteBlock(id: 'b1', type: NoteBlockType.bulletList).isList,
        isTrue,
      );
      expect(
        const NoteBlock(id: 'b2', type: NoteBlockType.numberedList).isList,
        isTrue,
      );
    });

    test('其他类型返回 false', () {
      expect(
        const NoteBlock(id: 'b1', type: NoteBlockType.paragraph).isList,
        isFalse,
      );
      expect(
        const NoteBlock(id: 'b2', type: NoteBlockType.heading1).isList,
        isFalse,
      );
    });
  });

  // ── headingLevel ────────────────────────────────────────────────

  group('headingLevel', () {
    test('heading1 → 1', () {
      expect(
        const NoteBlock(id: 'b1', type: NoteBlockType.heading1).headingLevel,
        1,
      );
    });

    test('heading2 → 2', () {
      expect(
        const NoteBlock(id: 'b2', type: NoteBlockType.heading2).headingLevel,
        2,
      );
    });

    test('heading3 → 3', () {
      expect(
        const NoteBlock(id: 'b3', type: NoteBlockType.heading3).headingLevel,
        3,
      );
    });

    test('非标题 → 0', () {
      expect(
        const NoteBlock(id: 'b1', type: NoteBlockType.paragraph).headingLevel,
        0,
      );
      expect(
        const NoteBlock(id: 'b2', type: NoteBlockType.code).headingLevel,
        0,
      );
    });
  });

  // ── fromSlashType 转换 ─────────────────────────────────────────

  group('fromSlashType', () {
    test('paragraph → paragraph', () {
      expect(
        NoteBlock.fromSlashType(SlashBlockType.paragraph),
        NoteBlockType.paragraph,
      );
    });

    test('heading → heading1', () {
      expect(
        NoteBlock.fromSlashType(SlashBlockType.heading),
        NoteBlockType.heading1,
      );
    });

    test('list → bulletList', () {
      expect(
        NoteBlock.fromSlashType(SlashBlockType.list),
        NoteBlockType.bulletList,
      );
    });

    test('quote → quote', () {
      expect(
        NoteBlock.fromSlashType(SlashBlockType.quote),
        NoteBlockType.quote,
      );
    });

    test('code → code', () {
      expect(
        NoteBlock.fromSlashType(SlashBlockType.code),
        NoteBlockType.code,
      );
    });

    test('divider → divider', () {
      expect(
        NoteBlock.fromSlashType(SlashBlockType.divider),
        NoteBlockType.divider,
      );
    });
  });

  // ── icon ────────────────────────────────────────────────────────

  group('icon', () {
    test('所有类型有图标', () {
      for (final type in NoteBlockType.values) {
        final block = NoteBlock(id: 'b', type: type);
        expect(block.icon, isNotEmpty, reason: '$type should have icon');
      }
    });

    test('paragraph → 📄', () {
      expect(
        const NoteBlock(id: 'b', type: NoteBlockType.paragraph).icon,
        '📄',
      );
    });

    test('code → 💻', () {
      expect(
        const NoteBlock(id: 'b', type: NoteBlockType.code).icon,
        '💻',
      );
    });

    test('image → 🖼️', () {
      expect(
        const NoteBlock(id: 'b', type: NoteBlockType.image).icon,
        '🖼️',
      );
    });
  });

  // ── copyWith ────────────────────────────────────────────────────

  group('copyWith', () {
    test('保持 id 不可变', () {
      const block = NoteBlock(id: 'b1', type: NoteBlockType.paragraph);
      final updated = block.copyWith(content: 'New content');
      expect(block.content, ''); // 原实例不变。
      expect(updated.content, 'New content');
      expect(updated.id, 'b1');
    });

    test('可切换 type', () {
      const block = NoteBlock(id: 'b1', type: NoteBlockType.paragraph);
      final h = block.copyWith(type: NoteBlockType.heading1);
      expect(block.type, NoteBlockType.paragraph); // 原实例不变。
      expect(h.type, NoteBlockType.heading1);
    });

    test('可添加 meta', () {
      const block = NoteBlock(id: 'b1', type: NoteBlockType.code);
      final withMeta = block.copyWith(meta: {'language': 'dart'});
      expect(withMeta.meta['language'], 'dart');
    });

    test('可添加 children', () {
      const child = NoteBlock(id: 'b2', type: NoteBlockType.paragraph);
      const block = NoteBlock(id: 'b1', type: NoteBlockType.bulletList);
      final withChild = block.copyWith(children: [child]);
      expect(withChild.children.length, 1);
      expect(withChild.children.first.id, 'b2');
    });

    test('可添加 spans', () {
      const block = NoteBlock(id: 'b1', type: NoteBlockType.paragraph);
      final withSpans = block.copyWith(
        spans: [const RichTextSpan(text: 'Hello')],
      );
      expect(withSpans.spans.length, 1);
      expect(withSpans.spans.first.text, 'Hello');
    });
  });

  // ── toParagraph ─────────────────────────────────────────────────

  group('toParagraph', () {
    test('paragraph → type: "paragraph"', () {
      const block = NoteBlock(
        id: 'b1',
        type: NoteBlockType.paragraph,
        content: 'Hello',
      );
      final p = block.toParagraph();
      expect(p['id'], 'b1');
      expect(p['content'], 'Hello');
      expect(p['type'], 'paragraph');
    });

    test('heading1 → type: "heading"', () {
      const block = NoteBlock(
        id: 'b1',
        type: NoteBlockType.heading1,
        content: 'Title',
      );
      final p = block.toParagraph();
      expect(p['type'], 'heading');
    });

    test('heading2 → type: "heading"', () {
      const block = NoteBlock(
        id: 'b1',
        type: NoteBlockType.heading2,
        content: 'Subtitle',
      );
      final p = block.toParagraph();
      expect(p['type'], 'heading');
    });

    test('heading3 → type: "heading"', () {
      const block = NoteBlock(
        id: 'b1',
        type: NoteBlockType.heading3,
        content: 'Sub-sub',
      );
      final p = block.toParagraph();
      expect(p['type'], 'heading');
    });

    test('code → type: "paragraph"（非标题类型回退）', () {
      const block = NoteBlock(
        id: 'b1',
        type: NoteBlockType.code,
        content: 'print("hi")',
      );
      final p = block.toParagraph();
      expect(p['type'], 'paragraph');
      expect(p['content'], 'print("hi")');
    });

    test('divider → type: "paragraph"', () {
      const block = NoteBlock(id: 'b1', type: NoteBlockType.divider);
      final p = block.toParagraph();
      expect(p['type'], 'paragraph');
      expect(p['content'], '');
    });
  });

  // ── 相等性 ──────────────────────────────────────────────────────

  group('相等性', () {
    test('id + type + content 相同则相等', () {
      const a = NoteBlock(
        id: 'b1',
        type: NoteBlockType.paragraph,
        content: 'X',
      );
      const b = NoteBlock(
        id: 'b1',
        type: NoteBlockType.paragraph,
        content: 'X',
      );
      expect(a, b);
    });

    test('id 不同则不相等', () {
      const a = NoteBlock(id: 'b1', type: NoteBlockType.paragraph);
      const b = NoteBlock(id: 'b2', type: NoteBlockType.paragraph);
      expect(a == b, isFalse);
    });

    test('type 不同则不相等', () {
      const a = NoteBlock(id: 'b1', type: NoteBlockType.paragraph);
      const b = NoteBlock(id: 'b1', type: NoteBlockType.heading1);
      expect(a == b, isFalse);
    });

    test('content 不同则不相等', () {
      const a = NoteBlock(
        id: 'b1',
        type: NoteBlockType.paragraph,
        content: 'A',
      );
      const b = NoteBlock(
        id: 'b1',
        type: NoteBlockType.paragraph,
        content: 'B',
      );
      expect(a == b, isFalse);
    });

    test('hashCode 一致', () {
      const a = NoteBlock(
        id: 'b1',
        type: NoteBlockType.heading2,
        content: 'Hi',
      );
      const b = NoteBlock(
        id: 'b1',
        type: NoteBlockType.heading2,
        content: 'Hi',
      );
      expect(a.hashCode, b.hashCode);
    });
  });
}
