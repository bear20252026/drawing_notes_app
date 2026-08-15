import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_endpoint_binding.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';

/// Q-1 God Class 拆分（2026-08-16）：ShapeBindingGeometry.isBoundTo 解绑
/// 判定纯函数单测（从 DrawingController 提取——独立可测）。
void main() {
  PageShapeItem arrow() => PageShapeItem(
    id: 'arrow_1',
    shapeType: ShapeType.arrow,
    x: 0,
    y: 0,
    width: 1,
    height: 1,
  );

  test('解绑判定：start/end 绑定指向目标返回 true', () {
    final a = arrow();
    a.startBinding = ShapeEndpointBinding(
      targetShapeId: 'a',
      anchorX: 0.5,
      anchorY: 0.5,
    );
    expect(ShapeBindingGeometry.isBoundTo(a, 'a'), isTrue);

    final b = arrow();
    b.endBinding = ShapeEndpointBinding(
      targetShapeId: 'b',
      anchorX: 0.5,
      anchorY: 0.5,
    );
    expect(ShapeBindingGeometry.isBoundTo(b, 'b'), isTrue);
  });

  test('解绑判定：无绑定/指向其他返回 false', () {
    final a = arrow();
    a.startBinding = ShapeEndpointBinding(
      targetShapeId: 'a',
      anchorX: 0.5,
      anchorY: 0.5,
    );
    a.endBinding = ShapeEndpointBinding(
      targetShapeId: 'b',
      anchorX: 0.5,
      anchorY: 0.5,
    );
    expect(ShapeBindingGeometry.isBoundTo(a, 'c'), isFalse);
    expect(ShapeBindingGeometry.isBoundTo(arrow(), 'a'), isFalse);
  });
}
