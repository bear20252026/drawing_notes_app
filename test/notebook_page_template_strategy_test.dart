import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 27, 9, 30);

  String Function() nextId(List<String> emitted) {
    var index = 0;
    return () {
      final id = 'text-${++index}';
      emitted.add(id);
      return id;
    };
  }

  test('策略创建保持默认页面尺寸、纸张映射和稳定的文档标识', () {
    for (final template in PageTemplate.values) {
      final emitted = <String>[];
      final content = NotebookPageTemplateStrategy.createContent(
        template: template,
        documentId: 'doc-${template.name}',
        documentTitle: '页面-${template.name}',
        createdAt: createdAt,
        nextTextItemId: nextId(emitted),
      );

      expect(content.document.id, 'doc-${template.name}');
      expect(content.document.title, '页面-${template.name}');
      expect(
        content.document.width,
        NotebookPageTemplateStrategy.defaultDocumentWidth,
      );
      expect(
        content.document.height,
        NotebookPageTemplateStrategy.defaultDocumentHeight,
      );
      expect(content.document.paperType, template.paperType);
      expect(content.document.infinite, isFalse);
    }
  });

  test('会议、康奈尔与计划模板生成既有文字布局并由调用方生成标识', () {
    final meetingIds = <String>[];
    final meeting = NotebookPageTemplateStrategy.createTextItems(
      template: PageTemplate.meeting,
      createdAt: createdAt,
      nextTextItemId: nextId(meetingIds),
    );
    expect(meetingIds, ['text-1', 'text-2', 'text-3', 'text-4', 'text-5']);
    expect(meeting.map((item) => item.text), [
      '会议主题',
      '日期：2026-08-27    参与者：',
      '议题',
      '决策',
      '行动项（负责人 / 截止日）',
    ]);
    expect(meeting.map((item) => item.y), [90, 170, 310, 1060, 1810]);
    expect(meeting.first.fontSize, 38);
    expect(meeting.first.bold, isTrue);
    expect(meeting[1].fontSize, 22);
    expect(meeting[1].bold, isFalse);

    final cornell = NotebookPageTemplateStrategy.createTextItems(
      template: PageTemplate.cornell,
      createdAt: createdAt,
      nextTextItemId: nextId(<String>[]),
    );
    expect(cornell.map((item) => item.text), ['主题 / 课程', '线索与问题', '笔记', '总结']);
    expect(cornell.map((item) => item.x), [110, 110, 720, 110]);
    expect(cornell.map((item) => item.y), [90, 220, 220, 2920]);

    final planner = NotebookPageTemplateStrategy.createTextItems(
      template: PageTemplate.planner,
      createdAt: createdAt,
      nextTextItemId: nextId(<String>[]),
    );
    expect(planner.map((item) => item.text), [
      '本周计划',
      '最重要的三件事',
      '日程与待办',
      '复盘与下周准备',
    ]);
    expect(planner.map((item) => item.fontSize), [38, 26, 26, 26]);
    expect(planner.every((item) => item.bold), isTrue);
  });

  test('非结构化模板不生成文字，自定义尺寸文档可供导入复用', () {
    for (final template in [
      PageTemplate.blank,
      PageTemplate.lined,
      PageTemplate.grid,
      PageTemplate.dot,
      PageTemplate.whiteboard,
    ]) {
      var idCalls = 0;
      final textItems = NotebookPageTemplateStrategy.createTextItems(
        template: template,
        createdAt: createdAt,
        nextTextItemId: () {
          idCalls++;
          return 'unexpected';
        },
      );
      expect(textItems, isEmpty);
      expect(idCalls, 0);
    }

    final importedDocument = NotebookPageTemplateStrategy.createDocument(
      id: 'pdf-page-1',
      title: '参考资料 · 1',
      width: 1200,
      height: 1800,
    );
    expect(importedDocument.id, 'pdf-page-1');
    expect(importedDocument.size.width, 1200);
    expect(importedDocument.size.height, 1800);
    expect(importedDocument.paperType, PaperType.blank);
  });
}
