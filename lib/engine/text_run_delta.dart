import '../models/text_item.dart';

/// 借鉴 flutter-quill（dart_quill_delta）Delta 模型，为本项目 [TextRun]
/// 提供与 Quill Delta ops 的双向转换。
///
/// 设计（精读 flutter-quill 源码结论，见 docs/SOURCE_READ_ADAPTATION_REPORT.md）：
/// - flutter-quill 的 Delta 是"操作序列"：insert/delete/retain + attributes；
///   本项目 [PageTextItem.runs]（[TextRun] 片段）可视为 Delta 的子集。
/// - 本层只做**数据模型转换**（纯 Dart、零依赖），不引入编辑器 UI；
///   未来若升级 flutter_quill，本层即为桥接层（doc JSON 增加 delta 字段）。
/// - 旧文档（无 runs）不受影响：转换仅在 runs 非空时调用，序列化向后兼容。
///
/// Quill attributes 键与本项目 [TextRun] 字段映射：
///   bold → bold / italic → italic / underline → underline /
///   strike → strikethrough / color → color（ARGB int 转 #RRGGBB）
class TextRunDeltaCodec {
  TextRunDeltaCodec._();

  /// Quill Delta attributes 键（与 dart_quill_delta 约定一致）。
  static const String kAttrBold = 'bold';
  static const String kAttrItalic = 'italic';
  static const String kAttrUnderline = 'underline';
  static const String kAttrStrike = 'strike';
  static const String kAttrColor = 'color';

  /// 把 [runs] 转换为 Quill Delta ops 列表：
  /// `[{"insert": "...", "attributes": {...}}, ...]`。
  /// 无样式片段省略 attributes（Delta 惯例）；空 runs 返回空列表。
  static List<Map<String, dynamic>> runsToDelta(List<TextRun> runs) {
    final ops = <Map<String, dynamic>>[];
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      final attrs = <String, dynamic>{};
      if (run.bold) attrs[kAttrBold] = true;
      if (run.italic) attrs[kAttrItalic] = true;
      if (run.underline) attrs[kAttrUnderline] = true;
      if (run.strikethrough) attrs[kAttrStrike] = true;
      if (run.color != null) {
        attrs[kAttrColor] = _colorToHex(run.color!);
      }
      ops.add({
        'insert': run.text,
        if (attrs.isNotEmpty) 'attributes': attrs,
      });
    }
    return ops;
  }

  /// 把 Quill Delta ops 列表转回 [TextRun] 列表。
  /// 兼容两种输入：完整 `{"insert": "...", "attributes": {...}}` 或仅
  /// `"insert"` 字符串；未知 attributes 键忽略（防呆）。
  static List<TextRun> deltaToRuns(List<Map<String, dynamic>> ops) {
    final runs = <TextRun>[];
    for (final op in ops) {
      final insert = op['insert'];
      if (insert is! String || insert.isEmpty) continue;
      final attrs = (op['attributes'] as Map?) ?? const <String, dynamic>{};
      runs.add(TextRun(
        text: insert,
        bold: attrs[kAttrBold] == true,
        italic: attrs[kAttrItalic] == true,
        underline: attrs[kAttrUnderline] == true,
        strikethrough: attrs[kAttrStrike] == true,
        color: attrs[kAttrColor] is String
            ? _hexToColor(attrs[kAttrColor] as String)
            : null,
      ));
    }
    return runs;
  }

  /// ARGB int（0xFFRRGGBB）→ '#RRGGBB'。
  static String _colorToHex(int argb) {
    final rgb = argb & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// '#RRGGBB'（或 '#RRGGBBAA'）→ ARGB int；无法解析返回 null。
  static int? _hexToColor(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6 && h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return h.length == 6 ? (0xFF000000 | v) : v;
  }
}
