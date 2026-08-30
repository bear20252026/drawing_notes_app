import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page_content.dart';
import 'package:drawing_notes_app/features/notes/domain/page_template.dart';

/// 交互式页面模板的默认可编辑内容策略。
///
/// 此策略是纯领域代码：调用方提供标识与创建时间，故它不依赖 Widget、存储、
/// I/O、系统时钟或随机数生成实现。PDF 和文本导入等非模板业务可以复用
/// [createDocument]，但仍自行决定其专有载荷。
class NotebookPageTemplateStrategy {
  const NotebookPageTemplateStrategy._();

  static const int defaultDocumentWidth = 2480;
  static const int defaultDocumentHeight = 3508;

  /// 创建用户从模板对话框新建页面时的完整初始内容。
  static NotebookPageContent createContent({
    required PageTemplate template,
    required String documentId,
    required String documentTitle,
    required DateTime createdAt,
    required String Function() nextTextItemId,
  }) => NotebookPageContent(
    document: createDocument(
      id: documentId,
      title: documentTitle,
      template: template,
    ),
    textItems: createTextItems(
      template: template,
      createdAt: createdAt,
      nextTextItemId: nextTextItemId,
    ),
  );

  /// 创建无混排对象的页面画布。
  ///
  /// 交互式新建默认保持现有 A4 近似尺寸。导入流程可传入自定义宽高以复用
  /// 同一文档基础装配，且不触发模板文字生成。
  static DrawingDocument createDocument({
    required String id,
    required String title,
    PageTemplate template = PageTemplate.blank,
    int width = defaultDocumentWidth,
    int height = defaultDocumentHeight,
  }) => DrawingDocument(
    id: id,
    title: title,
    width: width,
    height: height,
    paperType: template.paperType,
  );

  /// 创建模板预置的页面级文字对象。
  ///
  /// 只有结构化记录模板需要初始文字；其他纸张模板只依赖文档背景。
  static List<PageTextItem> createTextItems({
    required PageTemplate template,
    required DateTime createdAt,
    required String Function() nextTextItemId,
  }) {
    final date = _formatDate(createdAt);
    PageTextItem item(
      double x,
      double y,
      String text, {
      double size = 24,
      bool bold = false,
    }) => PageTextItem(
      id: nextTextItemId(),
      x: x,
      y: y,
      text: text,
      fontSize: size,
      bold: bold,
    );

    return switch (template) {
      PageTemplate.meeting => [
        item(110, 90, '会议主题', size: 38, bold: true),
        item(110, 170, '日期：$date    参与者：', size: 22),
        item(110, 310, '议题', size: 28, bold: true),
        item(110, 1060, '决策', size: 28, bold: true),
        item(110, 1810, '行动项（负责人 / 截止日）', size: 28, bold: true),
      ],
      PageTemplate.cornell => [
        item(110, 90, '主题 / 课程', size: 34, bold: true),
        item(110, 220, '线索与问题', bold: true),
        item(720, 220, '笔记', bold: true),
        item(110, 2920, '总结', bold: true),
      ],
      PageTemplate.planner => [
        item(110, 90, '本周计划', size: 38, bold: true),
        item(110, 240, '最重要的三件事', size: 26, bold: true),
        item(110, 1280, '日程与待办', size: 26, bold: true),
        item(110, 2450, '复盘与下周准备', size: 26, bold: true),
      ],
      PageTemplate.blank ||
      PageTemplate.lined ||
      PageTemplate.grid ||
      PageTemplate.dot ||
      PageTemplate.whiteboard => const [],
    };
  }

  static String _formatDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
