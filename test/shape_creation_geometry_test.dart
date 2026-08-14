import 'package:drawing_notes_app/engine/shape_creation_geometry.dart';
import 'package:drawing_notes_app/models/shape_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('点击画布创建居中的默认尺寸形状', () {
    final geometry = ShapeCreationGeometry.fromDrag(
      const Offset(100, 80),
      const Offset(101, 81),
    );
    final shape = geometry.createShape(
      id: 'rect',
      shapeType: ShapeType.rect,
      color: 0xFF000000,
      strokeWidth: 3,
    );

    expect(shape.x, 20);
    expect(shape.y, 25);
    expect(shape.width, 160);
    expect(shape.height, 110);
    expect(shape.flipX, isFalse);
    expect(shape.flipY, isFalse);
  });

  test('向右下拖拽保留实际外接尺寸', () {
    final geometry = ShapeCreationGeometry.fromDrag(
      const Offset(10, 20),
      const Offset(210, 100),
    );

    expect(geometry.x, 10);
    expect(geometry.y, 20);
    expect(geometry.width, 200);
    expect(geometry.height, 80);
    expect(geometry.flipX, isFalse);
    expect(geometry.flipY, isFalse);
  });

  test('向左上拖拽保持外接框并记录线性元素方向', () {
    final geometry = ShapeCreationGeometry.fromDrag(
      const Offset(210, 100),
      const Offset(10, 20),
    );
    final shape = geometry.createShape(
      id: 'arrow',
      shapeType: ShapeType.arrow,
      color: 0xFF3A6EA5,
      strokeWidth: 50,
    );

    expect(shape.x, 10);
    expect(shape.y, 20);
    expect(shape.width, 200);
    expect(shape.height, 80);
    expect(shape.flipX, isTrue);
    expect(shape.flipY, isTrue);
    expect(shape.strokeWidth, 20);
  });
}
