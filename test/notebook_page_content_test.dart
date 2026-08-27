import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NotebookPage createPage() => NotebookPage(
    id: 'page-1',
    title: '项目计划',
    document: DrawingDocument(
      id: 'doc-1',
      title: '画布',
      paperType: PaperType.grid,
    ),
    textItems: [PageTextItem(id: 'text-1', x: 10, y: 20, text: '原始文字')],
    imageItems: [
      PageImageItem(
        id: 'image-1',
        x: 30,
        y: 40,
        width: 100,
        height: 80,
        filePath: '/tmp/reference.png',
      ),
    ],
    connectors: [
      PageConnector(
        id: 'connector-1',
        fromItemId: 'text-1',
        toItemId: 'image-1',
      ),
    ],
    shapes: [
      PageShapeItem(
        id: 'shape-1',
        shapeType: ShapeType.rect,
        x: 50,
        y: 60,
        width: 70,
        height: 90,
      ),
    ],
    charts: [
      PageChartItem(id: 'chart-1', chartType: ChartType.bar, data: [1, 2, 3]),
    ],
  );

  test('版本快照深拷贝完整载荷，后续活动页面修改不会污染历史', () {
    final page = createPage();

    final version = page.addVersion(
      time: DateTime.utc(2026, 8, 27, 4),
      summary: '首次保存',
    );
    page.document.title = '已修改画布';
    page.textItems.single.text = '已修改文字';
    page.imageItems.clear();
    page.connectors.clear();
    page.shapes.clear();
    page.charts.clear();

    expect(version.content, isNot(same(page.content)));
    expect(version.document, isNot(same(page.document)));
    expect(version.document.title, '画布');
    expect(version.textItems.single.text, '原始文字');
    expect(version.imageItems, hasLength(1));
    expect(version.connectors, hasLength(1));
    expect(version.shapes, hasLength(1));
    expect(version.charts.single.data, [1, 2, 3]);
  });

  test('任一可编辑载荷变化都会触发版本记录，空页面不会产生首个版本', () {
    final emptyPage = NotebookPage(
      id: 'empty',
      title: '空白',
      document: DrawingDocument(id: 'empty-doc', title: '空白'),
    );
    expect(emptyPage.hasChangedSinceLatestVersion, isFalse);

    final page = createPage();
    expect(page.hasChangedSinceLatestVersion, isTrue);
    page.addVersion(time: DateTime.utc(2026, 8, 27, 4));
    expect(page.hasChangedSinceLatestVersion, isFalse);

    page.charts.single.data.add(4);
    expect(page.hasChangedSinceLatestVersion, isTrue);
    page.addVersion(time: DateTime.utc(2026, 8, 27, 5));

    page.connectors.clear();
    expect(page.hasChangedSinceLatestVersion, isTrue);
    expect(page.changeSummarySinceLatestVersion, '连线-1');
  });

  test('恢复版本保留活动内容引用、完整替换内容并维持历史上限', () {
    final page = createPage();
    final document = page.document;
    final textItems = page.textItems;
    final images = page.imageItems;
    final shapes = page.shapes;
    final version = page.addVersion(time: DateTime.utc(2026, 8, 27, 4));

    page.document
      ..title = '临时修改'
      ..paperType = PaperType.lined
      ..infinite = true;
    page.textItems.single.text = '临时文字';
    page.imageItems.clear();
    page.shapes.clear();
    page.restoreVersion(version);

    expect(page.document, same(document));
    expect(page.textItems, same(textItems));
    expect(page.imageItems, same(images));
    expect(page.shapes, same(shapes));
    expect(page.document.title, '画布');
    expect(page.document.paperType, PaperType.grid);
    expect(page.document.infinite, isFalse);
    expect(page.textItems.single.text, '原始文字');
    expect(page.imageItems, hasLength(1));
    expect(page.shapes, hasLength(1));

    for (var index = 0; index < NotebookPage.maxHistoryVersions + 2; index++) {
      page.addVersion(time: DateTime.utc(2026, 8, 28, index));
    }
    expect(page.history, hasLength(NotebookPage.maxHistoryVersions));
  });
}
