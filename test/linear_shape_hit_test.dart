// 线性元素命中判定（审计二-5，2026-09-06）：点到线段距离取代外接框。
//
// 细斜线的外接框大片空白不再拦截点击，也不再挡住叠在其后的元素；
// 封闭形状仍走外接框（rough 模式下选择热区可预测）。

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/application/document_object_editing_session.dart';

PageShapeItem _line(
  String id,
  Offset start,
  Offset end, {
  double strokeWidth = 4,
}) => PageShapeItem(
  id: id,
  shapeType: ShapeType.line,
  x: start.dx < end.dx ? start.dx : end.dx,
  y: start.dy < end.dy ? start.dy : end.dy,
  width: (end.dx - start.dx).abs().clamp(1, 10000),
  height: (end.dy - start.dy).abs().clamp(1, 10000),
  strokeWidth: strokeWidth,
  lineStart:
      start -
      Offset(
        start.dx < end.dx ? start.dx : end.dx,
        start.dy < end.dy ? start.dy : end.dy,
      ),
  lineEnd:
      end -
      Offset(
        start.dx < end.dx ? start.dx : end.dx,
        start.dy < end.dy ? start.dy : end.dy,
      ),
);

void main() {
  const shapes = <PageShapeItem>[];

  test('线段本体命中：带宽 = 线宽/2 + 6px', () {
    // 对角线 (0,200) → (200,0)，线宽 4 → 命中带宽 2 + 6 = 8px。
    final line = _line('l1', const Offset(0, 200), const Offset(200, 0));

    // 线上点（中点）命中。
    expect(
      DocumentObjectEditingSession.shapeHitTest(
        line,
        const Offset(100, 100),
        shapes,
      ),
      isTrue,
    );
    // 距线 5px（带宽内）命中。
    expect(
      DocumentObjectEditingSession.shapeHitTest(
        line,
        const Offset(103, 100),
        shapes,
      ),
      isTrue,
    );
    // 距线约 21px 不命中（旧外接框判定会命中——对角线的框盖住三角空白）。
    expect(
      DocumentObjectEditingSession.shapeHitTest(
        line,
        const Offset(20, 150),
        shapes,
      ),
      isFalse,
    );
    // 外接框角落（0,0）距线 141px：旧判定命中、新判定不命中。
    expect(
      DocumentObjectEditingSession.shapeHitTest(line, Offset.zero, shapes),
      isFalse,
    );
  });

  test('粗线命中带随线宽扩大', () {
    final thick = _line(
      'l2',
      const Offset(0, 0),
      const Offset(200, 0),
      strokeWidth: 16,
    );

    // 线上方 12px：带宽 8 + 6 = 14 → 命中。
    expect(
      DocumentObjectEditingSession.shapeHitTest(
        thick,
        const Offset(100, -12),
        shapes,
      ),
      isTrue,
    );
    // 线上方 20px：带宽外。
    expect(
      DocumentObjectEditingSession.shapeHitTest(
        thick,
        const Offset(100, -20),
        shapes,
      ),
      isFalse,
    );
  });

  test('无显式端点的旧文档线回退对角线判定', () {
    final legacy = PageShapeItem(
      id: 'l3',
      shapeType: ShapeType.line,
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      strokeWidth: 4,
    );

    // 回退端点 (0,100) → (100,0)：中点在 (50,50)。
    expect(
      DocumentObjectEditingSession.shapeHitTest(
        legacy,
        const Offset(50, 50),
        shapes,
      ),
      isTrue,
    );
    expect(
      DocumentObjectEditingSession.shapeHitTest(
        legacy,
        const Offset(10, 10),
        shapes,
      ),
      isFalse,
    );
  });

  test('封闭形状仍走外接框包含判定', () {
    final rect = PageShapeItem(
      id: 'r1',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 100,
      height: 60,
      strokeWidth: 4,
    );

    expect(
      DocumentObjectEditingSession.shapeHitTest(
        rect,
        const Offset(50, 30),
        shapes,
      ),
      isTrue,
    );
    expect(
      DocumentObjectEditingSession.shapeHitTest(
        rect,
        const Offset(150, 30),
        shapes,
      ),
      isFalse,
    );
  });
}
