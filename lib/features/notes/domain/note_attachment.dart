// 笔记附件/PDF/书签卡领域模型（P3-3）。
// 纯 Dart，无 flutter/io 外部依赖；不可变；值类型 ==/hashCode。

/// 附件类型：普通文件 / PDF / 书签。
enum AttachmentKind { file, pdf, bookmark }

/// 附件/PDF/书签卡的领域模型。
///
/// 不可变：所有字段 final，copyWith 返回新实例。
/// 值类型：基于全部字段的 == 与 hashCode。
class NoteAttachment {
  const NoteAttachment({
    required this.id,
    required this.name,
    required this.kind,
    this.mimeType = '',
    this.byteSize = 0,
    this.filePath = '',
    this.url = '',
    this.description = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// 唯一标识。
  final String id;

  /// 显示名称。
  final String name;

  /// 附件类型。
  final AttachmentKind kind;

  /// MIME 类型（如 'application/pdf'）。
  final String mimeType;

  /// 文件大小（字节）。
  final int byteSize;

  /// 本地文件路径。
  final String filePath;

  /// 远程 URL 或书签链接。
  final String url;

  /// 描述。
  final String description;

  /// 创建时间。
  final DateTime createdAt;

  /// 更新时间。
  final DateTime updatedAt;

  /// 是否可内嵌显示：PDF 与书签可内嵌，普通文件不可。
  bool get isEmbeddable =>
      kind == AttachmentKind.pdf || kind == AttachmentKind.bookmark;

  /// 副标题展示文案。
  ///
  /// - pdf: `'PDF · <formatBytes>'`
  /// - file: `'<formatBytes>'`
  /// - bookmark: url
  String get displaySubtitle {
    switch (kind) {
      case AttachmentKind.pdf:
        return 'PDF · ${formatBytes(byteSize)}';
      case AttachmentKind.file:
        return formatBytes(byteSize);
      case AttachmentKind.bookmark:
        return url;
    }
  }

  /// 不可变更新：返回仅变更指定字段的新实例。
  NoteAttachment copyWith({
    String? id,
    String? name,
    AttachmentKind? kind,
    String? mimeType,
    int? byteSize,
    String? filePath,
    String? url,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => NoteAttachment(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    mimeType: mimeType ?? this.mimeType,
    byteSize: byteSize ?? this.byteSize,
    filePath: filePath ?? this.filePath,
    url: url ?? this.url,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// 序列化为 JSON（DateTime → ISO8601 字符串）。
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'mimeType': mimeType,
    'byteSize': byteSize,
    'filePath': filePath,
    'url': url,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 从 JSON 反序列化（ISO8601 字符串 → DateTime）。
  factory NoteAttachment.fromJson(Map<String, dynamic> json) => NoteAttachment(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: AttachmentKind.values.byName(json['kind'] as String),
    mimeType: (json['mimeType'] as String?) ?? '',
    byteSize: (json['byteSize'] as int?) ?? 0,
    filePath: (json['filePath'] as String?) ?? '',
    url: (json['url'] as String?) ?? '',
    description: (json['description'] as String?) ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteAttachment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          kind == other.kind &&
          mimeType == other.mimeType &&
          byteSize == other.byteSize &&
          filePath == other.filePath &&
          url == other.url &&
          description == other.description &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    mimeType,
    byteSize,
    filePath,
    url,
    description,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'NoteAttachment(id: $id, name: $name, kind: $kind, byteSize: $byteSize)';
}

/// 把字节数格式化为可读字符串。
///
/// - `< 1024` → `'<bytes> B'`
/// - `< 1024*1024` → `'<bytes~/1024> KB'`
/// - `< 1024^3` → `'<bytes~/1048576> MB'`
/// - 否则 → `'<bytes~/1073741824> GB'`
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;

  if (bytes < kb) {
    return '$bytes B';
  } else if (bytes < mb) {
    return '${bytes ~/ kb} KB';
  } else if (bytes < gb) {
    return '${bytes ~/ mb} MB';
  } else {
    return '${bytes ~/ gb} GB';
  }
}
