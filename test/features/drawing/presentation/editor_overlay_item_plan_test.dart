import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_overlay_item_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PageTextItem text(String id, int zOrder) =>
      PageTextItem(id: id, x: 0, y: 0, text: id, zOrder: zOrder);

  PageImageItem image(String id, int zOrder) => PageImageItem(
    id: id,
    x: 0,
    y: 0,
    filePath: '/assets/$id.png',
    zOrder: zOrder,
  );

  PageShapeItem shape(String id, int zOrder) => PageShapeItem(
    id: id,
    shapeType: ShapeType.rect,
    x: 0,
    y: 0,
    zOrder: zOrder,
  );

  PageChartItem chart(String id, int zOrder) => PageChartItem(
    id: id,
    chartType: ChartType.bar,
    data: const <double>[1],
    zOrder: zOrder,
  );

  test('画布计划只按层级排序文字对象', () {
    final top = text('top', 20);
    final bottom = text('bottom', 10);

    final plan = EditorOverlayItemPlan.forCanvas(<PageTextItem>[top, bottom]);

    expect(plan.map((entry) => entry.id), <String>['bottom', 'top']);
    expect(plan.map((entry) => entry.kind), <EditorOverlayItemKind>[
      EditorOverlayItemKind.text,
      EditorOverlayItemKind.text,
    ]);
    expect(plan.first.text, same(bottom));
  });

  test('笔记页计划合并四类对象并保留类型化领域载荷', () {
    final aText = text('text', 40);
    final anImage = image('image', 10);
    final aShape = shape('shape', 30);
    final aChart = chart('chart', 20);

    final plan = EditorOverlayItemPlan.forPage(
      textItems: <PageTextItem>[aText],
      imageItems: <PageImageItem>[anImage],
      shapes: <PageShapeItem>[aShape],
      charts: <PageChartItem>[aChart],
    );

    expect(plan.map((entry) => entry.id), <String>[
      'image',
      'chart',
      'shape',
      'text',
    ]);
    expect(plan.map((entry) => entry.kind), <EditorOverlayItemKind>[
      EditorOverlayItemKind.image,
      EditorOverlayItemKind.chart,
      EditorOverlayItemKind.shape,
      EditorOverlayItemKind.text,
    ]);
    expect(plan[0].image, same(anImage));
    expect(plan[1].chart, same(aChart));
    expect(plan[2].shape, same(aShape));
    expect(plan[3].text, same(aText));
  });

  test('显示计划为只读快照，不受调用方集合后续增项影响', () {
    final source = <PageTextItem>[text('base', 1)];

    final plan = EditorOverlayItemPlan.forCanvas(source);
    source.add(text('later', 2));

    expect(plan.map((entry) => entry.id), <String>['base']);
    expect(
      () => plan.add(EditorOverlayItemPlanEntry.text(text('new', 3))),
      throwsUnsupportedError,
    );
  });
}
