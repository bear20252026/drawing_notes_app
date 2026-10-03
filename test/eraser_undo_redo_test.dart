import 'dart:ui' show Color, Offset;

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

/// 对象橡皮擦撤销/重做的次序与身份回归（2026-10-03 复核 P0/P1）。
///
/// 两条锁各自的成因：
/// - 形状：撤销时 `copy()` 追加到末尾 → redo 按 identity 移不掉（重做无效）、
///   再次 undo 追加**同 id** 副本（破坏箭头 `firstOrNull` 绑定与按 id 选择，
///   且原样存盘），并丢失原 z 序。
/// - 笔画：同一手势跨采样点记录的是「删除当下」的索引，前一次删除已让列表
///   变短 → 按该索引插回得到错误次序（`BlendMode.clear` 橡皮与高亮笔叠色
///   对次序敏感）。
void main() {
  Stroke strokeAtY(double y) => Stroke(
    points: <StrokePoint>[StrokePoint(10, y, 1), StrokePoint(110, y, 1)],
    color: const Color(0xFF111111),
    width: 4,
    type: BrushType.pen,
  );

  PageShapeItem rectAt(double x) => PageShapeItem(
    id: 'shape-$x',
    shapeType: ShapeType.rect,
    x: x,
    y: 300,
    width: 40,
    height: 40,
  );

  DrawingController controllerWith({
    required List<Stroke> strokes,
    List<PageShapeItem> shapes = const <PageShapeItem>[],
  }) => DrawingController(
    DrawingDocument(
      id: 'eraser-undo',
      title: '橡皮擦撤销',
      width: 400,
      height: 400,
      layers: <Layer>[
        Layer(id: 'layer_1', name: '图层 1', strokes: strokes),
      ],
      shapes: shapes,
    ),
  );

  /// 一次拖擦手势：逐采样点擦除，收笔生成一条撤销记录。
  void eraseGesture(DrawingController c, List<Offset> points) {
    c.beginObjectErase();
    for (final point in points) {
      c.eraseStrokesAt(point);
    }
    c.endObjectErase();
  }

  test('一次手势跨两个采样点擦两条笔画：撤销按原始叠色次序还原', () {
    final a = strokeAtY(20);
    final x = strokeAtY(100);
    final c = strokeAtY(180);
    final controller = controllerWith(strokes: <Stroke>[a, x, c]);
    final strokes = controller.document.layers.single.strokes;

    eraseGesture(controller, <Offset>[const Offset(60, 20), const Offset(60, 180)]);
    expect(strokes, <Stroke>[x]);

    controller.undo();
    expect(
      strokes,
      <Stroke>[a, x, c],
      reason: '按原始序号升序插回：原 [A,X,C] 不得还原成 [A,C,X]',
    );
    expect(identical(strokes[0], a), isTrue, reason: '放回原实例，不复制');

    controller.redo();
    expect(strokes, <Stroke>[x]);

    controller.undo();
    expect(strokes, <Stroke>[a, x, c]);
  });

  test('同一采样点擦除相邻两笔 + 后续采样点擦除第三笔：次序仍还原', () {
    final a = strokeAtY(20);
    final b = strokeAtY(30);
    final c = strokeAtY(180);
    final controller = controllerWith(strokes: <Stroke>[a, b, c]);
    final strokes = controller.document.layers.single.strokes;

    // 半径 12 + 半宽 2：单点 (60,25) 同时命中 A、B，之后的采样点命中 C。
    eraseGesture(controller, <Offset>[const Offset(60, 25), const Offset(60, 180)]);
    expect(strokes, isEmpty);

    controller.undo();
    expect(strokes, <Stroke>[a, b, c]);
  });

  test('擦除形状后 undo→redo→undo：原实例、原 z 序、id 不重复', () {
    final s0 = rectAt(20);
    final s1 = rectAt(200);
    final s2 = rectAt(340);
    final controller = controllerWith(
      strokes: <Stroke>[],
      shapes: <PageShapeItem>[s0, s1, s2],
    );
    final shapes = controller.document.shapes;

    eraseGesture(controller, <Offset>[const Offset(40, 320), const Offset(360, 320)]);
    expect(shapes, <PageShapeItem>[s1]);

    controller.undo();
    expect(
      shapes,
      <PageShapeItem>[s0, s1, s2],
      reason: '原序号插回，不追加到末尾',
    );
    expect(identical(shapes.first, s0), isTrue, reason: '放回原实例');

    controller.redo();
    expect(shapes, <PageShapeItem>[s1], reason: '重做必须真的把形状再移除');

    controller.undo();
    expect(shapes, <PageShapeItem>[s0, s1, s2]);
    expect(
      shapes.map((shape) => shape.id).toSet().length,
      shapes.length,
      reason: '反复回放不得产生同 id 副本（会破坏箭头绑定并按 id 选择）',
    );
  });

  test('一次手势同时擦掉笔画与形状：一条记录整体撤销、整体重做', () {
    final kept = strokeAtY(180);
    final erasedStroke = strokeAtY(20);
    final erasedShape = rectAt(20);
    final survivorShape = rectAt(200);
    final controller = controllerWith(
      strokes: <Stroke>[erasedStroke, kept],
      shapes: <PageShapeItem>[erasedShape, survivorShape],
    );
    final strokes = controller.document.layers.single.strokes;
    final shapes = controller.document.shapes;

    eraseGesture(controller, <Offset>[
      const Offset(60, 20),
      const Offset(40, 320),
    ]);
    expect(strokes, <Stroke>[kept]);
    expect(shapes, <PageShapeItem>[survivorShape]);

    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(strokes, <Stroke>[erasedStroke, kept]);
    expect(shapes, <PageShapeItem>[erasedShape, survivorShape]);
    expect(controller.canRedo, isTrue);

    controller.redo();
    expect(strokes, <Stroke>[kept]);
    expect(shapes, <PageShapeItem>[survivorShape]);

    // 收笔只入栈一条：一次 undo 必须回到擦除前。
    controller.undo();
    expect(strokes, <Stroke>[erasedStroke, kept]);
    expect(shapes, <PageShapeItem>[erasedShape, survivorShape]);
  });

  test('取消手势（cancelObjectErase）按原次序还原，不写历史', () {
    final a = strokeAtY(20);
    final x = strokeAtY(100);
    final c = strokeAtY(180);
    final controller = controllerWith(strokes: <Stroke>[a, x, c]);
    final strokes = controller.document.layers.single.strokes;

    controller.beginObjectErase();
    controller.eraseStrokesAt(const Offset(60, 20));
    controller.eraseStrokesAt(const Offset(60, 180));
    final undoableBefore = controller.canUndo;
    controller.cancelObjectErase();

    expect(strokes, <Stroke>[a, x, c]);
    expect(controller.canUndo, undoableBefore, reason: '取消不产生历史记录');
  });
}
