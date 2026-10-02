import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/application/object_eraser_session.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
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

  // P-06（审计 2026-09-27）：eraseAt 必须报告被擦对象的包围盒作为脏矩形，
  // 供调用方做增量图层重建。
  //
  // 回归锁的要点是**下界**：脏区一旦比对象小，增量重建就会在对象边缘留
  // 下残影（整层重建时不会有这个问题——这正是原实现「正确但慢」的地方，
  // 改成增量后必须保证不丢覆盖）。故断言用「覆盖对象的原始外接范围」，
  // 而非与 strokeBounds 逐像素比对（后者只能证明同源，证不了不偏小）。
  test('P-06：脏矩形覆盖被擦笔画与形状的外接范围，空采样为 null', () {
    final stroke = makeStroke(); // (10,20)-(110,20)，width 8
    final shape = makeShape(); // x160 y20 w80 h60
    final document = DrawingDocument(
      id: 'eraser-dirty',
      title: '脏矩形',
      shapes: <PageShapeItem>[shape],
    );
    document.layers.single.strokes.add(stroke);
    final session = ObjectEraserSession()..begin();

    // 1) 擦笔画：脏区须覆盖原始点集外接范围（10..110 × 20..20）。
    final strokeStep = session.eraseAt(
      document,
      const Offset(60, 20),
      eraserSize: 24,
      mode: EraserMode.stroke,
    );
    expect(strokeStep.changed, isTrue);
    final sDirty = strokeStep.dirty;
    expect(sDirty, isNotNull, reason: '擦除笔画必须给出脏矩形');
    expect(sDirty!.left, lessThanOrEqualTo(10));
    expect(sDirty.right, greaterThanOrEqualTo(110));
    expect(sDirty.top, lessThanOrEqualTo(20));
    expect(sDirty.bottom, greaterThanOrEqualTo(20));

    // 2) 擦形状：脏区须覆盖 160..240 × 20..80（含描边外扩）。
    final shapeStep = session.eraseAt(
      document,
      const Offset(180, 40),
      eraserSize: 24,
      mode: EraserMode.stroke,
    );
    expect(shapeStep.changed, isTrue);
    final shDirty = shapeStep.dirty;
    expect(shDirty, isNotNull, reason: '擦除形状必须给出脏矩形');
    expect(shDirty!.left, lessThanOrEqualTo(160));
    expect(shDirty.right, greaterThanOrEqualTo(240));
    expect(shDirty.top, lessThanOrEqualTo(20));
    expect(shDirty.bottom, greaterThanOrEqualTo(80));

    // 3) 未命中任何对象：changed=false 且脏区为 null——
    //    调用方拿到 null 会退回整层重建，方向是安全侧。
    final missStep = session.eraseAt(
      document,
      const Offset(900, 900),
      eraserSize: 24,
      mode: EraserMode.stroke,
    );
    expect(missStep.changed, isFalse);
    expect(missStep.dirty, isNull);
    expect(missStep.changedLayerIndices, isEmpty);
  });
}
