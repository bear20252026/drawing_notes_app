import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——RichTextBlock 富文本块测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('TextFormat：默认无格式', () {
    const format = TextFormat();
    expect(format.bold, false);
    expect(format.italic, false);
    expect(format.underline, false);
    expect(format.listType, ListType.none);
  });

  test('TextFormat：copyWith 不可变', () {
    const original = TextFormat();
    final bold = original.copyWith(bold: true);
    expect(original.bold, false); // 原实例不变。
    expect(bold.bold, true);
  });

  test('TextFormat：预设常量', () {
    expect(TextFormat.boldStyle.bold, true);
    expect(TextFormat.italicStyle.italic, true);
    expect(TextFormat.boldItalicStyle.bold, true);
    expect(TextFormat.boldItalicStyle.italic, true);
    expect(TextFormat.bulletListStyle.listType, ListType.bullet);
    expect(TextFormat.numberedListStyle.listType, ListType.numbered);
  });

  test('RichTextSpan：copyWith 不可变', () {
    const span = RichTextSpan(text: 'hello');
    final boldSpan = span.copyWith(format: TextFormat.boldStyle);
    expect(span.format.bold, false); // 原实例不变。
    expect(boldSpan.format.bold, true);
    expect(boldSpan.text, 'hello');
  });

  test('RichTextBlock：plainText 合并', () {
    const block = RichTextBlock(
      id: 'r1',
      spans: [
        RichTextSpan(text: 'Hello '),
        RichTextSpan(text: 'World', format: TextFormat.boldStyle),
      ],
      x: 0,
      y: 0,
    );
    expect(block.plainText, 'Hello World');
    expect(block.isEmpty, false);
  });

  test('RichTextBlock：isEmpty 空判断', () {
    const empty = RichTextBlock(id: 'r1', spans: [], x: 0, y: 0);
    expect(empty.isEmpty, true);
    const withEmptySpan = RichTextBlock(
      id: 'r2',
      spans: [RichTextSpan(text: '')],
      x: 0,
      y: 0,
    );
    expect(withEmptySpan.isEmpty, true);
  });

  test('RichTextBlock：copyWith 不可变', () {
    const block = RichTextBlock(
      id: 'r1',
      spans: [RichTextSpan(text: 'A')],
      x: 0,
      y: 0,
    );
    final moved = block.copyWith(x: 100, y: 200);
    expect(block.x, 0); // 原实例不变。
    expect(moved.x, 100);
    expect(moved.y, 200);
  });

  test('RichTextBlock：列表类型', () {
    const bullet = RichTextBlock(
      id: 'r1',
      spans: [RichTextSpan(text: 'Item')],
      x: 0,
      y: 0,
      listType: ListType.bullet,
    );
    expect(bullet.listType, ListType.bullet);
  });
}
