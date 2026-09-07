import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DrawingDocument createDocument() =>
      DrawingDocument(id: 'doc-1', title: '测试页面', paperType: PaperType.dot);

  test('NotebookPage round trip retains template and library metadata', () {
    final lastOpenedAt = DateTime.utc(2026, 8, 14, 10, 30);
    final page = NotebookPage(
      id: 'page-1',
      title: '会议记录',
      document: createDocument(),
      template: PageTemplate.meeting,
      favorite: true,
      lastOpenedAt: lastOpenedAt,
      tags: ['项目', '周会'],
    );

    final restored = NotebookPage.fromJson(page.toJson());

    expect(restored.template, PageTemplate.meeting);
    expect(restored.favorite, isTrue);
    expect(restored.lastOpenedAt, lastOpenedAt);
    expect(restored.tags, ['项目', '周会']);
  });

  test('PageVersion round trip retains every editable page object', () {
    final version = PageVersion(
      time: DateTime.utc(2026, 8, 14, 10),
      document: createDocument(),
      textItems: [PageTextItem(id: 'text-1', x: 10, y: 20, text: '会议结论')],
      imageItems: [
        PageImageItem(
          id: 'image-1',
          x: 30,
          y: 40,
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
        PageShapeItem(id: 'shape-1', shapeType: ShapeType.rect, x: 50, y: 60),
      ],
      charts: [
        PageChartItem(id: 'chart-1', chartType: ChartType.bar, data: [1, 2, 3]),
      ],
      summary: '完整快照',
    );

    final restored = PageVersion.fromJson(version.toJson());

    expect(restored.textItems.single.text, '会议结论');
    expect(restored.imageItems.single.filePath, '/tmp/reference.png');
    expect(restored.connectors.single.fromItemId, 'text-1');
    expect(restored.shapes.single.shapeType, ShapeType.rect);
    expect(restored.charts.single.data, [1, 2, 3]);
    expect(restored.summary, '完整快照');
  });

  test('G22：fromJson 加载侧执行 maxHistoryVersions 上限（无界历史截断）', () {
    final page = NotebookPage(
      id: 'page-h',
      title: '历史',
      document: createDocument(),
    );
    // 构造带 8 版历史的页面（addVersion 逐版封顶），再在 JSON 层复制成
    // 16 条——模拟手改/旧数据携带无界历史的场景。
    for (var i = 0; i < 20; i++) {
      page.addVersion(time: DateTime.utc(2026, 8, 1, 0, i), summary: 'v$i');
    }
    final history = page.toJson()['history'] as List;
    expect(history.length, NotebookPage.maxHistoryVersions); // 写入侧已封顶
    final inflated = Map<String, dynamic>.from(page.toJson())
      ..['history'] = [...history, ...history];

    final restored = NotebookPage.fromJson(inflated);

    // 加载侧与 addVersion 同一常量封顶，且保留头部（最近版本在前）。
    expect(restored.history.length, NotebookPage.maxHistoryVersions);
    expect(
      restored.history.map((v) => v.summary).toList(),
      history
          .take(NotebookPage.maxHistoryVersions)
          .map((e) => (e as Map<String, dynamic>)['summary'] as String?)
          .toList(),
    );
  });
}
