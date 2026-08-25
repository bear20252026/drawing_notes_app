/// NoteDocumentBridge 单元测试（2026-08-25）
library;

import 'package:drawing_notes_app/core/bridges/note_document_bridge.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:editor_core/editor_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteDocumentBridge.paragraphsToTextItems', () {
    test('空列表返回空', () {
      expect(
        NoteDocumentBridge.paragraphsToTextItems([]),
        isEmpty,
      );
    });

    test('段落转换为文本项', () {
      final paragraphs = [
        const NoteParagraph(
          id: 'p1',
          content: '标题',
          type: NoteParagraphType.heading,
        ),
        const NoteParagraph(
          id: 'p2',
          content: '正文',
        ),
      ];
      final items = NoteDocumentBridge.paragraphsToTextItems(paragraphs);
      expect(items.length, 2);
      expect(items[0].id, 'p1');
      expect(items[0].text, '标题');
      expect(items[0].fontSize, 28);
      expect(items[1].id, 'p2');
      expect(items[1].text, '正文');
      expect(items[1].fontSize, 16);
    });

    test('标题字号 28，段落字号 16', () {
      final paragraphs = [
        const NoteParagraph(id: 'h', content: 'H', type: NoteParagraphType.heading),
        const NoteParagraph(id: 'p', content: 'P'),
      ];
      final items = NoteDocumentBridge.paragraphsToTextItems(paragraphs);
      expect(items[0].fontSize, 28);
      expect(items[1].fontSize, 16);
    });

    test('未知类型默认 16', () {
      final paragraphs = [
        const NoteParagraph(id: 'p1', content: 'text'),
      ];
      final items = NoteDocumentBridge.paragraphsToTextItems(paragraphs);
      expect(items[0].fontSize, 16);
    });
  });

  group('NoteDocumentBridge.textItemsToParagraphs', () {
    test('空列表返回默认段落', () {
      final paragraphs = NoteDocumentBridge.textItemsToParagraphs([]);
      expect(paragraphs.length, 1);
      expect(paragraphs[0].id, 'p_default');
      expect(paragraphs[0].content, '');
    });

    test('文本项按 y 排序后转换为段落', () {
      final items = [
        PageTextItem(id: 'b', x: 0, y: 1, text: 'B', fontSize: 16),
        PageTextItem(id: 'a', x: 0, y: 0, text: 'A', fontSize: 28),
      ];
      final paragraphs = NoteDocumentBridge.textItemsToParagraphs(items);
      expect(paragraphs.length, 2);
      expect(paragraphs[0].content, 'A');
      expect(paragraphs[0].type, NoteParagraphType.heading);
      expect(paragraphs[1].content, 'B');
      expect(paragraphs[1].type, NoteParagraphType.paragraph);
    });

    test('fontSize >= 24 被识别为标题', () {
      final items = [
        PageTextItem(id: 't', x: 0, y: 0, text: 'Title'),
        PageTextItem(id: 's', x: 0, y: 1, text: 'Sub', fontSize: 23),
      ];
      final paragraphs = NoteDocumentBridge.textItemsToParagraphs(items);
      expect(paragraphs[0].type, NoteParagraphType.heading);
      expect(paragraphs[1].type, NoteParagraphType.paragraph);
    });
  });

  group('NoteDocumentBridge.applyToNotebook', () {
    test('空 notebook 创建新页面', () {
      final notebook = Notebook(id: 'nb1', title: 'Test');
      const doc = NoteDocument(
        id: 'nb1',
        title: 'Updated',
        paragraphs: [
          NoteParagraph(id: 'p1', content: '内容'),
        ],
      );

      NoteDocumentBridge.applyToNotebook(doc, notebook);

      expect(notebook.title, 'Updated');
      expect(notebook.pages.length, 1);
      expect(notebook.pages.first.textItems.length, 1);
      expect(notebook.pages.first.textItems[0].text, '内容');
    });

    test('已有页面则更新第一页', () {
      final notebook = Notebook(
        id: 'nb2',
        title: 'Old',
        pages: [
          NotebookPage(
            id: 'page1',
            title: 'P1',
            document: DrawingDocument(id: 'doc1', title: 'D'),
            textItems: [
              PageTextItem(id: 'old', x: 0, y: 0, text: 'Old', fontSize: 16),
            ],
          ),
        ],
      );
      const doc = NoteDocument(
        id: 'nb2',
        title: 'New',
        paragraphs: [
          NoteParagraph(id: 'p1', content: '新内容'),
        ],
      );

      NoteDocumentBridge.applyToNotebook(doc, notebook);

      expect(notebook.title, 'New');
      expect(notebook.pages.length, 1);
      expect(notebook.pages.first.textItems[0].text, '新内容');
    });
  });

  group('NoteDocumentBridge.fromNotebook', () {
    test('空页面 notebook 返回默认段落', () {
      final notebook = Notebook(id: 'nb3', title: 'Empty');
      final doc = NoteDocumentBridge.fromNotebook(notebook);
      expect(doc.id, 'nb3');
      expect(doc.title, 'Empty');
      expect(doc.paragraphs.length, 1);
      expect(doc.paragraphs[0].id, 'p_default');
    });

    test('有页面的 notebook 正确转换', () {
      final notebook = Notebook(
        id: 'nb4',
        title: 'WithPages',
        pages: [
          NotebookPage(
            id: 'page1',
            title: 'P1',
            document: DrawingDocument(id: 'doc1', title: 'D'),
            textItems: [
              PageTextItem(id: 't1', x: 0, y: 0, text: 'Title', fontSize: 28),
              PageTextItem(id: 't2', x: 0, y: 1, text: 'Body', fontSize: 16),
            ],
          ),
        ],
      );
      final doc = NoteDocumentBridge.fromNotebook(notebook);
      expect(doc.paragraphs.length, 2);
      expect(doc.paragraphs[0].type, NoteParagraphType.heading);
      expect(doc.paragraphs[1].type, NoteParagraphType.paragraph);
    });
  });
}
