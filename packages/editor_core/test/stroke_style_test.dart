import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE/Excalidraw 借鉴——StrokeStyle 画笔样式测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('StrokeStyle：默认值', () {
    const style = StrokeStyle();
    expect(style.strokeColor, '#000000');
    expect(style.backgroundColor, 'transparent');
    expect(style.strokeWidth, 2.0);
    expect(style.opacity, 1.0);
    expect(style.strokeStyle, StrokeLineType.solid);
  });

  test('StrokeStyle：copyWith 不可变', () {
    const original = StrokeStyle();
    final red = original.copyWith(strokeColor: '#FF0000', strokeWidth: 4.0);
    expect(original.strokeColor, '#000000'); // 原实例不变。
    expect(original.strokeWidth, 2.0);
    expect(red.strokeColor, '#FF0000');
    expect(red.strokeWidth, 4.0);
  });

  test('StrokeStyle：withStrokeWidth（范围限制 1~32）', () {
    const style = StrokeStyle();
    expect(style.withStrokeWidth(0).strokeWidth, 1.0);  // 最小值。
    expect(style.withStrokeWidth(50).strokeWidth, 32.0); // 最大值。
    expect(style.withStrokeWidth(10).strokeWidth, 10.0); // 正常值。
  });

  test('StrokeStyle：withOpacity（0~1）', () {
    const style = StrokeStyle();
    expect(style.withOpacity(-0.5).opacity, 0.0);
    expect(style.withOpacity(1.5).opacity, 1.0);
    expect(style.withOpacity(0.7).opacity, 0.7);
  });

  test('StrokeStyle：预设样式（thin/medium/thick）', () {
    expect(StrokeStyle.thin.strokeWidth, 1.0);
    expect(StrokeStyle.medium.strokeWidth, 2.0);
    expect(StrokeStyle.thick.strokeWidth, 4.0);
    expect(StrokeStyle.extraThick.strokeWidth, 8.0);
  });

  test('StrokeStyle：预设颜色', () {
    expect(StrokeStyle.black.strokeColor, '#000000');
    expect(StrokeStyle.red.strokeColor, '#FF0000');
    expect(StrokeStyle.blue.strokeColor, '#0000FF');
    expect(StrokeStyle.green.strokeColor, '#00AA00');
    expect(StrokeStyle.transparent.opacity, 0.0);
  });

  test('StrokeStyle：线条类型（solid/dashed/dotted）', () {
    expect(StrokeLineType.values.length, 3);
    expect(StrokeLineType.solid.index, 0);
    expect(StrokeLineType.dashed.index, 1);
    expect(StrokeLineType.dotted.index, 2);
  });

  test('StrokeStyle：相等性', () {
    const a = StrokeStyle(strokeColor: '#FF0000', strokeWidth: 3.0);
    const b = StrokeStyle(strokeColor: '#FF0000', strokeWidth: 3.0);
    expect(a, b);
  });

  test('StrokeStyle：范围常量（Excalidraw 参考）', () {
    expect(StrokeStyle.minWidth, 1.0);
    expect(StrokeStyle.maxWidth, 32.0);
  });
}
