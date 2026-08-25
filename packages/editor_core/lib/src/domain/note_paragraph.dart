// editor_core——NoteParagraph 笔记文档段落（AFFiNE Page 借鉴——2026-08-22）。
//
// 用户需求：笔记区域就是一个笔记——像 Word 文档一样可以直接打字。
// 段落模型（Word 文档式——paragraph/heading）——AFFiNE 块编辑器本地化。
// 纯 Dart 不可变——可独立测试——不搞崩。
library;

/// 笔记段落类型（Word 文档式——AFFiNE 块类型本地化）。
enum NoteParagraphType {
  /// 正文段落（直接打字——Word 式）。
  paragraph,

  /// 标题（H1-H6 简化——H2 级别）。
  heading,
}

/// 笔记段落（Word 文档式——不可变）。
class NoteParagraph {
  const NoteParagraph({
    required this.id,
    required this.content,
    this.type = NoteParagraphType.paragraph,
  });

  final String id;

  /// 段落内容（直接打字——Word 式）。
  final String content;

  /// 段落类型（paragraph/heading）。
  final NoteParagraphType type;

  NoteParagraph copyWith({String? content, NoteParagraphType? type}) {
    return NoteParagraph(
      id: id,
      content: content ?? this.content,
      type: type ?? this.type,
    );
  }

  /// 是否标题。
  bool get isHeading => type == NoteParagraphType.heading;

  /// JSON 序列化。
  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'type': type.name,
      };

  /// JSON 反序列化。
  factory NoteParagraph.fromJson(Map<String, dynamic> json) => NoteParagraph(
        id: json['id'] as String? ?? '',
        content: json['content'] as String? ?? '',
        type: NoteParagraphType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => NoteParagraphType.paragraph,
        ),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NoteParagraph && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 笔记文档（Word 文档式——段落列表——不可变）。
class NoteDocument {
  const NoteDocument({this.id = '', this.title = '未命名笔记', this.paragraphs = const []});

  final String id;
  final String title;

  /// 段落列表（Word 文档——直接打字）。
  final List<NoteParagraph> paragraphs;

  NoteDocument copyWith({String? title, List<NoteParagraph>? paragraphs}) {
    return NoteDocument(
      id: id,
      title: title ?? this.title,
      paragraphs: paragraphs ?? this.paragraphs,
    );
  }

  int get paragraphCount => paragraphs.length;

  /// 全文（拼接——导出/搜索）。
  String get fullText => paragraphs.map((p) => p.content).join('\n');

  /// JSON 序列化。
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'paragraphs': paragraphs.map((p) => p.toJson()).toList(),
      };

  /// JSON 反序列化。
  factory NoteDocument.fromJson(Map<String, dynamic> json) => NoteDocument(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '未命名笔记',
        paragraphs: (json['paragraphs'] as List<dynamic>?)
                ?.map((e) => NoteParagraph.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NoteDocument && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
