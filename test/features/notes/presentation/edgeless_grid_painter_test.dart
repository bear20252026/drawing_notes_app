import 'package:drawing_notes_app/features/notes/domain/edgeless_camera.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EdgelessGridPainter（2026-09-24 无限画布真无限网格）', () {
    const viewport = Size(1920, 1080);

    test('stepFor：zoom 1 时基础步长 64，缩小时倍增保证屏幕间距达标', () {
      expect(EdgelessGridPainter.stepFor(1.0), 64.0);
      expect(EdgelessGridPainter.stepFor(10.0), 64.0);
      // 64*0.5=32 ≥24 → 64；64*0.3=19.2 <24 → 128（128*0.3=38.4）。
      expect(EdgelessGridPainter.stepFor(0.5), 64.0);
      expect(EdgelessGridPainter.stepFor(0.3), 128.0);
      // 最小 zoom 0.1：64→128→256（256*0.1=25.6 ≥24）。
      expect(EdgelessGridPainter.stepFor(0.1), 256.0);
    });

    test('网格线随世界平移滚动，且对齐世界坐标 step 整数倍', () {
      final cameraA = EdgelessCamera.initial;
      final cameraB = cameraA.translated(100, 200);
      final xsA = EdgelessGridPainter.verticalLineScreenXs(viewport, cameraA);
      final xsB = EdgelessGridPainter.verticalLineScreenXs(viewport, cameraB);
      expect(xsA, isNot(xsB), reason: '平移后网格线屏幕位置应变化（随世界滚动）');
      // 对齐性：任一屏幕线反投影回世界坐标应是 64 的整数倍。
      final world = cameraB.screenToWorld(Offset(xsB.first, 0), viewport);
      expect((world.dx / 64) % 1, closeTo(0, 1e-9));
    });

    test('世界坐标无边界：平移到 ±100 万仍有网格线覆盖可视区', () {
      final farCamera = EdgelessCamera.initial.translated(1000000, 1000000);
      final xs = EdgelessGridPainter.verticalLineScreenXs(viewport, farCamera);
      final ys =
          EdgelessGridPainter.horizontalLineScreenYs(viewport, farCamera);
      expect(xs, isNotEmpty);
      expect(ys, isNotEmpty);
      // 覆盖性：可视区两端内侧均有线（可视区被网格覆盖，无「到头」空窗）。
      expect(xs.first, lessThanOrEqualTo(0));
      expect(xs.last, greaterThanOrEqualTo(viewport.width));
      expect(ys.first, lessThanOrEqualTo(0));
      expect(ys.last, greaterThanOrEqualTo(viewport.height));
    });

    test('线密度有界：线数不超过 可视宽高/最小间距 + 2', () {
      for (final zoom in const [0.1, 0.5, 1.0, 3.0, 10.0]) {
        final camera = EdgelessCamera(zoom: zoom);
        final xs = EdgelessGridPainter.verticalLineScreenXs(viewport, camera);
        final ys =
            EdgelessGridPainter.horizontalLineScreenYs(viewport, camera);
        expect(xs.length, lessThanOrEqualTo(viewport.width / 24 + 2),
            reason: 'zoom=$zoom 竖线过密');
        expect(ys.length, lessThanOrEqualTo(viewport.height / 24 + 2),
            reason: 'zoom=$zoom 横线过密');
      }
    });

    test('shouldRepaint：颜色或相机变化触发重绘', () {
      const color = Color(0x66000000);
      final camera = EdgelessCamera.initial;
      final painter = EdgelessGridPainter(color: color, camera: camera);
      expect(
        painter.shouldRepaint(
          EdgelessGridPainter(color: color, camera: camera),
        ),
        isFalse,
      );
      expect(
        painter.shouldRepaint(
          EdgelessGridPainter(color: color, camera: camera.translated(1, 1)),
        ),
        isTrue,
      );
    });
  });
}
