// editor_core——RichTextSpan 富文本格式（AFFiNE 块编辑器借鉴——2026-08-21）。
//
// AFFiNE "everything is a block" 理念——文本块扩展为富文本（加粗/斜体/列表）。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
library;

/// 文本格式样式（加粗/斜体/列表——AFFiNE 借鉴）。
class TextFormat {
  const TextFormat({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.listType = ListType.none,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final ListType listType;

  TextFormat copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    ListType? listType,
  }) {
    return TextFormat(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      listType: listType ?? this.listType,
    );
  }

  /// 无格式（默认）。
  static const none = TextFormat();

  /// 加粗格式。
  static const boldStyle = TextFormat(bold: true);

  /// 斜体格式。
  static const italicStyle = TextFormat(italic: true);

  /// 加粗 + 斜体格式。
  static const boldItalicStyle = TextFormat(bold: true, italic: true);

  /// 无序列表格式。
  static const bulletListStyle = TextFormat(listType: ListType.bullet);

  /// 有序列表格式。
  static const numberedListStyle = TextFormat(listType: ListType.numbered);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextFormat &&
          bold == other.bold &&
          italic == other.italic &&
          underline == other.underline &&
          listType == other.listType;

  @override
  int get hashCode => Object.hash(bold, italic, underline, listType);
}

/// 列表类型（AFFiNE 借鉴——块编辑器列表块）。
enum ListType {
  /// 无列表（普通文本）。
  none,

  /// 无序列表（● 圆点）。
  bullet,

  /// 有序列表（1. 2. 3.）。
  numbered,
}

/// 富文本跨度（带格式的文本片段——AFFiNE 借鉴——不可变）。
///
/// AFFiNE 块编辑器 "everything is a block" 理念：
/// - 文本块由多个 RichTextSpan 组成
/// - 每个 span 有独立格式（加粗/斜体/列表）
/// - 不可变（copyWith）
class RichTextSpan {
  const RichTextSpan({
    required this.text,
    this.format = const TextFormat(),
  });

  final String text;
  final TextFormat format;

  RichTextSpan copyWith({String? text, TextFormat? format}) {
    return RichTextSpan(
      text: text ?? this.text,
      format: format ?? this.format,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RichTextSpan && text == other.text && format == other.format;

  @override
  int get hashCode => Object.hash(text, format);
}

/// 富文本块（AFFiNE 块编辑器借鉴——多个 span 组成）。
///
/// 与 TextItem（纯文本）不同：
/// - TextItem：单个字符串
/// - RichTextBlock：多个 RichTextSpan（每个 span 有独立格式）
///
/// 纯 Dart 不可变——可独立测试。
class RichTextBlock {
  const RichTextBlock({
    required this.id,
    required this.spans,
    required this.x,
    required this.y,
    this.listType = ListType.none,
  });

  final String id;
  final List<RichTextSpan> spans;
  final double x;
  final double y;
  final ListType listType;

  RichTextBlock copyWith({
    List<RichTextSpan>? spans,
    double? x,
    double? y,
    ListType? listType,
  }) {
    return RichTextBlock(
      id: id,
      spans: spans ?? this.spans,
      x: x ?? this.x,
      y: y ?? this.y,
      listType: listType ?? this.listType,
    );
  }

  /// 纯文本内容（合并所有 span）。
  String get plainText => spans.map((s) => s.text).join();

  /// 是否为空。
  bool get isEmpty => spans.isEmpty || spans.every((s) => s.text.isEmpty);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RichTextBlock &&
          id == other.id &&
          _listEquals(spans, other.spans) &&
          x == other.x &&
          y == other.y &&
          listType == other.listType;

  @override
  int get hashCode => Object.hash(id, spans, x, y, listType);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
