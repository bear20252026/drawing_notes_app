import 'package:drawing_notes_app/features/drawing/infrastructure/shape_creation_geometry.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
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

  group('单击阈值 8px（审计二-7，2026-09-06）', () {
    test('位移 5px 仍判定为单击（旧阈值 4px 会误判为拖拽）', () {
      final geometry = ShapeCreationGeometry.fromDrag(
        const Offset(100, 80),
        const Offset(105, 80),
      );

      expect(geometry.isClick, isTrue);
      expect(geometry.width, 160);
      expect(geometry.height, 110);
    });

    test('位移 8px 以上判定为拖拽', () {
      final geometry = ShapeCreationGeometry.fromDrag(
        const Offset(100, 80),
        const Offset(110, 80),
      );

      expect(geometry.isClick, isFalse);
      expect(geometry.width, 10);
    });
  });

  group('角度吸附（审计二-1，2026-09-06）', () {
    test('偏离 0° 在容差内吸附为水平并保持长度', () {
      final snapped = ShapeCreationGeometry.snapDragAngle(
        const Offset(100, 100),
        const Offset(240, 112),
      );

      expect(snapped.dy, closeTo(100, 0.0001));
      expect(
        (snapped - const Offset(100, 100)).distance,
        closeTo(140.51, 0.01),
      );
    });

    test('偏离超过容差不吸附', () {
      const end = Offset(240, 130);

      expect(
        ShapeCreationGeometry.snapDragAngle(
          const Offset(100, 100),
          end,
          toleranceDegrees: 5,
        ),
        end,
      );
    });

    test('force（Shift）无视容差吸附到最近 45° 方向', () {
      final snapped = ShapeCreationGeometry.snapDragAngle(
        const Offset(100, 100),
        const Offset(240, 130),
        force: true,
      );

      final delta = snapped - const Offset(100, 100);
      expect(delta.direction, closeTo(0, 0.0001)); // 最近方向是 0°
      expect(delta.distance, closeTo(143.18, 0.01)); // 长度保持
    });

    test('45° 斜线吸附', () {
      final snapped = ShapeCreationGeometry.snapDragAngle(
        const Offset(0, 0),
        const Offset(100, 91),
      );

      expect(snapped.dx, closeTo(snapped.dy, 0.0001));
      expect(
        (snapped - Offset.zero).distance,
        closeTo(135.21, 0.01),
      );
    });
  });

  group('snappedDragPoints 档位（网格优先于角度）', () {
    test('网格档：两端对齐 20px 网格且不做角度吸附', () {
      final result = ShapeCreationGeometry.snappedDragPoints(
        const Offset(13, 27),
        const Offset(113, 91),
        linear: true,
        gridSnapEnabled: true,
      );

      expect(result.start, const Offset(20, 20));
      expect(result.end, const Offset(120, 100));
    });

    test('线性非网格档：终点做角度吸附', () {
      final result = ShapeCreationGeometry.snappedDragPoints(
        const Offset(100, 100),
        const Offset(240, 110),
        linear: true,
      );

      expect(result.start, const Offset(100, 100));
      expect(result.end.dy, closeTo(100, 0.0001));
    });

    test('网格档对非线性元素同样生效（不做角度吸附）', () {
      final result = ShapeCreationGeometry.snappedDragPoints(
        const Offset(13, 27),
        const Offset(113, 91),
        linear: false,
        gridSnapEnabled: true,
      );

      expect(result.start, const Offset(20, 20));
      expect(result.end, const Offset(120, 100));
    });
  });
}
