import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('两个画布并行书写时活动笔画与已提交内容严格隔离', () async {
    final controllerA = DrawingController(
      DrawingDocument(id: 'memory_a', title: '内存 A', infinite: true),
    );
    final controllerB = DrawingController(
      DrawingDocument(id: 'memory_b', title: '内存 B', infinite: true),
    );

    controllerA.startStroke(const Offset(10, 20));
    controllerB.startStroke(const Offset(300, 400));
    controllerA.extendStroke(const Offset(50, 60));
    controllerB.extendStroke(const Offset(500, 600));

    expect(controllerA.activeStroke!.points.first.offset, const Offset(10, 20));
    expect(
      controllerB.activeStroke!.points.first.offset,
      const Offset(300, 400),
    );

    await Future.wait([controllerA.endStroke(), controllerB.endStroke()]);

    final strokeA = controllerA.document.layers.single.strokes.single;
    final strokeB = controllerB.document.layers.single.strokes.single;
    expect(strokeA.points.first.offset, const Offset(10, 20));
    expect(strokeB.points.first.offset, const Offset(300, 400));
    expect(strokeA.points.last.offset, const Offset(50, 60));
    expect(strokeB.points.last.offset, const Offset(500, 600));
    expect(identical(controllerA.document, controllerB.document), isFalse);
    expect(identical(strokeA, strokeB), isFalse);

    controllerA.dispose();
    controllerB.dispose();
  });
}
