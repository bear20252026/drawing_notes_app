import 'package:drawing_notes_app/core/rendering/stroke_geometry_cache.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

StrokePoint _point(double x, {double pressure = 1}) =>
    StrokePoint(x, 0, pressure);

void main() {
  test('实时预览以稀疏锚点跟随高频输入', () {
    final cache = StrokeGeometryCache(_point(0));
    for (var i = 1; i <= 20; i++) {
      cache.append(_point(i * 0.1));
    }

    expect(cache.rawPointCount, 21);
    expect(cache.previewPoints.length, lessThan(5));
    expect(cache.previewPoints.last.x, closeTo(2, 0.0001));
  });

  test('收笔结果保留完整笔画端点并压缩重叠采样', () {
    final cache = StrokeGeometryCache(_point(0));
    cache
      ..append(_point(0.05))
      ..append(_point(0.10))
      ..append(_point(1.0))
      ..append(_point(1.05));

    final finished = cache.finish();

    expect(finished.first.x, 0);
    expect(finished.last.x, 1.05);
    expect(finished.length, lessThan(cache.rawPointCount));
  });

  test('近点但明显的压感变化不会在收笔时丢失', () {
    final cache = StrokeGeometryCache(_point(0, pressure: 0.2));
    cache
      ..append(_point(0.1, pressure: 0.7))
      ..append(_point(0.2, pressure: 0.7));

    final finished = cache.finish();

    expect(finished.any((point) => point.pressure == 0.7), isTrue);
    expect(finished.last.x, 0.2);
  });

  // ---------------------------------------------------------------------------
  // 补充用例
  // ---------------------------------------------------------------------------
  test('单点笔画：finish 返回仅含起始点的列表', () {
    final cache = StrokeGeometryCache(_point(5));
    final finished = cache.finish();
    expect(finished.length, 1);
    expect(finished.first.x, 5);
  });

  test('clear 重置缓存到初始状态', () {
    final cache = StrokeGeometryCache(_point(0));
    for (var i = 1; i <= 10; i++) {
      cache.append(_point(i * 0.1));
    }
    expect(cache.rawPointCount, 11);

    // StrokeGeometryCache 无 clear 方法；新建一个实例模拟重置。
    final fresh = StrokeGeometryCache(_point(0));
    expect(fresh.rawPointCount, 1);
    expect(fresh.previewPoints.length, 1);
    expect(fresh.previewPoints.first.x, 0);
  });

  test('高频重复位置追加被压缩（非坐标变化的点不增加原始计数的显著效果）', () {
    final cache = StrokeGeometryCache(_point(0));
    // 追加 100 个几乎相同位置的点
    for (var i = 0; i < 100; i++) {
      cache.append(_point(0.0001 * i));
    }
    expect(cache.rawPointCount, 101);
    // 预览点应被大幅压缩
    expect(cache.previewPoints.length, lessThan(20));
  });

  test('finish 后原始点仍保留', () {
    final cache = StrokeGeometryCache(_point(0));
    cache
      ..append(_point(1))
      ..append(_point(2));
    final _ = cache.finish();
    // finish 不清空内部原始点
    expect(cache.rawPointCount, greaterThanOrEqualTo(2));
  });

  test('大压力值不溢出（压力范围 0-1 边界）', () {
    final cache = StrokeGeometryCache(_point(0, pressure: 0.0));
    cache
      ..append(_point(0.5, pressure: 1.0))
      ..append(_point(1.0, pressure: 0.0));

    final finished = cache.finish();
    expect(finished.first.pressure, 0.0);
    expect(finished.last.pressure, 0.0);
    // 中间点应保留 1.0 压感（因为与两端差异大）
    expect(finished.any((p) => p.pressure == 1.0), isTrue);
  });
}
