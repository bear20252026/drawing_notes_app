import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// NoteParagraph + NoteDocument 测试（Word 文档式——纯 Dart 不可变——不搞崩）。
void main() {
  // ── NoteParagraph ──────────────────────────────────────────────

  group('NoteParagraph', () {
    test('默认 type 为 paragraph', () {
      const p = NoteParagraph(id: 'p1', content: 'Hello');
      expect(p.type, NoteParagraphType.paragraph);
      expect(p.isHeading, isFalse);
    });

    test('heading 类型 isHeading 为 true', () {
      const p = NoteParagraph(
        id: 'p2',
        content: 'Title',
        type: NoteParagraphType.heading,
      );
      expect(p.isHeading, isTrue);
    });

    test('copyWith 保持 id 不可变', () {
      const p = NoteParagraph(id: 'p1', content: 'A');
      final updated = p.copyWith(content: 'B');
      expect(p.content, 'A'); // 原实例不变。
      expect(updated.content, 'B');
      expect(updated.id, 'p1'); // id 保留。
    });

    test('copyWith 可切换 type', () {
      const p = NoteParagraph(id: 'p1', content: 'X');
      final h = p.copyWith(type: NoteParagraphType.heading);
      expect(p.type, NoteParagraphType.paragraph); // 原实例不变。
      expect(h.type, NoteParagraphType.heading);
    });

    test('相等性基于 id', () {
      const a = NoteParagraph(id: 'p1', content: 'A');
      const b = NoteParagraph(id: 'p1', content: 'B');
      const c = NoteParagraph(id: 'p2', content: 'A');
      expect(a, b); // id 相同即相等。
      expect(a == c, isFalse);
    });

    test('hashCode 基于 id', () {
      const a = NoteParagraph(id: 'p1', content: 'A');
      const b = NoteParagraph(id: 'p1', content: 'B');
      expect(a.hashCode, b.hashCode);
    });
  });

  // ── NoteDocument ───────────────────────────────────────────────

  group('NoteDocument', () {
    test('默认 title 为"未命名笔记"', () {
      const doc = NoteDocument();
      expect(doc.title, '未命名笔记');
      expect(doc.paragraphs, isEmpty);
    });

    test('paragraphCount 返回段落数量', () {
      const doc = NoteDocument(
        id: 'd1',
        paragraphs: [
          NoteParagraph(id: 'p1', content: 'A'),
          NoteParagraph(id: 'p2', content: 'B'),
        ],
      );
      expect(doc.paragraphCount, 2);
    });

    test('fullText 拼接段落内容', () {
      const doc = NoteDocument(
        id: 'd1',
        paragraphs: [
          NoteParagraph(id: 'p1', content: 'Hello'),
          NoteParagraph(id: 'p2', content: 'World'),
        ],
      );
      expect(doc.fullText, 'Hello\nWorld');
    });

    test('fullText 空段落返回空串', () {
      const doc = NoteDocument(id: 'd1');
      expect(doc.fullText, '');
    });

    test('copyWith 保持 id 不可变', () {
      const doc = NoteDocument(id: 'd1', title: 'Old');
      final updated = doc.copyWith(title: 'New');
      expect(doc.title, 'Old'); // 原实例不变。
      expect(updated.title, 'New');
      expect(updated.id, 'd1'); // id 保留。
    });

    test('copyWith 可替换段落列表', () {
      const doc = NoteDocument(id: 'd1');
      const paras = [
        NoteParagraph(id: 'p1', content: 'X'),
      ];
      final updated = doc.copyWith(paragraphs: paras);
      expect(updated.paragraphCount, 1);
      expect(updated.paragraphs.first.content, 'X');
    });

    test('相等性基于 id', () {
      const a = NoteDocument(id: 'd1', title: 'A');
      const b = NoteDocument(id: 'd1', title: 'B');
      const c = NoteDocument(id: 'd2', title: 'A');
      expect(a, b); // id 相同即相等。
      expect(a == c, isFalse);
    });

    test('hashCode 基于 id', () {
      const a = NoteDocument(id: 'd1');
      const b = NoteDocument(id: 'd1');
      expect(a.hashCode, b.hashCode);
    });
  });
}
