import 'package:drawing_notes_app/core/navigation/editor_page_session.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// 将 notes 聚合中的 [NotebookPage] 适配为 drawing 编辑器所需会话。
///
/// 此类是跨 feature 的数据适配边界。它不复制页面对象，因此编辑器对画布、
/// 文字、图片、形状、图表及连接线的变更仍会写入原页面，既有自动保存与
/// 历史快照语义保持不变。
class NotebookPageEditorSession implements EditorPageSession {
  NotebookPageEditorSession(this._page);

  final NotebookPage _page;

  @override
  String get id => _page.id;

  @override
  String get title => _page.title;

  @override
  set title(String value) => _page.title = value;

  @override
  DrawingDocument get document => _page.document;

  @override
  List<PageTextItem> get textItems => _page.textItems;

  @override
  List<PageImageItem> get imageItems => _page.imageItems;

  @override
  List<PageConnector> get connectors => _page.connectors;

  @override
  List<PageShapeItem> get shapes => _page.shapes;

  @override
  List<PageChartItem> get charts => _page.charts;

  @override
  DateTime get updatedAt => _page.updatedAt;

  @override
  set updatedAt(DateTime value) => _page.updatedAt = value;
}
