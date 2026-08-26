// notes — Domain 层：笔记内容值对象（零外部依赖）
// 遵循 Clean Architecture：Domain 层不依赖任何外部库或框架

/// 笔记内容值对象（不可变）
///
/// 封装笔记页面的结构化内容
class NoteContent {
  const NoteContent({
    required this.plainText,
    this.markdownHtml,
    this.attachments = const [],
  });

  /// 纯文本内容
  final String plainText;

  /// Markdown 渲染后的 HTML（可选）
  final String? markdownHtml;

  /// 附件路径列表
  final List<String> attachments;

  /// 是否为空笔记
  bool get isEmpty => plainText.isEmpty && (markdownHtml?.isEmpty ?? true);

  /// 是否有附件
  bool get hasAttachments => attachments.isNotEmpty;

  /// 创建副本并覆盖指定字段
  NoteContent copyWith({
    String? plainText,
    String? markdownHtml,
    List<String>? attachments,
  }) {
    return NoteContent(
      plainText: plainText ?? this.plainText,
      markdownHtml: markdownHtml ?? this.markdownHtml,
      attachments: attachments ?? this.attachments,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteContent &&
          runtimeType == other.runtimeType &&
          plainText == other.plainText &&
          markdownHtml == other.markdownHtml;

  @override
  int get hashCode => plainText.hashCode ^ markdownHtml.hashCode;

  @override
  String toString() => 'NoteContent(${plainText.length} chars)';
}
