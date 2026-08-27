import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/application/object_eraser_session.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Stroke makeStroke() => Stroke(
    points: <StrokePoint>[
      const StrokePoint(10, 20, 1),
      const StrokePoint(110, 20, 1),
    ],
    color: const Color(0xFF111111),
    width: 8,
    type: BrushType.pen,
  );

  PageShapeItem makeShape() => PageShapeItem(
    id: 'shape-1',
    shapeType: ShapeType.rect,
    x: 160,
    y: 20,
    width: 80,
    height: 60,
  );

  test('整笔擦除记录笔画与形状的可逆增量，并报告受影响图层', () {
    final stroke = makeStroke();
    final shape = makeShape();
    final document = DrawingDocument(
      id: 'eraser-session',
      title: '对象橡皮擦会话',
      shapes: <PageShapeItem>[shape],
    );
    document.layers.single.strokes.add(stroke);
    final session = ObjectEraserSession()..begin();

    final strokeStep = session.eraseAt(
      document,
      const Offset(60, 20),
      eraserSize: 24,
      mode: EraserMode.stroke,
    );
    final shapeStep = session.eraseAt(
      document,
      const Offset(180, 40),
      eraserSize: 24,
      mode: EraserMode.stroke,
    );

    expect(strokeStep.changed, isTrue);
    expect(strokeStep.changedLayerIndices, <int>{0});
    expect(shapeStep.changed, isTrue);
    expect(shapeStep.changedLayerIndices, isEmpty);
    expect(document.layers.single.strokes, isEmpty);
    expect(document.shapes, isEmpty);

    final result = session.consumeResult();
    expect(result, isNotNull);
    expect(result!.removedStrokes.single.stroke, same(stroke));
    expect(result.removedStrokes.single.layerIndex, 0);
    expect(result.removedShapes, <PageShapeItem>[shape]);
    expect(result.changedLayerIndices, <int>{0});
    expect(session.consumeResult(), isNull);
  });

  test('关闭当前模式的形状擦除开关时保留形状且不产生增量', () {
    final shape = makeShape();
    final document = DrawingDocument(
      id: 'eraser-shape-switch',
      title: '形状橡皮擦开关',
      shapes: <PageShapeItem>[shape],
    );
    final session = ObjectEraserSession()
      ..canEraseShapesStroke = false
      ..begin();

    final step = session.eraseAt(
      document,
      const Offset(180, 40),
      eraserSize: 24,
      mode: EraserMode.stroke,
    );

    expect(step.changed, isFalse);
    expect(document.shapes, <PageShapeItem>[shape]);
    expect(session.consumeResult(), isNull);
  });
}
