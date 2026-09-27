// C-01 解环（审计 2026-09-27）：整本/多页导出的单页数据契约下沉 core。
//
// 此前该类定义在 features/notes/application/notebook_pdf_exporter.dart，
// 导致 drawing/application → notes/application 直连（与 notes →
// drawing/rendering 合力构成 feature 级环，文件级无环故门禁测不到）。
// 契约下沉后 drawing 与 notes 各自只依赖 core 只读结构，由组合根
// （default_editor_page_builder）注入合成引擎实现。

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';

/// 整本/多页导出的单页数据（与 notes 聚合根 NotebookPage 解耦的最小
/// 结构——笔记本整本与编辑器多会话共用同一管线，drawing 侧只需按此
/// 结构供数，不触碰 notes 聚合）。
class NotebookPrintPageData {
  const NotebookPrintPageData({
    required this.id,
    required this.title,
    required this.document,
    required this.textItems,
    required this.imageItems,
    required this.shapes,
  });

  final String id;
  final String title;
  final DrawingDocument document;
  final List<PageTextItem> textItems;
  final List<PageImageItem> imageItems;
  final List<PageShapeItem> shapes;
}
