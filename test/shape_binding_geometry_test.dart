import 'package:drawing_notes_app/core/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PageShapeItem node(
    String id,
    double x,
    double y,
    double width,
    double height,
  ) => PageShapeItem(
    id: id,
    shapeType: ShapeType.rect,
    x: x,
    y: y,
    width: width,
    height: height,
  );

  PageShapeItem arrow() => PageShapeItem(
    id: 'arrow_1',
    shapeType: ShapeType.arrow,
    x: 0,
    y: 0,
    width: 1,
    height: 1,
  );

  test('创建箭头时两端命中形状会保存归一化双端绑定', () {
    final left = node('left', 20, 20, 120, 80);
    final right = node('right', 300, 100, 160, 120);
    final connector = arrow();
    const start = Offset(110, 60);
    const end = Offset(340, 190);

    ShapeBindingGeometry.bindArrowAtEndpoints(
      connector,
      [left, right],
      start: start,
      end: end,
    );

    expect(connector.startBinding?.targetShapeId, 'left');
    expect(connector.endBinding?.targetShapeId, 'right');
    expect(connector.startBinding?.anchorX, closeTo(0.75, 0.0001));
    expect(connector.startBinding?.anchorY, closeTo(0.5, 0.0001));
    expect(connector.endBinding?.anchorX, closeTo(0.25, 0.0001));
    expect(connector.endBinding?.anchorY, closeTo(0.75, 0.0001));

    final endpoints = ShapeBindingGeometry.arrowEndpoints(connector);
    expect(endpoints.start, start);
    expect(endpoints.end, end);
  });

  test('目标移动后箭头只重投影绑定端点并保持另一端', () {
    final left = node('left', 20, 20, 120, 80);
    final right = node('right', 300, 100, 160, 120);
    final connector = arrow();

    ShapeBindingGeometry.bindArrowAtEndpoints(
      connector,
      [left, right],
      start: const Offset(110, 60),
      end: const Offset(340, 190),
    );
    left.x += 40;
    left.y -= 10;

    expect(
      ShapeBindingGeometry.reprojectArrow(connector, [left, right]),
      isTrue,
    );
    final endpoints = ShapeBindingGeometry.arrowEndpoints(connector);
    expect(endpoints.start, const Offset(150, 50));
    expect(endpoints.end, const Offset(340, 190));
  });

  test('单端绑定允许另一端保持自由点', () {
    final left = node('left', 20, 20, 120, 80);
    final connector = arrow();
    const start = Offset(110, 60);
    const end = Offset(260, 180);

    ShapeBindingGeometry.bindArrowAtEndpoints(
      connector,
      [left],
      start: start,
      end: end,
    );

    expect(connector.startBinding?.targetShapeId, 'left');
    expect(connector.endBinding, isNull);
    final endpoints = ShapeBindingGeometry.arrowEndpoints(connector);
    expect(endpoints.start, start);
    expect(endpoints.end, end);
  });

  test('绑定关系随形状 JSON 往返且会夹紧异常锚点', () {
    final connector = PageShapeItem(
      id: 'arrow_1',
      shapeType: ShapeType.arrow,
      x: 20,
      y: 50,
      width: 280,
      height: 80,
      flipY: true,
    );
    connector.startBinding = ShapeBindingGeometry.bindingAt(
      node('left', 20, 20, 120, 80),
      const Offset(110, 60),
    );
    final json = connector.toJson()
      ..['endBinding'] = {
        'targetShapeId': 'right',
        'anchorX': 4,
        'anchorY': -2,
      };

    final restored = PageShapeItem.fromJson(json);

    expect(restored.startBinding?.targetShapeId, 'left');
    expect(restored.startBinding?.anchorX, closeTo(0.75, 0.0001));
    expect(restored.endBinding?.targetShapeId, 'right');
    expect(restored.endBinding?.anchorX, 1);
    expect(restored.endBinding?.anchorY, 0);
  });
}
