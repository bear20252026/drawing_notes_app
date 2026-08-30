import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page_content.dart';

/// 页面版本快照。
///
/// 保存 [time]、完整可编辑页面 [content] 与相对上一版的 [summary]。旧构造
/// 参数和字段访问器继续保留，令已有存储格式及调用方无需迁移。
class PageVersion {
  PageVersion({
    required this.time,
    NotebookPageContent? content,
    DrawingDocument? document,
    List<PageTextItem>? textItems,
    List<PageImageItem>? imageItems,
    List<PageConnector>? connectors,
    List<PageShapeItem>? shapes,
    List<PageChartItem>? charts,
    this.summary = '',
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
           );

  /// 捕获 [source] 的独立深拷贝，供历史记录使用。
  factory PageVersion.capture({
    required DateTime time,
    required NotebookPageContent source,
    String summary = '',
  }) => PageVersion(time: time, content: source.deepCopy(), summary: summary);

  final DateTime time;
  final NotebookPageContent content;
  final String summary;

  DrawingDocument get document => content.document;
  List<PageTextItem> get textItems => content.textItems;
  List<PageImageItem> get imageItems => content.imageItems;
  List<PageConnector> get connectors => content.connectors;
  List<PageShapeItem> get shapes => content.shapes;
  List<PageChartItem> get charts => content.charts;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    ...content.toJson(),
    'summary': summary,
  };

  factory PageVersion.fromJson(Map<String, dynamic> json) => PageVersion(
    time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
    content: NotebookPageContent.fromJson(json),
    summary: json['summary'] as String? ?? '',
  );
}
