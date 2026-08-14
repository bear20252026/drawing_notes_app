import 'package:drawing_notes_app/engine/editor_input_arbiter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

PointerDownEvent _down(int pointer, PointerDeviceKind kind) =>
    PointerDownEvent(pointer: pointer, kind: kind, position: Offset.zero);

PointerMoveEvent _move(int pointer, PointerDeviceKind kind) => PointerMoveEvent(
  pointer: pointer,
  kind: kind,
  position: const Offset(10, 10),
);

PointerUpEvent _up(int pointer, PointerDeviceKind kind) => PointerUpEvent(
  pointer: pointer,
  kind: kind,
  position: const Offset(10, 10),
);

void main() {
  const inkPolicy = EditorInputPolicy(allowInk: true);

  test('触控笔开始墨迹，手掌触控被拒绝', () {
    final arbiter = EditorInputArbiter();

    expect(
      arbiter.onDown(_down(1, PointerDeviceKind.stylus), policy: inkPolicy),
      EditorPointerDisposition.startInk,
    );
    expect(
      arbiter.onDown(_down(2, PointerDeviceKind.touch), policy: inkPolicy),
      EditorPointerDisposition.ignore,
    );
    expect(arbiter.activePointerCount, 1);
    expect(
      arbiter.onMove(_move(1, PointerDeviceKind.stylus)),
      EditorPointerDisposition.continueInk,
    );
  });

  test('第二个非手掌指针触发视图手势并取消意外墨迹', () {
    final arbiter = EditorInputArbiter();

    arbiter.onDown(_down(1, PointerDeviceKind.mouse), policy: inkPolicy);
    expect(
      arbiter.onDown(_down(2, PointerDeviceKind.mouse), policy: inkPolicy),
      EditorPointerDisposition.cancelInkForViewportGesture,
    );
    expect(
      arbiter.onMove(_move(1, PointerDeviceKind.mouse)),
      EditorPointerDisposition.updateViewportGesture,
    );
  });

  test('关闭手指书写时单指触控只进入视图手势', () {
    final arbiter = EditorInputArbiter();

    expect(
      arbiter.onDown(_down(1, PointerDeviceKind.touch), policy: inkPolicy),
      EditorPointerDisposition.beginViewportGesture,
    );
  });

  test('用户显式允许后手指可以开始墨迹并在抬起时结束', () {
    final arbiter = EditorInputArbiter();
    const fingerPolicy = EditorInputPolicy(
      allowInk: true,
      allowFingerDrawing: true,
    );

    expect(
      arbiter.onDown(_down(1, PointerDeviceKind.touch), policy: fingerPolicy),
      EditorPointerDisposition.startInk,
    );
    expect(
      arbiter.onUp(_up(1, PointerDeviceKind.touch)),
      EditorPointerDisposition.finishInk,
    );
  });
}
