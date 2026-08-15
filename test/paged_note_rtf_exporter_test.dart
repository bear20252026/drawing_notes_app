import 'package:drawing_notes_app/core/rtf_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';

void main() {
  test('分页笔记转换为包含中文和格式的 Word 兼容 RTF', () {
    final rtf = PagedNoteRtfExporter.build(
      title: '会议纪要',
      textItems: [
        PageTextItem(id: 'later', x: 10, y: 100, text: '第二段', italic: true),
        PageTextItem(
          id: 'first',
          x: 20,
          y: 20,
          text: '完成方案\n发送给团队',
          bold: true,
          underline: true,
          isTodo: true,
          todoChecked: true,
          fontSize: 28,
        ),
      ],
    );

    expect(rtf, startsWith(r'{\rtf1'));
    expect(rtf, contains(r'\u20250?')); // 会
    expect(rtf, contains(r'\b '));
    expect(rtf, contains(r'\ul '));
    expect(rtf, contains('[x]'));
    expect(rtf, contains(r'\line '));
    expect(rtf.indexOf('[x]'), lessThan(rtf.indexOf(r'\u31532?'))); // 第二段
    expect(rtf, endsWith('}'));
  });

  test('RTF 对特殊控制字符进行安全转义', () {
    final rtf = PagedNoteRtfExporter.build(
      title: r'标题{\}',
      textItems: [PageTextItem(id: 'one', x: 0, y: 0, text: r'A{B}\C')],
    );

    expect(rtf, contains(r'\{'));
    expect(rtf, contains(r'\}'));
    expect(rtf, contains(r'\\'));
  });
}
