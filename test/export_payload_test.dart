import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/editor_exporter.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

void main() {
  test('导出净化：payload 只含文档域数据，不含 UI 状态（三态分离）', () {
    final doc = DrawingDocument(id: 'd1', title: '净化测试');
    doc.layers.first.strokes.add(
      Stroke(
        points: const [StrokePoint(10, 10, 1)],
        color: const Color(0xFF000000),
        width: 3,
        type: BrushType.pen,
      ),
    );
    final page = NotebookPage(
      id: 'p1',
      title: '第 1 页',
      document: doc,
      textItems: [PageTextItem(id: 't1', x: 0, y: 0, text: '你好')],
    );

    final payload = buildExportPayload(doc, page: page);

    // 文档域数据必须存在。
    expect(payload['type'], 'drawing-notes');
    expect(payload['title'], '净化测试');
    expect(payload['layers'], isA<List>());
    expect(payload['textItems'], isA<List>());
    // UI 状态绝不进入导出（Excalidraw cleanAppStateForExport 边界）。
    expect(payload.containsKey('selection'), isFalse);
    expect(payload.containsKey('viewScale'), isFalse);
    expect(payload.containsKey('viewOffset'), isFalse);
    expect(payload.containsKey('tool'), isFalse);
    expect(payload.containsKey('selectionTool'), isFalse);
  });
}
