import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Saber 借鉴——HighlighterCompositing + 压感规范化测试（纯逻辑——不搞崩）。
void main() {
  test('荧光笔渲染参数（Saber——文字下方 + 重叠不变色）', () {
    const service = HighlighterCompositing();
    final render = service.render();
    expect(render.layerBelowText, true); // 渲染文字下方（文字清晰）。
    expect(render.noOverlapShift, true); // 重叠不变色。
    expect(render.alphaStable, true);    // 透明度稳定。
    expect(service.shouldLayerBelowText(render), true);
  });

  test('effectiveAlpha：重叠不变色（透明度稳定——不加深）', () {
    const service = HighlighterCompositing();
    // 重叠 5 次——透明度仍稳定（Saber compositing——无累计）。
    expect(service.effectiveAlpha(0.35, 1), 0.35);
    expect(service.effectiveAlpha(0.35, 5), 0.35);
    expect(service.effectiveAlpha(0.5, 3), 0.5);
  });

  test('blend：重叠区域保持原色（取浅色——不加深）', () {
    const service = HighlighterCompositing();
    final blended = service.blend((r: 0.9, g: 0.5, b: 0.2), (r: 0.4, g: 0.8, b: 0.3));
    // 取浅色分量（不加深——Saber compositing）。
    expect(blended.r, 0.4);
    expect(blended.g, 0.5);
    expect(blended.b, 0.2);
  });

  test('HighlighterRender：相等性', () {
    const a = HighlighterRender(layerBelowText: true, noOverlapShift: true, alphaStable: true);
    const b = HighlighterRender(layerBelowText: true, noOverlapShift: true, alphaStable: true);
    expect(a, b);
  });

  test('压感规范化（Saber v1.35——S Pen 兼容）', () {
    // 低于 0.05 视为误触。
    expect(BrushStyles.normalizePressure(0.02), 0);
    // 高于 0.95 视为满压。
    expect(BrushStyles.normalizePressure(0.98), 1);
    // 正常范围不变。
    expect(BrushStyles.normalizePressure(0.5), 0.5);
    expect(BrushStyles.normalizePressure(0.3), 0.3);
  });

  test('withPressure：压感规范化集成（压力在 0~1——无越界）', () {
    final points = List.generate(5, (i) => StrokePoint(x: i * 10.0, y: 0));
    final pressured = BrushStyles.withPressure(points);
    for (final p in pressured) {
      expect(p.pressure, inInclusiveRange(0.0, 1.0));
    }
  });
}
