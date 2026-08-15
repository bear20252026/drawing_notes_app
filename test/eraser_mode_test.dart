import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Stroke> addStroke(
    DrawingController controller,
    Offset from,
    Offset to,
  ) async {
    controller.tool = BrushType.pen;
    controller.brushSize = 10;
    controller.startStroke(from);
    controller.extendStroke(to);
    await controller.endStroke();
    return controller.document.layers.single.strokes.last;
  }

  test('整笔橡皮擦命中一条线时真实删除对象而不创建橡皮擦笔画', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'eraser_stroke', title: '整笔擦除'),
    );
    final first = await addStroke(
      controller,
      const Offset(10, 20),
      const Offset(120, 20),
    );
    final second = await addStroke(
      controller,
      const Offset(10, 120),
      const Offset(120, 120),
    );

    controller.eraserMode = EraserMode.stroke;
    controller.eraserSize = 28;
    controller.beginObjectErase();
    expect(controller.eraseStrokesAt(const Offset(70, 20)), isTrue);
    controller.endObjectErase();

    final remaining = controller.document.layers.single.strokes;
    expect(remaining, [second]);
    expect(remaining.any((stroke) => stroke.type == BrushType.eraser), isFalse);

    controller.undo();
    expect(
      controller.document.layers.single.strokes,
      containsAll([first, second]),
    );
    controller.redo();
    expect(controller.document.layers.single.strokes, [second]);
    controller.dispose();
  });

  test('取消整笔橡皮擦手势会还原已命中的笔画', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'eraser_cancel', title: '取消擦除'),
    );
    final stroke = await addStroke(
      controller,
      const Offset(0, 0),
      const Offset(100, 0),
    );

    controller.beginObjectErase();
    controller.eraseStrokesAt(const Offset(50, 0));
    expect(controller.document.layers.single.strokes, isEmpty);
    controller.cancelObjectErase();

    expect(controller.document.layers.single.strokes, [stroke]);
    controller.dispose();
  });

  test('透明像素模式仍以透明橡皮擦轨迹提交，供合成器局部挖空', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'eraser_pixel', title: '透明擦除'),
    );
    controller.tool = BrushType.eraser;
    controller.eraserMode = EraserMode.pixel;
    controller.eraserSize = 36;
    controller.startStroke(const Offset(20, 20));
    controller.extendStroke(const Offset(80, 20));
    await controller.endStroke();

    final eraserStroke = controller.document.layers.single.strokes.single;
    expect(eraserStroke.type, BrushType.eraser);
    expect(eraserStroke.width, 36);
    expect(eraserStroke.color.a, 0);
    controller.dispose();
  });
}
