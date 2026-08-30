import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_page_editor_session.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NotebookPageEditorSession 只暴露编辑所需字段并写回原始页面', () {
    final document = DrawingDocument(id: 'doc-1', title: '画布');
    final text = PageTextItem(id: 'text-1', x: 1, y: 2, text: '文字');
    final image = PageImageItem(
      id: 'image-1',
      filePath: '/tmp/image.png',
      x: 3,
      y: 4,
      width: 100,
      height: 80,
    );
    final connector = PageConnector(
      id: 'connector-1',
      fromItemId: 'text-1',
      toItemId: 'image-1',
    );
    final shape = PageShapeItem(
      id: 'shape-1',
      shapeType: ShapeType.rect,
      x: 5,
      y: 6,
      width: 70,
      height: 50,
      color: 0xFF000000,
    );
    final chart = PageChartItem(
      id: 'chart-1',
      chartType: ChartType.bar,
      x: 7,
      y: 8,
      width: 120,
      height: 90,
      data: const <double>[1, 2],
    );
    final page = NotebookPage(
      id: 'page-1',
      title: '原始标题',
      document: document,
      textItems: <PageTextItem>[text],
      imageItems: <PageImageItem>[image],
      connectors: <PageConnector>[connector],
      shapes: <PageShapeItem>[shape],
      charts: <PageChartItem>[chart],
    );
    final session = NotebookPageEditorSession(page);
    final changedAt = DateTime.utc(2026, 8, 27, 3, 0);

    expect(session.id, page.id);
    expect(session.document, same(document));
    expect(session.textItems, same(page.textItems));
    expect(session.imageItems, same(page.imageItems));
    expect(session.connectors, same(page.connectors));
    expect(session.shapes, same(page.shapes));
    expect(session.charts, same(page.charts));

    session.title = '更新后的标题';
    session.updatedAt = changedAt;
    session.textItems.add(
      PageTextItem(id: 'text-2', x: 9, y: 10, text: '新增文字'),
    );

    expect(page.title, '更新后的标题');
    expect(page.updatedAt, changedAt);
    expect(page.textItems, hasLength(2));
  });
}
