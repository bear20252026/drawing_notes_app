import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/image_transform_service.dart';

/// Q-1 God Class 拆分（2026-08-16——第五步）：ImageTransformService 图片
/// 缩放纯计算独立单测（从 DrawingController 解耦）。
void main() {
  test('缩放：围绕中心保持比例', () {
    final r = ImageTransformService.clampedScale(
      x: 0,
      y: 0,
      width: 100,
      height: 50,
      factor: 2,
    );
    expect(r.width, 200);
    expect(r.height, 100);
    expect(r.x, -50); // 中心(50,25) 保持 → x = 50 - 100 = -50
    expect(r.y, closeTo(-25, 1e-9)); // y = 25 - 50 = -25
  });

  test('缩放：尺寸 clamp 边界（最小 32/24）', () {
    final r = ImageTransformService.clampedScale(
      x: 0,
      y: 0,
      width: 20,
      height: 10,
      factor: 0.1,
    );
    expect(r.width, 32); // clamp 最小宽度
    expect(r.height, 24); // clamp 最小高度
  });

  test('缩放：缩小保持中心', () {
    final r = ImageTransformService.clampedScale(
      x: 100,
      y: 200,
      width: 100,
      height: 50,
      factor: 0.5,
    );
    expect(r.width, 50);
    expect(r.height, 25);
    expect(r.x, 125); // 中心(150,225) → x = 150 - 25 = 125
    expect(r.y, closeTo(212.5, 1e-9));
  });

  test('形状缩放：围绕中心 + clamp 16 边界', () {
    final r = ImageTransformService.clampedShapeScale(
      center: const Offset(50, 25),
      width: 100,
      height: 50,
      factor: 2,
    );
    expect(r.width, 200);
    expect(r.height, 100);
    expect(r.x, -50); // 中心(50,25) → x = 50 - 100 = -50
    expect(r.y, closeTo(-25, 1e-9));
    // clamp 最小 16（形状最小尺寸）。
    final small = ImageTransformService.clampedShapeScale(
      center: const Offset(0, 0),
      width: 10,
      height: 10,
      factor: 0.1,
    );
    expect(small.width, 16);
    expect(small.height, 16);
  });
}
