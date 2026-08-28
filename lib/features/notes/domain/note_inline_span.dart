// 由 Claude 团队生成 | Drawing Notes App
// 内联富文本 span 模型：承载块内文本的样式片段。
// 纯 Dart，无 flutter/io/controller/存储依赖。

/// 内联富文本片段：携带文本 + 样式标记。
///
/// 用于在 NoteBlock 的文本块中表达粗体/斜体/下划线/链接等内联样式。
/// 多个 [NoteInlineSpan] 组成一个完整块文本；未标注区间视为纯文本。
class NoteInlineSpan {
  const NoteInlineSpan({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.link,
  });

  /// 文本内容。
  final String text;

  /// 是否粗体。
  final bool bold;

  /// 是否斜体。
  final bool italic;

  /// 是否下划线。
  final bool underline;

  /// 链接地址（非空时表示可点击链接）。
  final String? link;

  /// 是否为纯文本（无任何样式）。
  bool get isPlain => !bold && !italic && !underline && link == null;

  /// 是否为空文本。
  bool get isEmpty => text.isEmpty;

  /// 不可变 copyWith。
  NoteInlineSpan copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? underline,
    String? link,
    bool clearLink = false,
  }) =>
      NoteInlineSpan(
        text: text ?? this.text,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        link: clearLink ? null : (link ?? this.link),
      );

  /// 从纯文本创建（向后兼容）。
  factory NoteInlineSpan.plain(String text) => NoteInlineSpan(text: text);

  /// 合并相邻同样式 span（规范化）。
  bool canMergeWith(NoteInlineSpan other) =>
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      link == other.link;

  /// 与同样式 span 合并。
  NoteInlineSpan merge(NoteInlineSpan other) =>
      copyWith(text: text + other.text);

  /// 在指定位置切分 span，返回 (前半, 后半)。
  (NoteInlineSpan, NoteInlineSpan) splitAt(int offset) {
    final clamped = offset.clamp(0, text.length);
    return (
      copyWith(text: text.substring(0, clamped)),
      copyWith(text: text.substring(clamped)),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteInlineSpan &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          bold == other.bold &&
          italic == other.italic &&
          underline == other.underline &&
          link == other.link;

  @override
  int get hashCode => Object.hash(text, bold, italic, underline, link);

  @override
  String toString() =>
      'NoteInlineSpan(text: "$text", bold: $bold, italic: $italic, underline: $underline, link: $link)';
}

/// 内联 span 列表的工具扩展。
extension NoteInlineSpanList on List<NoteInlineSpan> {
  /// 拼接所有 span 的文本。
  String get plainText => fold('', (acc, span) => acc + span.text);

  /// 规范化：合并相邻同样式 span。
  List<NoteInlineSpan> normalized() {
    if (isEmpty) return [];
    final result = <NoteInlineSpan>[first];
    for (var i = 1; i < length; i++) {
      final last = result.last;
      final current = this[i];
      if (last.canMergeWith(current)) {
        result[result.length - 1] = last.merge(current);
      } else {
        result.add(current);
      }
    }
    return result;
  }

  /// 从纯文本创建单 span 列表（向后兼容）。
  static List<NoteInlineSpan> fromPlainText(String text) =>
      text.isEmpty ? [] : [NoteInlineSpan.plain(text)];
}
