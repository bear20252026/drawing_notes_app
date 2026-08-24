import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Saber 借鉴——BrushStyles 画笔笔画组测试（纯逻辑——不搞崩）。
void main() {
  test('钢笔（Pen）：压力感应——粗细随压力变化', () {
    const pen = BrushStyle.pen;
    expect(pen.pressureSensitive, true);
    // 压力 0 → 40% 宽；压力 1 → 160% 宽。
    expect(pen.effectiveWidth(0), closeTo(0.8, 0.01)); // 2.0 × 0.4。
    expect(pen.effectiveWidth(0.5), closeTo(2.0, 0.01)); // 2.0 × 1.0。
    expect(pen.effectiveWidth(1.0), closeTo(3.2, 0.01)); // 2.0 × 1.6。
  });

  test('圆珠笔（Ballpoint）：均匀——无压力变化', () {
    const ballpoint = BrushStyle.ballpoint;
    expect(ballpoint.pressureSensitive, false);
    expect(ballpoint.effectiveWidth(0), 1.5);
    expect(ballpoint.effectiveWidth(1.0), 1.5); // 压力不影响。
    expect(ballpoint.effectiveWidth(0.5), 1.5);
  });

  test('荧光笔（Highlighter）：半透明宽笔画（高亮）', () {
    const highlighter = BrushStyle.highlighter;
    expect(highlighter.baseWidth, 8.0); // 宽笔画。
    expect(highlighter.opacity, 0.35); // 半透明。
    expect(BrushStyles.isTranslucent(highlighter), true);
    expect(highlighter.effectiveWidth(0.5), 8.0); // 固定宽。
  });

  test('铅笔（Pencil）：纹理笔画', () {
    const pencil = BrushStyle.pencil;
    expect(pencil.textured, true);
    expect(BrushStyles.isTextured(pencil), true);
    expect(pencil.opacity, 0.8);
  });

  test('BrushStyles.all：4 种画笔（Saber 画笔组）', () {
    expect(BrushStyles.all.length, 4);
    expect(BrushStyles.all.map((b) => b.type).toSet(),
        {BrushType.pen, BrushType.ballpoint, BrushType.highlighter, BrushType.pencil});
  });

  test('BrushStyles.of/nameOf：按类型获取 + 名称', () {
    expect(BrushStyles.of(BrushType.pen).type, BrushType.pen);
    expect(BrushStyles.nameOf(BrushType.pen), '钢笔');
    expect(BrushStyles.nameOf(BrushType.ballpoint), '圆珠笔');
    expect(BrushStyles.nameOf(BrushType.highlighter), '荧光笔');
    expect(BrushStyles.nameOf(BrushType.pencil), '铅笔');
  });

  test('withPressure：钢笔压力序列（起笔收笔轻——压力变化）', () {
    final points = List.generate(5, (i) => StrokePoint(x: i * 10.0, y: 0));
    final pressured = BrushStyles.withPressure(points);
    expect(pressured.length, 5);
    // 中间点压力最高（正弦波——起收轻）。
    expect(pressured[0].pressure, lessThan(pressured[2].pressure));
    expect(pressured[4].pressure, lessThan(pressured[2].pressure));
    expect(pressured[2].pressure, closeTo(1.0, 0.05)); // 峰值。
  });

  test('StrokePoint：copyWith + 相等性', () {
    const p = StrokePoint(x: 10, y: 20, pressure: 0.5);
    final updated = p.copyWith(pressure: 1.0);
    expect(p.pressure, 0.5); // 原实例不变。
    expect(updated.pressure, 1.0);
    const other = StrokePoint(x: 10, y: 20, pressure: 0.5);
    expect(p, other);
  });

  test('BrushStyle：copyWith + 相等性（按 type）', () {
    const pen = BrushStyle.pen;
    final thick = pen.copyWith(baseWidth: 4.0, opacity: 0.9);
    expect(pen.baseWidth, 2.0); // 原实例不变。
    expect(thick.baseWidth, 4.0);
    expect(thick.opacity, 0.9);
    const other = BrushStyle(type: BrushType.pen);
    expect(pen, other); // 按 type 相等。
  });

  test('BrushType 枚举', () {
    expect(BrushType.values.length, 4);
  });
}
