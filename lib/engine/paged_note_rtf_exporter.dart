import '../models/notebook.dart';

/// 分页笔记到 Word 兼容 RTF 的内容导出器。
///
/// RTF 是 Microsoft Word 与 WPS 均可直接打开和继续编辑的公开文档格式。该
/// 导出器只处理结构化文字内容；手写、图片和形状仍由 PDF/PNG/SVG 导出保真。
class PagedNoteRtfExporter {
  const PagedNoteRtfExporter._();

  static String build({
    required String title,
    required Iterable<PageTextItem> textItems,
  }) {
    final ordered = textItems.toList()
      ..sort((a, b) {
        final byY = a.y.compareTo(b.y);
        return byY == 0 ? a.x.compareTo(b.x) : byY;
      });

    final out = StringBuffer()
      ..write(r'{\rtf1\ansi\deff0\uc1')
      ..write(r'{\fonttbl{\f0 Calibri;}{\f1 Noto Sans CJK SC;}}')
      ..write(r'\viewkind4\pard\sa180\f1\fs24 ')
      ..write(r'\fs36\b ')
      ..write(_escape(title))
      ..write(r'\b0\fs24\par\par ');

    for (final item in ordered) {
      var text = item.text;
      if (item.isTodo) {
        text = '${item.todoChecked ? '[x]' : '[ ]'} $text';
      }
      if (item.isSticky) {
        out.write(r'\highlight7 ');
      }
      if (item.bold) out.write(r'\b ');
      if (item.italic) out.write(r'\i ');
      if (item.underline) out.write(r'\ul ');
      if (item.strikethrough) out.write(r'\strike ');

      final fontHalfPoints = (item.fontSize * 1.5).clamp(16, 96).round();
      out
        ..write('\\fs$fontHalfPoints ')
        ..write(_escape(text).replaceAll(r'\u10?', r'\line '));

      if (item.bold) out.write(r'\b0 ');
      if (item.italic) out.write(r'\i0 ');
      if (item.underline) out.write(r'\ul0 ');
      if (item.strikethrough) out.write(r'\strike0 ');
      if (item.isSticky) out.write(r'\highlight0 ');
      out.write(r'\par ');
    }
    return '${out.toString()}}';
  }

  /// 转义 RTF 控制符，非 ASCII UTF-16 码元写成 `\\uN?`，保证中文、日文等
  /// 在不同 Word 实现中都不会因当前系统代码页而损坏。
  static String _escape(String input) {
    final out = StringBuffer();
    for (final unit in input.codeUnits) {
      switch (unit) {
        case 0x5c: // backslash
          out.write(r'\\');
        case 0x7b: // {
          out.write(r'\{');
        case 0x7d: // }
          out.write(r'\}');
        default:
          if (unit >= 0x20 && unit <= 0x7e) {
            out.writeCharCode(unit);
          } else {
            final signed = unit > 0x7fff ? unit - 0x10000 : unit;
            out.write('\\u$signed?');
          }
      }
    }
    return out.toString();
  }
}
