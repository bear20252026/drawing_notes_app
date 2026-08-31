// 由 Claude 团队生成 | Drawing Notes App
// note_inline_span.dart 单元测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_inline_span.dart';

void main() {
  group('NoteInlineSpan', () {
    test('plain 工厂创建纯文本 span', () {
      final span = NoteInlineSpan.plain('hello');
      expect(span.text, 'hello');
      expect(span.isPlain, isTrue);
      expect(span.bold, isFalse);
      expect(span.italic, isFalse);
    });

    test('isPlain 在有样式时为 false', () {
      expect(NoteInlineSpan(text: 'x', bold: true).isPlain, isFalse);
      expect(NoteInlineSpan(text: 'x', italic: true).isPlain, isFalse);
      expect(NoteInlineSpan(text: 'x', underline: true).isPlain, isFalse);
      expect(NoteInlineSpan(text: 'x', link: 'url').isPlain, isFalse);
    });

    test('isEmpty 反映文本是否为空', () {
      expect(NoteInlineSpan.plain('').isEmpty, isTrue);
      expect(NoteInlineSpan.plain('x').isEmpty, isFalse);
    });

    test('copyWith 返回修改字段后的新对象', () {
      final span = NoteInlineSpan.plain('hello');
      final bold = span.copyWith(bold: true);

      expect(span.bold, isFalse); // 原对象不变
      expect(bold.bold, isTrue);
      expect(bold.text, 'hello');
    });

    test('copyWith clearLink 清除链接', () {
      final span = NoteInlineSpan(text: 'x', link: 'url');
      final cleared = span.copyWith(clearLink: true);
      expect(cleared.link, isNull);
    });

    test('canMergeWith：同样式可合并', () {
      final a = NoteInlineSpan(text: 'a', bold: true);
      final b = NoteInlineSpan(text: 'b', bold: true);
      final c = NoteInlineSpan(text: 'c', italic: true);

      expect(a.canMergeWith(b), isTrue);
      expect(a.canMergeWith(c), isFalse);
    });

    test('merge 拼接文本并保留样式', () {
      final a = NoteInlineSpan(text: 'Hello ', bold: true);
      final b = NoteInlineSpan(text: 'World', bold: true);
      final merged = a.merge(b);

      expect(merged.text, 'Hello World');
      expect(merged.bold, isTrue);
    });

    test('splitAt 切分 span', () {
      final span = NoteInlineSpan(text: 'Hello', bold: true);
      final (first, second) = span.splitAt(3);

      expect(first.text, 'Hel');
      expect(second.text, 'lo');
      expect(first.bold, isTrue);
      expect(second.bold, isTrue);
    });

    test('splitAt 越界安全', () {
      final span = NoteInlineSpan(text: 'Hi');
      final (first, second) = span.splitAt(100);
      expect(first.text, 'Hi');
      expect(second.text, '');

      final (first2, second2) = span.splitAt(-5);
      expect(first2.text, '');
      expect(second2.text, 'Hi');
    });

    test('相等性：同字段相等', () {
      final a = NoteInlineSpan(text: 'x', bold: true, link: 'url');
      final b = NoteInlineSpan(text: 'x', bold: true, link: 'url');
      final c = NoteInlineSpan(text: 'x', bold: true);

      expect(a == b, isTrue);
      expect(a == c, isFalse);
      expect(a.hashCode == b.hashCode, isTrue);
    });
  });

  group('NoteInlineSpanList', () {
    test('plainText 拼接所有文本', () {
      final spans = [
        NoteInlineSpan.plain('Hello '),
        NoteInlineSpan(text: 'World', bold: true),
      ];
      expect(spans.plainText, 'Hello World');
    });

    test('normalized 合并相邻同样式 span', () {
      final spans = [
        NoteInlineSpan(text: 'a', bold: true),
        NoteInlineSpan(text: 'b', bold: true),
        NoteInlineSpan(text: 'c', italic: true),
        NoteInlineSpan(text: 'd', italic: true),
      ];
      final result = spans.normalized();

      expect(result.length, 2);
      expect(result[0].text, 'ab');
      expect(result[0].bold, isTrue);
      expect(result[1].text, 'cd');
      expect(result[1].italic, isTrue);
    });

    test('fromPlainText 从纯文本创建', () {
      final spans = NoteInlineSpanList.fromPlainText('hello');
      expect(spans.length, 1);
      expect(spans.first.text, 'hello');
      expect(spans.first.isPlain, isTrue);
    });

    test('fromPlainText 空文本返回空列表', () {
      final spans = NoteInlineSpanList.fromPlainText('');
      expect(spans, isEmpty);
    });
  });
}
