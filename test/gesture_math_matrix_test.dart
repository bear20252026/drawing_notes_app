import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/gesture_math.dart';

/// 审计改造（2026-08-15）：vector_math Matrix3 矩阵化视口变换。
/// 验证矩阵版与函数版数学严格等价（行为不变）+ 正逆互逆。
void main() {
  final rng = Random(42);

  Offset randPoint() => Offset(rng.nextDouble() * 2000 - 1000, rng.nextDouble() * 2000 - 1000);

  test('viewTransformMatrix 与 canvasToViewPoint 等价（100 组随机输入）', () {
    for (var i = 0; i < 100; i++) {
      final scale = rng.nextDouble() * 4 + 0.1;
      final angle = rng.nextDouble() * 2 * pi - pi;
      final center = randPoint();
      final offset = randPoint();
      final p = randPoint();

      final m = viewTransformMatrix(scale, angle, center, offset);
      final viaMatrix = canvasToViewPointMatrix(m, p);
      final viaFunction = canvasToViewPoint(p, scale, angle, center, offset);

      expect(
        (viaMatrix - viaFunction).distance,
        lessThan(1e-6),
        reason: '第 $i 组：矩阵版($viaMatrix) vs 函数版($viaFunction)',
      );
    }
  });

  test('viewToCanvasPointMatrix 与 viewToCanvasPoint 等价（100 组随机输入）', () {
    for (var i = 0; i < 100; i++) {
      final scale = rng.nextDouble() * 4 + 0.1;
      final angle = rng.nextDouble() * 2 * pi - pi;
      final center = randPoint();
      final offset = randPoint();
      final p = randPoint();

      final m = viewTransformMatrix(scale, angle, center, offset);
      final viaMatrix = viewToCanvasPointMatrix(m, p);
      final viaFunction = viewToCanvasPoint(p, scale, angle, center, offset);

      expect(
        (viaMatrix - viaFunction).distance,
        lessThan(1e-6),
        reason: '第 $i 组：矩阵版($viaMatrix) vs 函数版($viaFunction)',
      );
    }
  });

  test('矩阵正逆互逆：canvas→view→canvas 还原（视口契约）', () {
    for (var i = 0; i < 50; i++) {
      final scale = rng.nextDouble() * 4 + 0.1;
      final angle = rng.nextDouble() * 2 * pi - pi;
      final center = randPoint();
      final offset = randPoint();
      final p = randPoint();

      final m = viewTransformMatrix(scale, angle, center, offset);
      final view = canvasToViewPointMatrix(m, p);
      final back = viewToCanvasPointMatrix(m, view);

      expect(
        (back - p).distance,
        lessThan(1e-6),
        reason: '第 $i 组：往返误差($back) vs 原点($p)',
      );
    }
  });
}
