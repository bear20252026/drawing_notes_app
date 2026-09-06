import 'dart:ui' show Offset, Rect;

import 'package:drawing_notes_app/features/drawing/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PageShapeItem node(
    String id,
    double x,
    double y,
    double width,
    double height,
  ) => PageShapeItem(
    id: id,
    shapeType: ShapeType.rect,
    x: x,
    y: y,
    width: width,
    height: height,
  );

  PageShapeItem arrow() => PageShapeItem(
    id: 'arrow_1',
    shapeType: ShapeType.arrow,
    x: 0,
    y: 0,
    width: 1,
    height: 1,
  );

  test('创建箭头时两端命中形状会保存归一化双端绑定', () {
    final left = node('left', 20, 20, 120, 80);
    final right = node('right', 300, 100, 160, 120);
    final connector = arrow();
    const start = Offset(110, 60);
    const end = Offset(340, 190);

    ShapeBindingGeometry.bindArrowAtEndpoints(
      connector,
      [left, right],
      start: start,
      end: end,
    );

    expect(connector.startBinding?.targetShapeId, 'left');
    expect(connector.endBinding?.targetShapeId, 'right');
    // 审计二-4（2026-09-06）：绑定时刻端点重投影到目标外接框周界——
    // (110,60) 距 left 右边最近 → (140,60)；(340,190) 距 right 底边最近
    // → (340,220)。箭头尖不再悬停在形状内部。
    expect(connector.startBinding?.anchorX, closeTo(1.0, 0.0001));
    expect(connector.startBinding?.anchorY, closeTo(0.5, 0.0001));
    expect(connector.endBinding?.anchorX, closeTo(0.25, 0.0001));
    expect(connector.endBinding?.anchorY, closeTo(1.0, 0.0001));

    final endpoints = ShapeBindingGeometry.arrowEndpoints(connector);
    expect(endpoints.start, const Offset(140, 60));
    expect(endpoints.end, const Offset(340, 220));
  });

  test('目标移动后箭头只重投影绑定端点并保持另一端', () {
    final left = node('left', 20, 20, 120, 80);
    final right = node('right', 300, 100, 160, 120);
    final connector = arrow();

    ShapeBindingGeometry.bindArrowAtEndpoints(
      connector,
      [left, right],
      start: const Offset(110, 60),
      end: const Offset(340, 190),
    );
    left.x += 40;
    left.y -= 10;

    expect(
      ShapeBindingGeometry.reprojectArrow(connector, [left, right]),
      isTrue,
    );
    final endpoints = ShapeBindingGeometry.arrowEndpoints(connector);
    // 锚点 (1.0, 0.5) 在移动后的 left (60,10,120,80) 上投影为右边中点。
    expect(endpoints.start, const Offset(180, 50));
    expect(endpoints.end, const Offset(340, 220));
  });

  test('单端绑定允许另一端保持自由点', () {
    final left = node('left', 20, 20, 120, 80);
    final connector = arrow();
    const start = Offset(110, 60);
    const end = Offset(260, 180);

    ShapeBindingGeometry.bindArrowAtEndpoints(
      connector,
      [left],
      start: start,
      end: end,
    );

    expect(connector.startBinding?.targetShapeId, 'left');
    expect(connector.endBinding, isNull);
    final endpoints = ShapeBindingGeometry.arrowEndpoints(connector);
    expect(endpoints.start, const Offset(140, 60));
    expect(endpoints.end, end);
  });

  test('绑定关系随形状 JSON 往返且会夹紧异常锚点', () {
    final connector = PageShapeItem(
      id: 'arrow_1',
      shapeType: ShapeType.arrow,
      x: 20,
      y: 50,
      width: 280,
      height: 80,
      flipY: true,
    );
    connector.startBinding = ShapeBindingGeometry.bindingAt(
      node('left', 20, 20, 120, 80),
      const Offset(110, 60),
    );
    final json = connector.toJson()
      ..['endBinding'] = {
        'targetShapeId': 'right',
        'anchorX': 4,
        'anchorY': -2,
      };

    final restored = PageShapeItem.fromJson(json);

    expect(restored.startBinding?.targetShapeId, 'left');
    expect(restored.startBinding?.anchorX, closeTo(0.75, 0.0001));
    expect(restored.endBinding?.targetShapeId, 'right');
    expect(restored.endBinding?.anchorX, 1);
    expect(restored.endBinding?.anchorY, 0);
  });

  group('端点磁吸与边框投影（审计二-3/二-4，2026-09-06）', () {
    test('projectPointToBounds：外部点投影到最近边，内部点推到最近边', () {
      const bounds = Rect.fromLTWH(100, 100, 200, 100);
      // 外部：斜向最近处是右上角 (300, 100)。
      expect(
        ShapeBindingGeometry.projectPointToBounds(
          const Offset(340, 60),
          bounds,
        ),
        const Offset(300, 100),
      );
      // 外部正右：垂足 (300, 140)。
      expect(
        ShapeBindingGeometry.projectPointToBounds(
          const Offset(360, 140),
          bounds,
        ),
        const Offset(300, 140),
      );
      // 内部 (150, 130)：到左边 50、右边 150、上边 30、下边 70 → 上边。
      expect(
        ShapeBindingGeometry.projectPointToBounds(
          const Offset(150, 130),
          bounds,
        ),
        const Offset(150, 100),
      );
    });

    test('bindableShapeNear：8px 邻域命中、远离不误绑', () {
      final big = node('big', 0, 0, 400, 300);
      final small = node('small', 500, 100, 40, 40);

      // 距 big 右边 6px（旧按中心 50px 判定会把 big 抢走；现在 8px 邻域
      // 命中 big——按到边框距离，而非中心距离）。
      expect(
        ShapeBindingGeometry.bindableShapeNear(const Offset(406, 150), [
          big,
          small,
        ])?.id,
        'big',
      );
      // 距 small 左边 4px：命中 small 而不是被大形状抢绑。
      expect(
        ShapeBindingGeometry.bindableShapeNear(const Offset(496, 120), [
          big,
          small,
        ])?.id,
        'small',
      );
      // 两形状都不在 8px 内 → 不绑定。
      expect(
        ShapeBindingGeometry.bindableShapeNear(const Offset(460, 260), [
          big,
          small,
        ]),
        isNull,
      );
      // 内部点同样命中（沿用旧语义：内部即命中）。
      expect(
        ShapeBindingGeometry.bindableShapeNear(const Offset(200, 150), [
          big,
          small,
        ])?.id,
        'big',
      );
    });

    test('distanceToSegment：垂线距离与端点钳制', () {
      const a = Offset(0, 0);
      const b = Offset(100, 0);
      expect(
        ShapeBindingGeometry.distanceToSegment(const Offset(50, 30), a, b),
        30,
      );
      // 超出线段端点：距离取到端点，而非垂足。
      expect(
        ShapeBindingGeometry.distanceToSegment(const Offset(130, 40), a, b),
        50,
      );
    });

    test('applyLinearEndpoints：直线也走同一规范化（flip/rotation 归零）', () {
      final line = PageShapeItem(
        id: 'line_1',
        shapeType: ShapeType.line,
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        flipX: true,
        rotation: 0.5,
      );

      ShapeBindingGeometry.applyLinearEndpoints(
        line,
        start: const Offset(120, 80),
        end: const Offset(40, 200),
      );

      expect(line.x, 40);
      expect(line.y, 80);
      expect(line.width, 80);
      expect(line.height, 120);
      expect(line.flipX, isFalse);
      expect(line.flipY, isFalse);
      expect(line.rotation, 0);
      expect(line.lineStart, const Offset(80, 0));
      expect(line.lineEnd, const Offset(0, 120));
    });

    test('globalToLocal 是 localToGlobal 的严格逆变换（含旋转与翻转）', () {
      final shape = PageShapeItem(
        id: 'arrow_r',
        shapeType: ShapeType.arrow,
        x: 200,
        y: 120,
        width: 300,
        height: 160,
        flipX: true,
        rotation: 0.7,
      );
      const local = Offset(90, 40);
      final global = ShapeBindingGeometry.localToGlobal(shape, local);
      expect(
        ShapeBindingGeometry.globalToLocal(shape, global),
        closeToOffset(local, 0.001),
      );
    });
  });
}

/// Offset 的 closeTo 匹配器（逐分量）。
Matcher closeToOffset(Offset value, double epsilon) =>
    _OffsetCloseTo(value, epsilon);

class _OffsetCloseTo extends Matcher {
  _OffsetCloseTo(this._value, this._epsilon);

  final Offset _value;
  final double _epsilon;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is Offset &&
      (item.dx - _value.dx).abs() <= _epsilon &&
      (item.dy - _value.dy).abs() <= _epsilon;

  @override
  Description describe(Description description) =>
      description.add('is within $_epsilon of $_value');
}
