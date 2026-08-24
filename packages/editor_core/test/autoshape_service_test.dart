import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw+ 借鉴——AutoshapeService 手绘整形测试（纯逻辑——不搞崩）。
void main() {
  test('直线整形：近似共线的点 → line（高置信度）', () {
    const service = AutoshapeService();
    // 几乎水平的点（微小抖动）。
    final points = [
      const AutoPoint(0, 0), const AutoPoint(20, 1), const AutoPoint(40, 0),
      const AutoPoint(60, 1), const AutoPoint(80, 0), const AutoPoint(100, 1),
    ];
    final result = service.shape(points);
    expect(result.shape, 'line');
    expect(result.confidence, greaterThanOrEqualTo(0.8));
    expect(result.shouldShape, true);
    expect(result.startX, 0);
    expect(result.startY, 0);
    expect(result.endX, 100);
  });

  test('矩形整形：闭合四角 → rect', () {
    const service = AutoshapeService();
    // 矩形四角（闭合）。
    final points = [
      const AutoPoint(0, 0), const AutoPoint(50, 0), const AutoPoint(100, 0),
      const AutoPoint(100, 50), const AutoPoint(100, 100),
      const AutoPoint(50, 100), const AutoPoint(0, 100), const AutoPoint(0, 50),
      const AutoPoint(0, 0),
    ];
    final result = service.shape(points);
    expect(result.shape, 'rect');
    expect(result.shouldShape, true);
    expect(result.rectX1, 0);
    expect(result.rectY1, 0);
    expect(result.rectX2, 100);
    expect(result.rectY2, 100);
  });

  test('圆形整形：闭合近圆 → ellipse', () {
    const service = AutoshapeService();
    // 近似圆形（8 点）。
    final points = [
      const AutoPoint(50, 0), const AutoPoint(85, 15), const AutoPoint(100, 50),
      const AutoPoint(85, 85), const AutoPoint(50, 100), const AutoPoint(15, 85),
      const AutoPoint(0, 50), const AutoPoint(15, 15), const AutoPoint(50, 0),
    ];
    final result = service.shape(points);
    expect(result.shape, 'ellipse');
    expect(result.shouldShape, true);
  });

  test('非闭合/锯齿：不整形', () {
    const service = AutoshapeService();
    // 锯齿状（非闭合——不整形）。
    final points = [
      const AutoPoint(0, 0), const AutoPoint(20, 50), const AutoPoint(40, 0),
      const AutoPoint(60, 50), const AutoPoint(80, 0),
    ];
    final result = service.shape(points);
    expect(result.shape, isNull);
    expect(result.shouldShape, false);
  });

  test('太少点（<3）：不整形', () {
    const service = AutoshapeService();
    final result = service.shape(const [AutoPoint(0, 0), AutoPoint(10, 10)]);
    expect(result.shape, isNull);
    expect(result.shouldShape, false);
  });

  test('AutoshapeResult：相等性 + shouldShape', () {
    const a = AutoshapeResult(shape: 'line', confidence: 0.9);
    const b = AutoshapeResult(shape: 'line', confidence: 0.9);
    const c = AutoshapeResult(shape: 'rect', confidence: 0.9);
    expect(a, b);
    expect(a == c, isFalse);
    expect(a.shouldShape, true); // ≥0.8。
    const low = AutoshapeResult(shape: 'line', confidence: 0.5);
    expect(low.shouldShape, false);
  });

  test('AutoPoint：相等性', () {
    const a = AutoPoint(1, 2);
    const b = AutoPoint(1, 2);
    const c = AutoPoint(2, 1);
    expect(a, b);
    expect(a == c, isFalse);
  });
}
