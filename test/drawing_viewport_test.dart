import 'package:drawing_notes_app/features/drawing/application/drawing_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('视图与画布坐标在缩放、平移和旋转后保持严格互逆', () {
    final viewport = DrawingViewport()
      ..scale = 1.75
      ..offset = const Offset(-86, 42)
      ..rotation = 0.37;
    const canvasCenter = Offset(500, 350);
    const canvasPoint = Offset(180.25, 712.75);

    final viewPoint = viewport.canvasToView(
      canvasPoint,
      canvasCenter: canvasCenter,
    );
    final restored = viewport.viewToCanvas(
      viewPoint,
      canvasCenter: canvasCenter,
    );

    expect(restored.dx, closeTo(canvasPoint.dx, 0.000001));
    expect(restored.dy, closeTo(canvasPoint.dy, 0.000001));
  });

  test('零旋转的视口投影保持缩放和平移的预期关系', () {
    final viewport = DrawingViewport()
      ..scale = 2
      ..offset = const Offset(10, -20);
    const canvasCenter = Offset(100, 100);

    expect(
      viewport.canvasToView(const Offset(120, 80), canvasCenter: canvasCenter),
      const Offset(150, 40),
    );
  });
}
