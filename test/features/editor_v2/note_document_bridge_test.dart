// NoteDocumentBridge 测试（#13 持久化修复——2026-08-24）。
//
// 测试 NoteDocument ↔ Notebook 双向转换的正确性。
import 'package:flutter_test/flutter_test.dart';

import 'package:editor_core/editor_core.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/bridges/note_document_bridge.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

void main() {
  group('NoteDocumentBridge', () {
    // ──────────────────────────── paragraphsToTextItems ────────────────────────────

    test('paragraphsToTextItems — 空段落列表', () {
      final items = NoteDocumentBridge.paragraphsToTextItems([]);
      expect(items, isEmpty);
    });

    test('paragraphsToTextItems — 单段落（paragraph 类型）', () {
      final paragraphs = [
        const NoteParagraph(id: 'p1', content: '普通段落'),
      ];
      final items = NoteDocumentBridge.paragraphsToTextItems(paragraphs);
      expect(items.length, 1);
      expect(items.first.id, 'p1');
      expect(items.first.text, '普通段落');
      expect(items.first.y, 0.0);
      expect(items.first.fontSize, 16); // paragraph → 16
    });

    test('paragraphsToTextItems — heading 类型 → fontSize=28', () {
      final paragraphs = [
        const NoteParagraph(
          id: 'h1',
          content: '标题',
          type: NoteParagraphType.heading,
        ),
      ];
      final items = NoteDocumentBridge.paragraphsToTextItems(paragraphs);
      expect(items.first.fontSize, 28); // heading → 28
    });

    test('paragraphsToTextItems — 多段落顺序正确', () {
      final paragraphs = [
        const NoteParagraph(id: 'p1', content: '第一段'),
        const NoteParagraph(id: 'p2', content: '第二段'),
        const NoteParagraph(id: 'p3', content: '第三段'),
      ];
      final items = NoteDocumentBridge.paragraphsToTextItems(paragraphs);
      expect(items.length, 3);
      expect(items[0].y, 0.0);
      expect(items[1].y, 1.0);
      expect(items[2].y, 2.0);
      expect(items[0].text, '第一段');
      expect(items[1].text, '第二段');
      expect(items[2].text, '第三段');
    });

    // ──────────────────────────── textItemsToParagraphs ────────────────────────────

    test('textItemsToParagraphs — 空列表 → 默认空段落', () {
      final paragraphs = NoteDocumentBridge.textItemsToParagraphs([]);
      expect(paragraphs.length, 1);
      expect(paragraphs.first.content, '');
    });

    test('textItemsToParagraphs — fontSize>=24 → heading', () {
      final items = [
        PageTextItem(id: 'h1', x: 0, y: 0, text: '标题', fontSize: 28),
      ];
      final paragraphs = NoteDocumentBridge.textItemsToParagraphs(items);
      expect(paragraphs.first.type, NoteParagraphType.heading);
    });

    test('textItemsToParagraphs — fontSize<24 → paragraph', () {
      final items = [
        PageTextItem(id: 'p1', x: 0, y: 0, text: '正文', fontSize: 16),
      ];
      final paragraphs = NoteDocumentBridge.textItemsToParagraphs(items);
      expect(paragraphs.first.type, NoteParagraphType.paragraph);
    });

    test('textItemsToParagraphs — 按 y 坐标排序', () {
      final items = [
        PageTextItem(id: 'p2', x: 0, y: 2, text: '第二段', fontSize: 16),
        PageTextItem(id: 'p1', x: 0, y: 0, text: '第一段', fontSize: 16),
        PageTextItem(id: 'p3', x: 0, y: 1, text: '第三段', fontSize: 16),
      ];
      final paragraphs = NoteDocumentBridge.textItemsToParagraphs(items);
      expect(paragraphs[0].content, '第一段');
      expect(paragraphs[1].content, '第三段');
      expect(paragraphs[2].content, '第二段');
    });

    // ──────────────────────────── applyToNotebook ────────────────────────────

    test('applyToNotebook — 空 notebook → 创建新 page', () {
      final notebook = Notebook(id: 'nb1', title: '笔记本');
      final noteDoc = NoteDocument(
        id: 'nb1',
        title: '我的笔记',
        paragraphs: [
          const NoteParagraph(id: 'p1', content: '内容'),
        ],
      );

      NoteDocumentBridge.applyToNotebook(noteDoc, notebook);

      expect(notebook.pages.length, 1);
      expect(notebook.pages.first.textItems.length, 1);
      expect(notebook.pages.first.textItems.first.text, '内容');
      expect(notebook.title, '我的笔记');
    });

    test('applyToNotebook — 有 page → 更新 textItems', () {
      final notebook = Notebook(
        id: 'nb1',
        title: '旧标题',
        pages: [
          NotebookPage(
            id: 'page1',
            title: '旧页面',
            document: DrawingDocument(id: 'doc1', title: '文档'),
            textItems: [
              PageTextItem(id: 'old', x: 0, y: 0, text: '旧内容', fontSize: 16),
            ],
          ),
        ],
      );
      final noteDoc = NoteDocument(
        id: 'nb1',
        title: '新标题',
        paragraphs: [
          const NoteParagraph(id: 'p1', content: '新内容1'),
          const NoteParagraph(id: 'p2', content: '新内容2'),
        ],
      );

      NoteDocumentBridge.applyToNotebook(noteDoc, notebook);

      expect(notebook.pages.length, 1); // 不新增 page
      expect(notebook.pages.first.textItems.length, 2);
      expect(notebook.pages.first.textItems[0].text, '新内容1');
      expect(notebook.pages.first.textItems[1].text, '新内容2');
      expect(notebook.title, '新标题');
    });

    // ──────────────────────────── fromNotebook ────────────────────────────

    test('fromNotebook — 空 pages → 默认空文档', () {
      final notebook = Notebook(id: 'nb1', title: '笔记本');
      final doc = NoteDocumentBridge.fromNotebook(notebook);

      expect(doc.id, 'nb1');
      expect(doc.title, '笔记本');
      expect(doc.paragraphs.length, 1);
      expect(doc.paragraphs.first.content, '');
    });

    test('fromNotebook — 有 textItems → 正确转换', () {
      final notebook = Notebook(
        id: 'nb1',
        title: '笔记本',
        pages: [
          NotebookPage(
            id: 'page1',
            title: '页面',
            document: DrawingDocument(id: 'doc1', title: '文档'),
            textItems: [
              PageTextItem(
                  id: 'p1', x: 0, y: 0, text: '段落1', fontSize: 16),
              PageTextItem(
                  id: 'h1', x: 0, y: 1, text: '标题', fontSize: 28),
            ],
          ),
        ],
      );
      final doc = NoteDocumentBridge.fromNotebook(notebook);

      expect(doc.paragraphs.length, 2);
      expect(doc.paragraphs[0].content, '段落1');
      expect(doc.paragraphs[0].type, NoteParagraphType.paragraph);
      expect(doc.paragraphs[1].content, '标题');
      expect(doc.paragraphs[1].type, NoteParagraphType.heading);
    });

    // ──────────────────────────── 往返测试（Round-trip） ────────────────────────────

    test('round-trip — NoteDocument → Notebook → NoteDocument 内容一致', () {
      final original = NoteDocument(
        id: 'nb1',
        title: '测试笔记本',
        paragraphs: [
          const NoteParagraph(id: 'p1', content: '第一段正文'),
          const NoteParagraph(
            id: 'h1',
            content: '章节标题',
            type: NoteParagraphType.heading,
          ),
          const NoteParagraph(id: 'p2', content: '第二段正文'),
        ],
      );

      // NoteDocument → Notebook
      final notebook = Notebook(id: 'nb1', title: '测试笔记本');
      NoteDocumentBridge.applyToNotebook(original, notebook);

      // Notebook → NoteDocument
      final restored = NoteDocumentBridge.fromNotebook(notebook);

      expect(restored.title, original.title);
      expect(restored.paragraphs.length, original.paragraphs.length);
      for (var i = 0; i < original.paragraphs.length; i++) {
        expect(restored.paragraphs[i].content, original.paragraphs[i].content);
        expect(restored.paragraphs[i].type, original.paragraphs[i].type);
      }
    });

    test('round-trip — 空文档往返不丢失', () {
      final original = NoteDocument(
        id: 'nb1',
        title: '',
        paragraphs: [const NoteParagraph(id: 'p1', content: '')],
      );

      final notebook = Notebook(id: 'nb1', title: '');
      NoteDocumentBridge.applyToNotebook(original, notebook);
      final restored = NoteDocumentBridge.fromNotebook(notebook);

      expect(restored.paragraphs.length, 1);
      expect(restored.paragraphs.first.content, '');
    });
  });
}
