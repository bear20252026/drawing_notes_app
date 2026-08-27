import 'package:drawing_notes_app/features/notes/domain/notebook_page.dart';

/// 笔记本加密模式。
enum EncryptionMode {
  /// 记忆密码派生密钥。
  password,

  /// U 盘保存的随机主密钥。
  keyfile,
}

/// 多个页面的分类与持久化聚合。
///
/// 加密后的可编辑页面不以明文落盘；解锁后才填充 [pages]。加密、密钥管理、
/// I/O 与界面刷新仍分别属于基础设施、会话和展示层。
class Notebook {
  Notebook({
    required this.id,
    required this.title,
    List<NotebookPage>? pages,
    this.encrypted = false,
    this.encryptionMode = EncryptionMode.password,
    this.encryptedPayload,
    this.recoveryEnvelope,
    this.searchSummary = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : pages = pages ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  final List<NotebookPage> pages;
  bool encrypted;
  EncryptionMode encryptionMode;
  String? encryptedPayload;
  String? recoveryEnvelope;
  String searchSummary;
  final DateTime createdAt;
  DateTime updatedAt;

  void touch() => updatedAt = DateTime.now();

  static const int searchSummaryMaxChars = 200;

  /// 构建标题及文字块开头组成的脱敏检索摘要。
  static String buildSearchSummary(Notebook notebook) {
    final buffer = StringBuffer(notebook.title);
    for (final page in notebook.pages) {
      for (final text in page.textItems) {
        if (buffer.length >= searchSummaryMaxChars) break;
        buffer
          ..write(' ')
          ..write(text.text);
      }
    }
    final summary = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return summary.length > searchSummaryMaxChars
        ? summary.substring(0, searchSummaryMaxChars)
        : summary;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'pages': encrypted ? const [] : pages.map((page) => page.toJson()).toList(),
    'encrypted': encrypted,
    'encryptionMode': encryptionMode.name,
    if (encryptedPayload != null) 'encryptedPayload': encryptedPayload,
    if (recoveryEnvelope != null) 'recoveryEnvelope': recoveryEnvelope,
    if (searchSummary.isNotEmpty) 'searchSummary': searchSummary,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名笔记本',
    pages: (json['pages'] as List? ?? const [])
        .map((item) => NotebookPage.fromJson(item as Map<String, dynamic>))
        .toList(),
    encrypted: json['encrypted'] as bool? ?? false,
    encryptionMode: EncryptionMode.values.firstWhere(
      (mode) => mode.name == json['encryptionMode'],
      orElse: () => EncryptionMode.password,
    ),
    encryptedPayload: json['encryptedPayload'] as String?,
    recoveryEnvelope: json['recoveryEnvelope'] as String?,
    searchSummary: json['searchSummary'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
