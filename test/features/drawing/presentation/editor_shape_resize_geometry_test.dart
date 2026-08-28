import 'package:drawing_notes_app/features/drawing/presentation/editor_shape_resize_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const original = EditorShapeBounds(x: 100, y: 200, width: 300, height: 400);

  group('EditorShapeResizeGeometry', () {
    test('左和右边手柄分别移动左锚点或保持原点', () {
      final left = EditorShapeResizeGeometry.resize(
        bounds: original,
        handle: EditorShapeResizeHandle.left,
        canvasDelta: const Offset(30, 99),
      );
      final right = EditorShapeResizeGeometry.resize(
        bounds: original,
        handle: EditorShapeResizeHandle.right,
        canvasDelta: const Offset(30, 99),
      );

      expect((left.x, left.y, left.width, left.height), (130, 200, 270, 400));
      expect(
        (right.x, right.y, right.width, right.height),
        (100, 200, 330, 400),
      );
    });

    test('上和下边手柄分别移动上锚点或保持原点', () {
      final top = EditorShapeResizeGeometry.resize(
        bounds: original,
        handle: EditorShapeResizeHandle.top,
        canvasDelta: const Offset(99, 40),
      );
      final bottom = EditorShapeResizeGeometry.resize(
        bounds: original,
        handle: EditorShapeResizeHandle.bottom,
        canvasDelta: const Offset(99, 40),
      );

      expect((top.x, top.y, top.width, top.height), (100, 240, 300, 360));
      expect(
        (bottom.x, bottom.y, bottom.width, bottom.height),
        (100, 200, 300, 440),
      );
    });

    test('四角手柄按对应边组合调整两个轴', () {
      final topLeft = EditorShapeResizeGeometry.resize(
        bounds: original,
        handle: EditorShapeResizeHandle.topLeft,
        canvasDelta: const Offset(30, 40),
      );
      final topRight = EditorShapeResizeGeometry.resize(
        bounds: original,
        handle: EditorShapeResizeHandle.topRight,
        canvasDelta: const Offset(30, 40),
      );
      final bottomLeft = EditorShapeResizeGeometry.resize(
        bounds: original,
        handle: EditorShapeResizeHandle.bottomLeft,
        canvasDelta: const Offset(30, 40),
      );
      final bottomRight = EditorShapeResizeGeometry.resize(
        bounds: original,
        handle: EditorShapeResizeHandle.bottomRight,
        canvasDelta: const Offset(30, 40),
      );

      expect(
        (topLeft.x, topLeft.y, topLeft.width, topLeft.height),
        (130, 240, 270, 360),
      );
      expect(
        (topRight.x, topRight.y, topRight.width, topRight.height),
        (100, 240, 330, 360),
      );
      expect(
        (bottomLeft.x, bottomLeft.y, bottomLeft.width, bottomLeft.height),
        (130, 200, 270, 440),
      );
      expect(
        (bottomRight.x, bottomRight.y, bottomRight.width, bottomRight.height),
        (100, 200, 330, 440),
      );
    });

    test('所有手柄保持既有 20 至 1000 尺寸钳制和左上锚点语义', () {
      const tight = EditorShapeBounds(x: 5, y: 7, width: 30, height: 30);
      final min = EditorShapeResizeGeometry.resize(
        bounds: tight,
        handle: EditorShapeResizeHandle.topLeft,
        canvasDelta: const Offset(100, 100),
      );
      final max = EditorShapeResizeGeometry.resize(
        bounds: original,
        handle: EditorShapeResizeHandle.bottomRight,
        canvasDelta: const Offset(1000, 1000),
      );

      expect((min.x, min.y, min.width, min.height), (105, 107, 20, 20));
      expect((max.x, max.y, max.width, max.height), (100, 200, 1000, 1000));
    });

    test('计算不会修改输入边界', () {
      EditorShapeResizeGeometry.resize(
        bounds: original,
        handle: EditorShapeResizeHandle.bottomRight,
        canvasDelta: const Offset(20, 20),
      );

      expect(
        (original.x, original.y, original.width, original.height),
        (100, 200, 300, 400),
      );
    });
  });
}
