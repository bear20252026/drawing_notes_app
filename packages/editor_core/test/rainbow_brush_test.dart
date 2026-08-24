import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 用户需求——RainbowBrush 彩虹画笔测试（纯逻辑——不搞崩）。
void main() {
  test('colorAt：正弦波 RGB——分量在 0-255 范围', () {
    for (var i = 0; i <= 20; i++) {
      final c = RainbowBrush.colorAt(i / 20);
      expect(c.r, inInclusiveRange(0, 255));
      expect(c.g, inInclusiveRange(0, 255));
      expect(c.b, inInclusiveRange(0, 255));
    }
  });

  test('colorAt：复杂混合（非单一色相——分量相位差 120°）', () {
    // t=0：r=sin(0)*127+128=128，g=sin(2.094)*127+128≈238，b=sin(4.189)*127+128≈18。
    final c0 = RainbowBrush.colorAt(0);
    // t=0.5：r=sin(π)*127+128=128，g=sin(π+2.094)*127+128≈18，b=sin(π+4.189)*127+128≈238。
    final c05 = RainbowBrush.colorAt(0.5);
    // 复杂混合——不同位置颜色显著不同（非单一色相变化）。
    expect(c0, isNot(equals(c05)));
    expect(c0.hex.length, 7); // #RRGGBB。
  });

  test('colorAt：hex 格式正确', () {
    final c = RainbowBrush.colorAt(0.25);
    expect(c.hex, matches(RegExp(r'^#[0-9A-F]{6}$')));
  });

  test('hueCycle：色相循环（t=0 和 t=1 都是红——完整循环）', () {
    final start = RainbowBrush.hueCycle(0);
    final end = RainbowBrush.hueCycle(1);
    expect(start, end); // 0° = 360°。
    expect(start.r, greaterThan(start.b)); // 红色主导。
  });

  test('hueCycle：中间色相变化（0→0.5 显著不同）', () {
    final c0 = RainbowBrush.hueCycle(0);
    final c05 = RainbowBrush.hueCycle(0.5);
    expect(c0, isNot(equals(c05)));
  });

  test('mix：混合两种颜色（比例 0/0.5/1）', () {
    const yellow = RainbowColor(r: 255, g: 255, b: 0);
    const blue = RainbowColor(r: 0, g: 0, b: 255);
    final allYellow = RainbowBrush.mix(yellow, blue, 0);
    final half = RainbowBrush.mix(yellow, blue, 0.5);
    final allBlue = RainbowBrush.mix(yellow, blue, 1);
    expect(allYellow, yellow);
    expect(allBlue, blue);
    // 混合（黄+蓝 → 中间色——含绿色分量——Mixbox 思路）。
    expect(half.g, greaterThan(100)); // 绿分量增强。
    expect(half.g, greaterThan(0));
  });

  test('strokeColors：笔画颜色序列（每点颜色变化——复杂混合流动）', () {
    final colors = RainbowBrush.strokeColors(20);
    expect(colors.length, 20);
    expect(RainbowBrush.isVarying(colors), true); // 颜色不断变化。
  });

  test('strokeColors：单点序列', () {
    final colors = RainbowBrush.strokeColors(1);
    expect(colors.length, 1);
  });

  test('isVarying：相邻点颜色不同（彩虹流动验证）', () {
    final colors = RainbowBrush.strokeColors(10);
    expect(RainbowBrush.isVarying(colors), true);
    // 相同颜色——不变化。
    final same = List.filled(5, const RainbowColor(r: 255, g: 0, b: 0));
    expect(RainbowBrush.isVarying(same), false);
  });

  test('RainbowColor：相等性 + hex', () {
    const a = RainbowColor(r: 255, g: 0, b: 0);
    const b = RainbowColor(r: 255, g: 0, b: 0);
    const c = RainbowColor(r: 0, g: 255, b: 0);
    expect(a, b);
    expect(a == c, isFalse);
    expect(a.hex, '#FF0000');
  });
}
