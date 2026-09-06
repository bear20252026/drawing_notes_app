// 由 Claude 团队生成 | Drawing Notes App
// text_span_editor.dart 单元测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_inline_span.dart';
import 'package:drawing_notes_app/features/doc/domain/text_span_editor.dart';

void main() {
  group('TextSpanEditor', () {
    const editor = TextSpanEditor();

    group('applyBold', () {
      test('对纯文本选区应用粗体', () {
        final spans = NoteInlineSpanList.fromPlainText('Hello World');
        final result = editor.applyBold(spans, const SpanRange(0, 5));

        expect(result.length, 2);
        expect(result[0].text, 'Hello');
        expect(result[0].bold, isTrue);
        expect(result[1].text, ' World');
        expect(result[1].bold, isFalse);
      });

      test('对已全粗体的选区移除粗体（toggle）', () {
        final spans = [NoteInlineSpan(text: 'Hello', bold: true)];
        final result = editor.applyBold(spans, const SpanRange(0, 5));

        expect(result.length, 1);
        expect(result[0].bold, isFalse);
      });

      test('空选区不修改', () {
        final spans = NoteInlineSpanList.fromPlainText('Hello');
        final result = editor.applyBold(spans, const SpanRange(3, 3));
        expect(result, equals(spans));
      });

      test('跨 span 选区应用粗体', () {
        final spans = [
          NoteInlineSpan(text: 'Hello ', bold: true),
          NoteInlineSpan(text: 'World', bold: false),
        ];
        final result = editor.applyBold(spans, const SpanRange(3, 8));

        // 选区覆盖 "lo Wo" → 部分在粗体 span，部分在非粗体 span
        // 由于不是全部已粗体 → 应用粗体
        final selectedText = result.fold('', (acc, s) {
          if (s.bold) {
            acc = acc + s.text;
          }
          return acc;
        });
        expect(selectedText, contains('lo'));
      });
    });

    group('applyItalic', () {
      test('对选区应用斜体', () {
        final spans = NoteInlineSpanList.fromPlainText('Hello World');
        final result = editor.applyItalic(spans, const SpanRange(6, 11));

        expect(result.length, 2);
        expect(result[0].text, 'Hello ');
        expect(result[0].italic, isFalse);
        expect(result[1].text, 'World');
        expect(result[1].italic, isTrue);
      });

      test('toggle 语义：已全斜体则移除', () {
        final spans = [NoteInlineSpan(text: 'Hello', italic: true)];
        final result = editor.applyItalic(spans, const SpanRange(0, 5));
        expect(result.first.italic, isFalse);
      });
    });

    group('applyLink', () {
      test('对选区应用链接', () {
        final spans = NoteInlineSpanList.fromPlainText('Click here');
        final result = editor.applyLink(
          spans,
          const SpanRange(0, 5),
          'https://example.com',
        );

        expect(result.length, 2);
        expect(result[0].text, 'Click');
        expect(result[0].link, 'https://example.com');
        expect(result[1].text, ' here');
        expect(result[1].link, isNull);
      });

      test('对已有相同链接的选区移除链接', () {
        final spans = [
          NoteInlineSpan(text: 'Click', link: 'https://example.com'),
        ];
        final result = editor.applyLink(
          spans,
          const SpanRange(0, 5),
          'https://example.com',
        );
        expect(result.first.link, isNull);
      });

      test('空选区不修改', () {
        final spans = NoteInlineSpanList.fromPlainText('Hello');
        final result = editor.applyLink(spans, const SpanRange(2, 2), 'url');
        expect(result, equals(spans));
      });
    });

    group('clearStyle', () {
      test('移除选区上的所有样式', () {
        final spans = [
          NoteInlineSpan(text: 'Bold', bold: true, italic: true),
          NoteInlineSpan(text: 'Link', link: 'url'),
        ];
        final result = editor.clearStyle(spans, const SpanRange(0, 9));

        expect(result.length, 1);
        expect(result[0].text, 'BoldLink');
        expect(result[0].isPlain, isTrue);
      });

      test('仅移除选区内的样式', () {
        final spans = [
          NoteInlineSpan(text: 'Hello ', bold: true),
          NoteInlineSpan(text: 'World', bold: true),
        ];
        final result = editor.clearStyle(spans, const SpanRange(3, 8));

        // "lo Wo" 被清除样式
        expect(result.length, 3);
        expect(result[0].text, 'Hel');
        expect(result[0].bold, isTrue);
        expect(result[1].text, 'lo Wo');
        expect(result[1].bold, isFalse);
        expect(result[2].text, 'rld');
        expect(result[2].bold, isTrue);
      });
    });

    group('边界安全', () {
      test('选区越界自动 clamp', () {
        final spans = NoteInlineSpanList.fromPlainText('Hi');
        final result = editor.applyBold(spans, const SpanRange(-5, 100));
        expect(result.first.bold, isTrue);
      });

      test('空 span 列表不报错', () {
        final result = editor.applyBold([], const SpanRange(0, 5));
        expect(result, isEmpty);
      });

      test('不可变性：原列表不变', () {
        final spans = NoteInlineSpanList.fromPlainText('Hello');
        editor.applyBold(spans, const SpanRange(0, 3));
        expect(spans.first.bold, isFalse);
      });
    });
  });

  group('SpanRange', () {
    test('isEmpty 当 start >= end 时为 true', () {
      expect(const SpanRange(3, 3).isEmpty, isTrue);
      expect(const SpanRange(5, 3).isEmpty, isTrue);
      expect(const SpanRange(0, 5).isEmpty, isFalse);
    });

    test('contains 判断偏移是否在范围内', () {
      const range = SpanRange(2, 5);
      expect(range.contains(1), isFalse);
      expect(range.contains(2), isTrue);
      expect(range.contains(4), isTrue);
      expect(range.contains(5), isFalse);
    });
  });
}
