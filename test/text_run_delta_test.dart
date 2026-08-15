import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/text_run_delta.dart';
import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';

void main() {
  group('TextRunDeltaCodec', () {
    test('runs → Delta ops：无样式片段省略 attributes', () {
      final runs = [
        const TextRun(text: 'Hello'),
        const TextRun(text: ' World', bold: true),
      ];
      final ops = TextRunDeltaCodec.runsToDelta(runs);
      expect(ops, [
        {'insert': 'Hello'},
        {'insert': ' World', 'attributes': {'bold': true}},
      ]);
    });

    test('runs → Delta ops：全属性映射（strike/color）', () {
      final runs = [
        const TextRun(
          text: 'x',
          bold: true,
          italic: true,
          underline: true,
          strikethrough: true,
          color: 0xFF1A1A1A,
        ),
      ];
      final ops = TextRunDeltaCodec.runsToDelta(runs);
      expect(ops.single['insert'], 'x');
      final attrs = ops.single['attributes'] as Map;
      expect(attrs['bold'], true);
      expect(attrs['italic'], true);
      expect(attrs['underline'], true);
      expect(attrs['strike'], true);
      expect(attrs['color'], '#1A1A1A');
    });

    test('Delta ops → runs：完整往返（round-trip）', () {
      final original = [
        const TextRun(text: '你好', bold: true),
        const TextRun(text: ' 世界', color: 0xFF112233),
      ];
      final back = TextRunDeltaCodec.deltaToRuns(
        TextRunDeltaCodec.runsToDelta(original),
      );
      expect(back.length, original.length);
      expect(back[0].text, '你好');
      expect(back[0].bold, true);
      expect(back[1].color, 0xFF112233);
    });

    test('Delta ops → runs：兼容仅 insert 字符串与未知属性', () {
      final runs = TextRunDeltaCodec.deltaToRuns([
        {'insert': 'plain'},
        {'insert': 'bold', 'attributes': {'bold': true, 'unknown': 1}},
      ]);
      expect(runs.length, 2);
      expect(runs[0].text, 'plain');
      expect(runs[1].bold, true);
    });

    test('边界：空 runs / 空 insert / 非法颜色', () {
      expect(TextRunDeltaCodec.runsToDelta([]), isEmpty);
      expect(TextRunDeltaCodec.deltaToRuns([]), isEmpty);
      expect(
        TextRunDeltaCodec.deltaToRuns([{'insert': ''}]).length,
        0,
      );
      final badColor = TextRunDeltaCodec.deltaToRuns([
        {'insert': 't', 'attributes': {'color': 'not-a-color'}},
      ]);
      expect(badColor.single.color, isNull);
    });

    test('颜色格式：hex 往返一致', () {
      final ops = TextRunDeltaCodec.runsToDelta([
        const TextRun(text: 'c', color: 0xFFFF00AA),
      ]);
      final attrs = ops.single['attributes'] as Map;
      expect(attrs['color'], '#FF00AA');
      final back = TextRunDeltaCodec.deltaToRuns(ops);
      expect(back.single.color, 0xFFFF00AA);
    });
  });
}
