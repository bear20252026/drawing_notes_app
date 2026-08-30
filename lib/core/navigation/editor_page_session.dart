import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';

/// 编辑器在“笔记页面模式”中所需的最小可变会话。
///
/// 该契约刻意只表达画布、混排对象与页面展示元数据；笔记本的文件夹、
/// 标签、版本历史、加密等聚合管理职责仍留在 notes feature。这样 drawing
/// presentation 可编辑分页内容而不直接依赖 notes 的 [NotebookPage] 聚合。
abstract interface class EditorPageSession {
  String get id;

  String get title;
  set title(String value);

  DrawingDocument get document;
  List<PageTextItem> get textItems;
  List<PageImageItem> get imageItems;
  List<PageConnector> get connectors;
  List<PageShapeItem> get shapes;
  List<PageChartItem> get charts;

  DateTime get updatedAt;
  set updatedAt(DateTime value);
}
