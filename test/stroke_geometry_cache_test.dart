import 'package:drawing_notes_app/engine/stroke_geometry_cache.dart';
import 'package:drawing_notes_app/models/stroke.dart';
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
}
