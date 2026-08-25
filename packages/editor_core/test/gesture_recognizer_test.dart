import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——GestureRecognizer 高级手势测试（纯逻辑——不搞崩）。
void main() {
  test('GestureData：默认值', () {
    const gesture = GestureData(type: GestureType.tap, phase: GesturePhase.began, x: 10, y: 20);
    expect(gesture.type, GestureType.tap);
    expect(gesture.phase, GesturePhase.began);
    expect(gesture.scale, 1.0);
    expect(gesture.rotation, 0.0);
    expect(gesture.isTwoFinger, false);
  });

  test('GestureData：双指手势（focalPoint/fingerDistance）', () {
    const gesture = GestureData(
      type: GestureType.pinch, phase: GesturePhase.updated,
      x: 0, y: 0, x2: 100, y2: 0,
      scale: 1.5,
    );
    expect(gesture.isTwoFinger, true);
    expect(gesture.focalPoint!.x, 50);
    expect(gesture.focalPoint!.y, 0);
    expect(gesture.fingerDistance, 100);
  });

  test('GestureData：copyWith 不可变', () {
    const original = GestureData(type: GestureType.tap, phase: GesturePhase.began, x: 0, y: 0);
    final updated = original.copyWith(type: GestureType.drag, phase: GesturePhase.updated, x: 50, y: 50);
    expect(original.type, GestureType.tap); // 原实例不变。
    expect(updated.type, GestureType.drag);
    expect(updated.x, 50);
  });

  test('recognizeType：tap（几乎没移动 + 短时间）', () {
    final type = GestureRecognizer.recognizeType(
      startX: 0, startY: 0, currentX: 5, currentY: 5, durationMs: 100,
    );
    expect(type, GestureType.tap);
  });

  test('recognizeType：longPress（几乎没移动 + 长时间）', () {
    final type = GestureRecognizer.recognizeType(
      startX: 0, startY: 0, currentX: 5, currentY: 5, durationMs: 600,
    );
    expect(type, GestureType.longPress);
  });

  test('recognizeType：drag（移动距离大）', () {
    final type = GestureRecognizer.recognizeType(
      startX: 0, startY: 0, currentX: 100, currentY: 100, durationMs: 200,
    );
    expect(type, GestureType.drag);
  });

  test('recognizeType：pinch（双指 + 缩放）', () {
    final type = GestureRecognizer.recognizeType(
      startX: 0, startY: 0, currentX: 50, currentY: 0,
      startX2: 100, startY2: 0, currentX2: 200, currentY2: 0,
      durationMs: 200, currentScale: 1.5,
    );
    expect(type, GestureType.pinch);
  });

  test('recognizeType：rotate（双指 + 旋转）', () {
    final type = GestureRecognizer.recognizeType(
      startX: 0, startY: 0, currentX: 50, currentY: 0,
      startX2: 100, startY2: 0, currentX2: 100, currentY2: 50,
      durationMs: 200, currentRotation: 0.5,
    );
    expect(type, GestureType.rotate);
  });

  test('isDoubleTap：双击检测（间隔 < 300ms）', () {
    final now = DateTime.now();
    expect(GestureRecognizer.isDoubleTap(now.subtract(const Duration(milliseconds: 200)), now), true);
    expect(GestureRecognizer.isDoubleTap(now.subtract(const Duration(milliseconds: 500)), now), false);
    expect(GestureRecognizer.isDoubleTap(null, now), false);
  });

  test('velocity：速度计算', () {
    // 100px / 0.5s = 200 px/s。
    expect(GestureRecognizer.velocity(100, 0, 500), closeTo(200, 0.01));
    expect(GestureRecognizer.velocity(0, 0, 500), 0);
    expect(GestureRecognizer.velocity(100, 0, 0), 0); // 时间为 0。
  });

  test('GestureType/Phase 枚举', () {
    expect(GestureType.values.length, 6);
    expect(GesturePhase.values.length, 4);
  });
}
