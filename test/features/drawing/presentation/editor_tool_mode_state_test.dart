import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_interaction_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('手型模式切换会排他清理框选和形状工具', () {
    final state = EditorToolModeState()..selectShape(ShapeType.ellipse);

    expect(state.toggleHand(), isTrue);

    expect(state.handActive, isTrue);
    expect(state.marqueeActive, isFalse);
    expect(state.activeShape, isNull);
    expect(state.toggleHand(), isFalse);
    expect(state.handActive, isFalse);
  });

  test('框选模式切换会排他清理手型和形状工具', () {
    final state = EditorToolModeState()..selectShape(ShapeType.arrow);

    expect(state.toggleMarquee(), isTrue);

    expect(state.marqueeActive, isTrue);
    expect(state.handActive, isFalse);
    expect(state.activeShape, isNull);
    expect(state.toggleMarquee(), isFalse);
    expect(state.marqueeActive, isFalse);
  });

  test('选择形状与非形状工具均保持互斥模式不变量', () {
    final state = EditorToolModeState()..toggleHand();

    state.selectShape(ShapeType.rect);
    expect(state.handActive, isFalse);
    expect(state.marqueeActive, isFalse);
    expect(state.activeShape, ShapeType.rect);

    state.clearPointerModes();
    expect(state.handActive, isFalse);
    expect(state.marqueeActive, isFalse);
    expect(state.activeShape, isNull);
  });
}
