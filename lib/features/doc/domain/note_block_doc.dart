// 由 Claude 团队生成 | Drawing Notes App
// NoteBlockDoc 文档容器：承载一个「文档=笔记」的块模型聚合。
// 纯 Dart，无 flutter/io/controller/存储依赖。

import 'package:drawing_notes_app/features/doc/domain/note_block.dart';

/// 一个「文档=笔记」的块模型聚合根。
///
/// [body] 是文档的正文块列表（有序）。M0 约定：一个文档 = 一个 root 块，
/// 其 children 即正文块列表；这里 [body] 直接持有该 children 列表，
/// 避免多余的根节点包装。[title] 由 NotebookPage 持有，此处可独立设置。
///
/// [body] 字段为 final，但列表内容在 M0 阶段允许通过 [copyWith] 替换。
/// 后续集成时由 NoteBlockEditor 操作后返回新 doc。
class NoteBlockDoc {
  const NoteBlockDoc({
    required this.id,
    this.title = '',
    List<NoteBlock>? body,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  }) : body = body ?? const [];

  /// 文档唯一标识。
  final String id;

  /// 文档标题。
  final String title;

  /// 正文块列表（有序、不可变引用）。
  final List<NoteBlock> body;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后修改时间。
  final DateTime updatedAt;

  /// 标签 id 列表（M12.6 标签系统；标签定义存 TagStore，文档只持 id）。
  final List<String> tags;

  /// 生成含一个空 paragraph 的最小文档。
  factory NoteBlockDoc.empty(String id, {String title = '', DateTime? now}) {
    final timestamp = now ?? DateTime.fromMillisecondsSinceEpoch(0);
    return NoteBlockDoc(
      id: id,
      title: title,
      body: [NoteBlock.textBlock('${id}_b0', text: '')],
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// 是否有正文块。
  bool get hasBlocks => body.isNotEmpty;

  /// 不可变 copyWith。
  NoteBlockDoc copyWith({
    String? id,
    String? title,
    List<NoteBlock>? body,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => NoteBlockDoc(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    tags: tags ?? this.tags,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  // ── 序列化 ─────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body.map((b) => b.toJson()).toList(),
    if (tags.isNotEmpty) 'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NoteBlockDoc.fromJson(Map<String, dynamic> json) => NoteBlockDoc(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    body: (json['body'] as List? ?? const [])
        .map((e) => NoteBlock.fromJson(e as Map<String, dynamic>))
        .toList(),
    tags: (json['tags'] as List? ?? const []).whereType<String>().toList(),
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteBlockDoc &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          _bodyEqual(body, other.body) &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, title, Object.hashAll(body), createdAt, updatedAt);

  @override
  String toString() =>
      'NoteBlockDoc(id: $id, title: "$title", blocks: ${body.length})';
}

bool _bodyEqual(List<NoteBlock> a, List<NoteBlock> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
