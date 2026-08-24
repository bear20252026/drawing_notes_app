import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——Measurement 测量工具测试（纯逻辑——不搞崩）。
void main() {
  test('distance：两点间距离', () {
    expect(Measurement.distance(0, 0, 3, 4), closeTo(5, 1e-9));
    expect(Measurement.distance(0, 0, 0, 0), 0);
    expect(Measurement.distance(1, 1, 4, 5), closeTo(5, 1e-9));
  });

  test('measureDistance：距离测量 + 标注', () {
    final result = Measurement.measureDistance(0, 0, 100, 0);
    expect(result.type, MeasurementType.distance);
    expect(result.value, closeTo(100, 1e-9));
    expect(result.unit, 'px');
    expect(result.displayText, '100.0 px');
    expect(result.label, isNotNull);
    expect(result.label!.x, 50); // 中点。
    expect(result.label!.y, -15);
    expect(result.points.length, 2);
  });

  test('angleBetween：两向量夹角', () {
    // 90 度角（垂直）。
    expect(Measurement.angleBetween(0, 0, 10, 0, 10, 10), closeTo(90, 0.01));
    // 平行向量（同方向）→ 0°（非 180°）。
    expect(Measurement.angleBetween(0, 0, 10, 0, 20, 0), closeTo(0, 0.01));
    // 0 度（退化——AB 长度 0）。
    expect(Measurement.angleBetween(0, 0, 0, 0, 10, 0), 0);
  });

  test('measureAngle：角度测量 + 标注', () {
    final result = Measurement.measureAngle(0, 0, 10, 0, 10, 10);
    expect(result.type, MeasurementType.angle);
    expect(result.value, closeTo(90, 0.01));
    expect(result.displayText, '90.0°');
    expect(result.label, isNotNull);
    expect(result.points.length, 3);
  });

  test('polygonArea：多边形面积（Shoelace 公式）', () {
    // 正方形 10x10 → 面积 100。
    final square = [(x: 0.0, y: 0.0), (x: 10.0, y: 0.0), (x: 10.0, y: 10.0), (x: 0.0, y: 10.0)];
    expect(Measurement.polygonArea(square), closeTo(100, 0.01));
    // 三角形 底10 高10 → 面积 50。
    final triangle = [(x: 0.0, y: 0.0), (x: 10.0, y: 0.0), (x: 5.0, y: 10.0)];
    expect(Measurement.polygonArea(triangle), closeTo(50, 0.01));
    // 空/不足 3 点 → 0。
    expect(Measurement.polygonArea([(x: 0.0, y: 0.0)]), 0);
  });

  test('polygonCentroid：多边形质心', () {
    final square = [(x: 0.0, y: 0.0), (x: 10.0, y: 0.0), (x: 10.0, y: 10.0), (x: 0.0, y: 10.0)];
    final centroid = Measurement.polygonCentroid(square);
    expect(centroid.x, closeTo(5, 0.01));
    expect(centroid.y, closeTo(5, 0.01));
  });

  test('measureArea：面积测量 + 标注', () {
    final square = [(x: 0.0, y: 0.0), (x: 10.0, y: 0.0), (x: 10.0, y: 10.0), (x: 0.0, y: 10.0)];
    final result = Measurement.measureArea(square);
    expect(result.type, MeasurementType.area);
    expect(result.value, closeTo(100, 0.01));
    expect(result.displayText, contains('100.0'));
    expect(result.label, isNotNull);
  });
}
