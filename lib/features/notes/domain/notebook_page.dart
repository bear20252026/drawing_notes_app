import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/notes/domain/clone_ref.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page_content.dart';
import 'package:drawing_notes_app/features/notes/domain/page_template.dart';
import 'package:drawing_notes_app/features/notes/domain/page_version.dart';

/// 笔记本中的一个页面。
///
/// 聚合根保存页面库元数据和一个活动 [content]。既有内容访问器继续转发到
/// [content]，从而让编辑器会话持有稳定的对象引用，而快照、恢复和版本上限
/// 由单一领域入口维护。
class NotebookPage {
  NotebookPage({
    required this.id,
    required this.title,
    NotebookPageContent? content,
    DrawingDocument? document,
    List<PageTextItem>? textItems,
    List<PageImageItem>? imageItems,
    this.folder = '',
    this.cloneOf,
    List<String>? tags,
    List<PageVersion>? history,
    List<PageConnector>? connectors,
    List<PageShapeItem>? shapes,
    List<PageChartItem>? charts,
    this.template = PageTemplate.blank,
    this.favorite = false,
    this.lastOpenedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : content =
           content ??
           NotebookPageContent(
             document:
                 document ??
                 (throw ArgumentError.notNull('document when content is null')),
             textItems: textItems,
             imageItems: imageItems,
             connectors: connectors,
             shapes: shapes,
             charts: charts,
           ),
       tags = tags ?? [],
       history = history ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  final NotebookPageContent content;

  DrawingDocument get document => content.document;
  List<PageTextItem> get textItems => content.textItems;
  List<PageImageItem> get imageItems => content.imageItems;
  List<PageConnector> get connectors => content.connectors;
  List<PageShapeItem> get shapes => content.shapes;
  List<PageChartItem> get charts => content.charts;

  /// 分组名（空字符串表示根级）。
  String folder;

  /// 指向源页面的克隆引用；克隆内容解析不在聚合中执行。
  CloneRef? cloneOf;

  /// 跨笔记本检索标签。
  final List<String> tags;

  /// 最近的版本排在索引 0。
  final List<PageVersion> history;

  static const int maxHistoryVersions = 8;

  /// 创建时选定的工作流模板。
  PageTemplate template;

  /// 收藏/置顶标记。
  bool favorite;

  /// 最近一次进入编辑器的时间，不等同于内容更新时间。
  DateTime? lastOpenedAt;
  final DateTime createdAt;
  DateTime updatedAt;

  void touch() => updatedAt = DateTime.now();

  /// 相比最近版本，活动内容是否产生应记录的变化。
  bool get hasChangedSinceLatestVersion => history.isEmpty
      ? !content.isEmpty
      : !content.hasSameContentAs(history.first.content);

  /// 基于最近快照生成面向用户的轻量变更摘要。
  String get changeSummarySinceLatestVersion =>
      _changeSummaryComparedTo(history.isEmpty ? null : history.first);

  /// 创建当前内容的独立版本快照。
  PageVersion captureVersion({required DateTime time, String summary = ''}) =>
      PageVersion.capture(time: time, source: content, summary: summary);

  /// 在历史顶部加入当前内容快照并应用上限。
  PageVersion addVersion({required DateTime time, String summary = ''}) {
    final version = captureVersion(time: time, summary: summary);
    history.insert(0, version);
    if (history.length > maxHistoryVersions) {
      history.removeRange(maxHistoryVersions, history.length);
    }
    return version;
  }

  /// 用某一版本的内容覆盖活动页面。
  ///
  /// [DrawingDocument] 和所有活动集合的身份均保持不变，避免断开正在编辑该页的
  /// 控制器会话；写入值始终来自独立深拷贝。
  void restoreVersion(PageVersion version) =>
      content.replaceWith(version.content);

  String _changeSummaryComparedTo(PageVersion? previous) {
    if (previous == null) return '首次保存';
    final strokesNow = document.layers.fold<int>(
      0,
      (sum, layer) => sum + layer.strokes.length,
    );
    final strokesBefore = previous.document.layers.fold<int>(
      0,
      (sum, layer) => sum + layer.strokes.length,
    );
    final parts = <String>[];
    final strokeDelta = strokesNow - strokesBefore;
    if (strokeDelta != 0) {
      parts.add('笔画${strokeDelta > 0 ? '+' : ''}$strokeDelta');
    }
    if (textItems.length != previous.textItems.length) {
      parts.add(
        '文字${textItems.length > previous.textItems.length ? '+' : ''}'
        '${textItems.length - previous.textItems.length}',
      );
    } else if (_hasTextChanged(previous)) {
      parts.add('文字修改');
    }
    _appendCountDelta(
      parts,
      '图片',
      imageItems.length,
      previous.imageItems.length,
    );
    _appendCountDelta(parts, '形状', shapes.length, previous.shapes.length);
    _appendCountDelta(parts, '图表', charts.length, previous.charts.length);
    _appendCountDelta(
      parts,
      '连线',
      connectors.length,
      previous.connectors.length,
    );
    return parts.isEmpty ? '内容微调' : parts.join(' · ');
  }

  bool _hasTextChanged(PageVersion previous) {
    for (var index = 0; index < textItems.length; index++) {
      if (textItems[index].text != previous.textItems[index].text) return true;
    }
    return false;
  }

  void _appendCountDelta(
    List<String> parts,
    String label,
    int currentCount,
    int previousCount,
  ) {
    final delta = currentCount - previousCount;
    if (delta != 0) parts.add('$label${delta > 0 ? '+' : ''}$delta');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    ...content.toJson(),
    'folder': folder,
    if (cloneOf != null) 'cloneOf': cloneOf!.toJson(),
    'tags': tags,
    'history': history.map((entry) => entry.toJson()).toList(),
    'template': template.name,
    'favorite': favorite,
    if (lastOpenedAt != null) 'lastOpenedAt': lastOpenedAt!.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NotebookPage.fromJson(Map<String, dynamic> json) => NotebookPage(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名页面',
    content: NotebookPageContent.fromJson(json),
    folder: json['folder'] as String? ?? '',
    cloneOf: json['cloneOf'] != null
        ? CloneRef.fromJson(json['cloneOf'] as Map<String, dynamic>)
        : null,
    tags: (json['tags'] as List? ?? const [])
        .map((item) => item.toString())
        .toList(),
    history: (json['history'] as List? ?? const [])
        .map((item) => PageVersion.fromJson(item as Map<String, dynamic>))
        .toList(),
    template: PageTemplate.values.firstWhere(
      (candidate) => candidate.name == json['template'],
      orElse: () => PageTemplate.blank,
    ),
    favorite: json['favorite'] as bool? ?? false,
    lastOpenedAt: DateTime.tryParse(json['lastOpenedAt'] as String? ?? ''),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
