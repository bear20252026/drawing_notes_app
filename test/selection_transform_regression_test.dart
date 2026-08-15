import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> addLine(
    DrawingController controller,
    Offset from,
    Offset to,
  ) async {
    controller.startStroke(from);
    controller.extendStroke(to);
    await controller.endStroke();
  }

  test('稀疏长笔画穿过矩形选区时也能被圈中', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'lasso-cross', title: '套索交叉'),
    );
    await addLine(controller, const Offset(-100, 0), const Offset(100, 0));

    controller.selectionTool = SelectionTool.rect;
    controller.beginSelection(const Offset(-10, -10));
    controller.extendSelection(const Offset(10, 10));
    controller.endSelection();

    expect(controller.hasSelectedStrokes, isTrue);
    controller.dispose();
  });

  test('缩放围绕实际选中笔画中心，不围绕大套索中心漂移', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'lasso-center', title: '套索中心'),
    );
    await addLine(controller, const Offset(90, 100), const Offset(110, 100));

    controller.selectionTool = SelectionTool.rect;
    // 故意画出远大于内容的选区；旧实现会围绕 (0,0) 缩放。
    controller.beginSelection(const Offset(-1000, -1000));
    controller.extendSelection(const Offset(1000, 1000));
    controller.endSelection();
    controller.scaleSelectedStrokes(2);
    controller.endTransform();

    final points = controller.document.layers.single.strokes.single.points;
    expect(points.first.offset, const Offset(80, 100));
    expect(points.last.offset, const Offset(120, 100));
    controller.dispose();
  });
}
