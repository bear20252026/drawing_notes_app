import 'dart:math' as math;

import 'package:drawing_notes_app/features/drawing/presentation/editor_interaction_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连续缩放返回相对倍率并保留最新滑块值', () {
    final state = EditorSelectionTransformState();

    expect(state.updateScale(1.5), 1.5);
    expect(state.updateScale(0.75), 0.5);
    expect(state.scaleValue, 0.75);
  });

  test('连续旋转返回弧度增量并保留最新角度', () {
    final state = EditorSelectionTransformState();

    expect(state.updateRotationDegrees(90), closeTo(math.pi / 2, 0.000001));
    expect(state.updateRotationDegrees(45), closeTo(-math.pi / 4, 0.000001));
    expect(state.rotationDegrees, 45);
  });

  test('复位会恢复缩放与旋转滑块的安全默认值', () {
    final state = EditorSelectionTransformState()
      ..updateScale(2)
      ..updateRotationDegrees(120);

    state.reset();

    expect(state.scaleValue, 1);
    expect(state.rotationDegrees, 0);
  });
}
