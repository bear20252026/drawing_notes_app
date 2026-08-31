// 由 Claude 团队生成 | Drawing Notes App
// note_block_doc_migration.dart 单元测试。

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc_migration.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page_content.dart';

void main() {
  group('migrateNotebookPage', () {
    test('空页面迁移后至少一个空 paragraph 块', () {
      final page = NotebookPage(
        id: 'p1',
        title: 'Empty',
        content: NotebookPageContent(
          document: DrawingDocument(id: 'd1', title: ''),
        ),
      );

      final doc = migrateNotebookPage(page);

      expect(doc.id, 'p1');
      expect(doc.title, 'Empty');
      expect(doc.body.length, 1);
      expect(doc.body.first.type, NoteBlockType.text);
      expect(doc.body.first.text, '');
    });

    test('textItems 按顺序转为 text 块', () {
      final page = NotebookPage(
        id: 'p2',
        title: 'Text Page',
        content: NotebookPageContent(
          document: DrawingDocument(id: 'd2', title: ''),
          textItems: [
            PageTextItem(id: 't1', x: 0, y: 0, text: 'First paragraph'),
            PageTextItem(id: 't2', x: 0, y: 30, text: 'Second paragraph'),
          ],
        ),
      );

      final doc = migrateNotebookPage(page);

      expect(doc.body.length, 2);
      expect(doc.body[0].type, NoteBlockType.text);
      expect(doc.body[0].text, 'First paragraph');
      expect(doc.body[1].text, 'Second paragraph');
    });

    test('非空 document 追加 canvas 块', () {
      final docWithStroke = DrawingDocument(
        id: 'd3',
        title: '',
        layers: [
          Layer(
            id: 'l1',
            name: 'Layer 1',
            strokes: [Stroke(points: [], color: Color(0xFF000000), width: 2, type: BrushType.pen)],
          ),
        ],
      );
      final page = NotebookPage(
        id: 'p3',
        title: 'Canvas Page',
        content: NotebookPageContent(
          document: docWithStroke,
          textItems: [PageTextItem(id: 't1', x: 0, y: 0, text: 'Hello')],
        ),
      );

      final doc = migrateNotebookPage(page);

      expect(doc.body.length, 2); // text + canvas
      expect(doc.body[0].type, NoteBlockType.text);
      expect(doc.body[1].type, NoteBlockType.canvas);
      expect(doc.body[1].props['document'], isA<Map<String, dynamic>>());
    });

    test('空 document 不追加 canvas 块', () {
      final page = NotebookPage(
        id: 'p4',
        title: 'No Canvas',
        content: NotebookPageContent(
          document: DrawingDocument(id: 'd4', title: ''),
          textItems: [PageTextItem(id: 't1', x: 0, y: 0, text: 'Only text')],
        ),
      );

      final doc = migrateNotebookPage(page);

      expect(doc.body.length, 1);
      expect(doc.body.first.type, NoteBlockType.text);
    });

    test('charts 非空时追加 chart 块', () {
      final page = NotebookPage(
        id: 'p5',
        title: 'Chart Page',
        content: NotebookPageContent(
          document: DrawingDocument(id: 'd5', title: ''),
          textItems: [PageTextItem(id: 't1', x: 0, y: 0, text: 'Text')],
          charts: [
            PageChartItem(id: 'c1', chartType: ChartType.bar, data: [1, 2, 3]),
          ],
        ),
      );

      final doc = migrateNotebookPage(page);

      expect(doc.body.length, 2); // text + chart
      expect(doc.body[1].type, NoteBlockType.chart);
      expect(doc.body[1].props['chart'], isA<Map<String, dynamic>>());
    });

    test('imageItems 非空时追加 image 块', () {
      final page = NotebookPage(
        id: 'p6',
        title: 'Image Page',
        content: NotebookPageContent(
          document: DrawingDocument(id: 'd6', title: ''),
          textItems: [PageTextItem(id: 't1', x: 0, y: 0, text: 'Text')],
          imageItems: [PageImageItem(id: 'i1', x: 0, y: 0, filePath: 'test.png')],
        ),
      );

      final doc = migrateNotebookPage(page);

      expect(doc.body.length, 2); // text + image
      expect(doc.body[1].type, NoteBlockType.image);
      expect(doc.body[1].props['image'], isA<Map<String, dynamic>>());
    });

    test('includeCharts=false 时不追加 chart 块', () {
      final page = NotebookPage(
        id: 'p7',
        title: 'No Charts',
        content: NotebookPageContent(
          document: DrawingDocument(id: 'd7', title: ''),
          textItems: [PageTextItem(id: 't1', x: 0, y: 0, text: 'Text')],
          charts: [
            PageChartItem(id: 'c1', chartType: ChartType.bar, data: [1, 2, 3]),
          ],
        ),
      );

      final doc = migrateNotebookPage(page, includeCharts: false);

      expect(doc.body.length, 1);
      expect(doc.body.first.type, NoteBlockType.text);
    });

    test('includeImages=false 时不追加 image 块', () {
      final page = NotebookPage(
        id: 'p8',
        title: 'No Images',
        content: NotebookPageContent(
          document: DrawingDocument(id: 'd8', title: ''),
          textItems: [PageTextItem(id: 't1', x: 0, y: 0, text: 'Text')],
          imageItems: [PageImageItem(id: 'i1', x: 0, y: 0, filePath: 'test.png')],
        ),
      );

      final doc = migrateNotebookPage(page, includeImages: false);

      expect(doc.body.length, 1);
      expect(doc.body.first.type, NoteBlockType.text);
    });

    test('不修改源 page（纯函数）', () {
      final page = NotebookPage(
        id: 'p9',
        title: 'Original',
        content: NotebookPageContent(
          document: DrawingDocument(id: 'd9', title: ''),
          textItems: [PageTextItem(id: 't1', x: 0, y: 0, text: 'Original text')],
        ),
      );

      migrateNotebookPage(page);

      expect(page.textItems.length, 1);
      expect(page.textItems.first.text, 'Original text');
      expect(page.title, 'Original');
    });

    test('完整迁移：text + canvas + chart + image', () {
      final fullDoc = DrawingDocument(
        id: 'd10',
        title: '',
        layers: [
          Layer(
            id: 'l1',
            name: 'L1',
            strokes: [Stroke(points: [], color: Color(0xFF000000), width: 2, type: BrushType.pen)],
          ),
        ],
      );
      final page = NotebookPage(
        id: 'p10',
        title: 'Full',
        content: NotebookPageContent(
          document: fullDoc,
          textItems: [
            PageTextItem(id: 't1', x: 0, y: 0, text: 'Line 1'),
            PageTextItem(id: 't2', x: 0, y: 30, text: 'Line 2'),
          ],
          charts: [
            PageChartItem(id: 'c1', chartType: ChartType.line, data: [1, 2, 3]),
          ],
          imageItems: [PageImageItem(id: 'i1', x: 0, y: 0, filePath: 'photo.jpg')],
        ),
      );

      final doc = migrateNotebookPage(page);

      expect(doc.body.length, 5); // 2 text + 1 canvas + 1 chart + 1 image
      expect(doc.body[0].text, 'Line 1');
      expect(doc.body[1].text, 'Line 2');
      expect(doc.body[2].type, NoteBlockType.canvas);
      expect(doc.body[3].type, NoteBlockType.chart);
      expect(doc.body[4].type, NoteBlockType.image);
    });

    test('保留 createdAt / updatedAt', () {
      final created = DateTime(2025, 1, 1);
      final updated = DateTime(2025, 6, 15);
      final page = NotebookPage(
        id: 'p11',
        title: 'Timed',
        content: NotebookPageContent(
          document: DrawingDocument(id: 'd11', title: ''),
        ),
        createdAt: created,
        updatedAt: updated,
      );

      final doc = migrateNotebookPage(page);

      expect(doc.createdAt, created);
      expect(doc.updatedAt, updated);
    });

    test('迁移后的 NoteBlockDoc 可序列化往返', () {
      final page = NotebookPage(
        id: 'p12',
        title: 'Serialize',
        content: NotebookPageContent(
          document: DrawingDocument(id: 'd12', title: ''),
          textItems: [PageTextItem(id: 't1', x: 0, y: 0, text: 'Round trip')],
        ),
      );

      final doc = migrateNotebookPage(page);
      final json = doc.toJson();
      final restored = NoteBlockDoc.fromJson(json);

      expect(restored.id, doc.id);
      expect(restored.title, doc.title);
      expect(restored.body.length, doc.body.length);
      expect(restored.body.first.text, 'Round trip');
    });
  });
}
