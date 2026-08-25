import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——AnimatedTrail 绘制动画测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('TrailPoint：默认值', () {
    const point = TrailPoint(x: 10, y: 20);
    expect(point.x, 10);
    expect(point.y, 20);
    expect(point.t, 0.0);
    expect(point.pressure, 1.0);
  });

  test('TrailPoint：copyWith 不可变', () {
    const original = TrailPoint(x: 0, y: 0);
    final moved = original.copyWith(x: 100, pressure: 0.5);
    expect(original.x, 0); // 原实例不变。
    expect(moved.x, 100);
    expect(moved.pressure, 0.5);
  });

  test('AnimatedTrail：初始状态', () {
    const trail = AnimatedTrail(points: []);
    expect(trail.isEmpty, true);
    expect(trail.pointCount, 0);
    expect(trail.progress, 1.0);
    expect(trail.isComplete, true);
  });

  test('AnimatedTrail：addPoint 添加轨迹点', () {
    const trail = AnimatedTrail(points: []);
    final added = trail.addPoint(const TrailPoint(x: 0, y: 0));
    expect(added.pointCount, 1);
    expect(added.isEmpty, false);
  });

  test('AnimatedTrail：visibleCount/visiblePoints（进度截取）', () {
    final points = List.generate(10, (i) => TrailPoint(x: i * 10.0, y: 0, t: i / 9));
    final trail = AnimatedTrail(points: points, progress: 0.5);
    expect(trail.visibleCount, 5);
    expect(trail.visiblePoints.length, 5);
    expect(trail.visiblePoints.last.x, 40);
  });

  test('AnimatedTrail：advance（推进动画进度）', () {
    const trail = AnimatedTrail(points: [TrailPoint(x: 0, y: 0)], progress: 0.0);
    final advanced = trail.advance(0.3);
    expect(advanced.progress, closeTo(0.3, 0.001));
    final advanced2 = advanced.advance(0.5);
    expect(advanced2.progress, closeTo(0.8, 0.001));
    // 超过 1.0——clamp 到 1.0。
    final completed = advanced2.advance(0.5);
    expect(completed.progress, 1.0);
  });

  test('AnimatedTrail：reset/complete', () {
    const trail = AnimatedTrail(points: [TrailPoint(x: 0, y: 0)], progress: 0.5);
    expect(trail.reset().progress, 0.0);
    expect(trail.complete().progress, 1.0);
    expect(trail.complete().isComplete, true);
  });

  test('AnimatedTrail：interpolatedPosition（线性插值）', () {
    final points = [
      const TrailPoint(x: 0, y: 0, t: 0),
      const TrailPoint(x: 100, y: 100, t: 1),
    ];
    final trail = AnimatedTrail(points: points, progress: 0.5, easing: EasingType.linear);
    final pos = trail.interpolatedPosition!;
    expect(pos.x, closeTo(50, 0.01));
    expect(pos.y, closeTo(50, 0.01));
  });

  test('AnimatedTrail：interpolatedPressure（压力插值）', () {
    final points = [
      const TrailPoint(x: 0, y: 0, pressure: 1.0),
      const TrailPoint(x: 100, y: 100, pressure: 0.2),
    ];
    final trail = AnimatedTrail(points: points, progress: 0.5, easing: EasingType.linear);
    expect(trail.interpolatedPressure, closeTo(0.6, 0.01));
  });

  test('AnimatedTrail：easing 函数（easeIn/easeOut/easeInOut）', () {
    // easeIn（t^2）——比线性慢启动。
    final easeInPoints = [
      const TrailPoint(x: 0, y: 0),
      const TrailPoint(x: 100, y: 0),
    ];
    final easeIn = AnimatedTrail(points: easeInPoints, progress: 0.5, easing: EasingType.easeIn);
    final easeInPos = easeIn.interpolatedPosition!;
    expect(easeInPos.x, lessThan(50)); // easeIn 中点 < 线性中点。

    // easeOut（1 - (1-t)^2）——比线性快启动。
    final easeOut = AnimatedTrail(points: easeInPoints, progress: 0.5, easing: EasingType.easeOut);
    final easeOutPos = easeOut.interpolatedPosition!;
    expect(easeOutPos.x, greaterThan(50)); // easeOut 中点 > 线性中点。
  });

  test('AnimatedTrail：copyWith 不可变', () {
    const original = AnimatedTrail(points: [], progress: 0.0);
    final updated = original.copyWith(progress: 0.5, speed: 2.0);
    expect(original.progress, 0.0); // 原实例不变。
    expect(updated.progress, 0.5);
    expect(updated.speed, 2.0);
  });

  test('AnimatedTrail：EasingType 枚举', () {
    expect(EasingType.values.length, 4);
    expect(EasingType.linear.index, 0);
    expect(EasingType.easeIn.index, 1);
    expect(EasingType.easeOut.index, 2);
    expect(EasingType.easeInOut.index, 3);
  });
}
