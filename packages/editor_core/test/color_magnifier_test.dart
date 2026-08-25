import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 用户需求——ColorMagnifier 取色放大镜测试（纯逻辑——不搞崩）。
void main() {
  test('MagnifierConfig：默认值', () {
    const config = MagnifierConfig();
    expect(config.radius, 16);
    expect(config.zoom, 3);
    expect(config.showCrosshair, true);
    expect(config.showHex, true);
  });

  test('magnifierSize：放大镜显示尺寸（radius×2×zoom）', () {
    const service = ColorMagnifier();
    const config = MagnifierConfig(radius: 16, zoom: 3);
    final size = service.magnifierSize(config);
    expect(size.width, 96); // 16×2×3。
    expect(size.height, 96);
    expect(size.isValid, true);
  });

  test('pickColor：RGBA 像素提取（红色）', () {
    const service = ColorMagnifier();
    // 2x2 图像——第一个像素红色（RGBA）。
    final bytes = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255];
    final color = service.pickColor(
      imageBytes: bytes, width: 2, height: 2, px: 0, py: 0,
    );
    expect(color.r, 255);
    expect(color.g, 0);
    expect(color.b, 0);
    expect(color.hex, '#FF0000');
  });

  test('pickColor：BGRA 像素提取（字节顺序）', () {
    const service = ColorMagnifier();
    // 1x1 图像——BGRA：b=255, g=0, r=0 → 蓝色。
    final bytes = [255, 0, 0, 255];
    final color = service.pickColor(
      imageBytes: bytes, width: 1, height: 1, px: 0, py: 0, bgrOrder: true,
    );
    expect(color.r, 0);
    expect(color.b, 255);
  });

  test('pickColor：边界采样（clamp）', () {
    const service = ColorMagnifier();
    final bytes = List.generate(4 * 4, (i) => i * 10 % 256);
    // 越界位置——clamp 到图像内。
    final color = service.pickColor(
      imageBytes: bytes, width: 2, height: 2, px: 99, py: 99,
    );
    expect(color.r, inInclusiveRange(0, 255));
  });

  test('pickColor：越界字节——返回黑色', () {
    const service = ColorMagnifier();
    final color = service.pickColor(
      imageBytes: [1, 2, 3], width: 1, height: 1, px: 0, py: 0,
    );
    expect(color.hex, '#000000');
  });

  test('sampleRegion：采样区域（鼠标位置周围 radius）', () {
    const service = ColorMagnifier();
    const config = MagnifierConfig(radius: 16);
    final region = service.sampleRegion(config, px: 50, py: 40);
    expect(region.left, 34);
    expect(region.top, 24);
    expect(region.right, 66);
    expect(region.bottom, 56);
  });

  test('shouldShow：取色模式开启时显示', () {
    const service = ColorMagnifier();
    expect(service.shouldShow(true, const MagnifierConfig()), true);
    expect(service.shouldShow(false, const MagnifierConfig()), false);
    expect(service.shouldShow(true, const MagnifierConfig(zoom: 0)), false);
  });

  test('PickedColor：hex 格式 + 相等性', () {
    const red = PickedColor(r: 255, g: 0, b: 0);
    expect(red.hex, '#FF0000');
    const other = PickedColor(r: 255, g: 0, b: 0);
    expect(red, other);
    const green = PickedColor(r: 0, g: 255, b: 0);
    expect(red == green, isFalse);
  });

  test('MagnifierConfig：copyWith 不可变', () {
    const config = MagnifierConfig();
    final updated = config.copyWith(radius: 32, zoom: 5);
    expect(config.radius, 16); // 原实例不变。
    expect(updated.radius, 32);
    expect(updated.zoom, 5);
  });
}
