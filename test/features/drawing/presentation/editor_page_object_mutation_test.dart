import 'package:drawing_notes_app/features/drawing/domain/page_chart_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/page_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page_object_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('分组标记覆盖文字、图片和形状且返回实际变更数量', () {
    final text = PageTextItem(id: 'text-1', x: 0, y: 0, text: '文字');
    final image = PageImageItem(
      id: 'image-1',
      filePath: '/tmp/image.png',
      x: 0,
      y: 0,
    );
    final shape = PageShapeItem(
      id: 'shape-1',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 40,
      height: 40,
    );

    final changed = EditorPageObjectMutation.setGroupId(
      ids: {'text-1', 'image-1', 'shape-1', 'missing'},
      groupId: 'group-1',
      textItems: [text],
      imageItems: [image],
      shapes: [shape],
    );

    expect(changed, 3);
    expect(text.groupId, 'group-1');
    expect(image.groupId, 'group-1');
    expect(shape.groupId, 'group-1');
  });

  test('删除跨混排对象集合只移除命中的对象并返回数量', () {
    final text = PageTextItem(id: 'text-1', x: 0, y: 0, text: '文字');
    final keptText = PageTextItem(id: 'text-2', x: 0, y: 0, text: '保留');
    final image = PageImageItem(
      id: 'image-1',
      filePath: '/tmp/image.png',
      x: 0,
      y: 0,
    );
    final shape = PageShapeItem(
      id: 'shape-1',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 40,
      height: 40,
    );
    final chart = PageChartItem(
      id: 'chart-1',
      chartType: ChartType.bar,
      data: [1, 2, 3],
    );

    final textItems = [text, keptText];
    final imageItems = [image];
    final shapes = [shape];
    final charts = [chart];

    final removed = EditorPageObjectMutation.remove(
      ids: {'text-1', 'image-1', 'shape-1', 'chart-1', 'missing'},
      textItems: textItems,
      imageItems: imageItems,
      shapes: shapes,
      charts: charts,
    );

    expect(removed, 4);
    expect(textItems, [keptText]);
    expect(imageItems, isEmpty);
    expect(shapes, isEmpty);
    expect(charts, isEmpty);
  });

  test('空 id 集合不会修改任何对象', () {
    final text = PageTextItem(id: 'text-1', x: 0, y: 0, text: '文字');
    final textItems = [text];

    final changed = EditorPageObjectMutation.setGroupId(
      ids: const {},
      groupId: 'group-1',
      textItems: textItems,
      imageItems: const [],
      shapes: const [],
    );
    final removed = EditorPageObjectMutation.remove(
      ids: const {},
      textItems: textItems,
      imageItems: [],
      shapes: [],
      charts: [],
    );

    expect(changed, 0);
    expect(removed, 0);
    expect(text.groupId, isNull);
    expect(textItems, [text]);
  });
}
