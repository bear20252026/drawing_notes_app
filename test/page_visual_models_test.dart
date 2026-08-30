import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('分页图表模型保持既有 JSON 字段和默认值', () {
    final chart = PageChartItem(
      id: 'chart-1',
      chartType: ChartType.line,
      data: [1, 2.5],
      labels: ['一月', '二月'],
      x: 40,
      y: 60,
      width: 480,
      height: 280,
      color: 0xFF112233,
      zOrder: 5,
    );

    final restored = PageChartItem.fromJson(chart.toJson());

    expect(restored.chartType, ChartType.line);
    expect(restored.data, [1, 2.5]);
    expect(restored.labels, ['一月', '二月']);
    expect(restored.position.dx, 40);
    expect(restored.position.dy, 60);
    expect(restored.width, 480);
    expect(restored.height, 280);
    expect(restored.color, 0xFF112233);
    expect(restored.zOrder, 5);

    final legacy = PageChartItem.fromJson({
      'id': 'legacy-chart',
      'chartType': 'unknown',
    });
    expect(legacy.chartType, ChartType.bar);
    expect(legacy.data, isEmpty);
    expect(legacy.width, 320);
    expect(legacy.height, 200);
  });

  test('分页连接线模型保持既有 JSON 字段和颜色默认值', () {
    final connector = PageConnector(
      id: 'connector-1',
      fromItemId: 'text-1',
      toItemId: 'image-1',
      color: 0xFF445566,
    );

    final restored = PageConnector.fromJson(connector.toJson());
    expect(restored.id, 'connector-1');
    expect(restored.fromItemId, 'text-1');
    expect(restored.toItemId, 'image-1');
    expect(restored.color, 0xFF445566);

    final legacy = PageConnector.fromJson({
      'id': 'legacy-connector',
      'fromItemId': 'a',
      'toItemId': 'b',
    });
    expect(legacy.color, 0xFF42A5F5);
  });
}
