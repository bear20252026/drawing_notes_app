import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/color_sampling_service.dart';

/// Q-1 God Class 拆分（2026-08-16——第四步）：ColorSamplingService 取色
/// 纯计算（rawRgba 像素→Color）独立单测（从 DrawingController 解耦）。
void main() {
  test('取色：rawRgba 像素读取（RGBA 字节序）', () {
    // 2x2 图像：像素0=红(255,0,0,255) 像素1=绿(0,255,0,255)
    //          像素2=蓝(0,0,255,255) 像素3=白(255,255,255,255)
    final data = ByteData(16)
      ..setUint8(0, 255)
      ..setUint8(1, 0)
      ..setUint8(2, 0)
      ..setUint8(3, 255)
      ..setUint8(4, 0)
      ..setUint8(5, 255)
      ..setUint8(6, 0)
      ..setUint8(7, 255)
      ..setUint8(8, 0)
      ..setUint8(9, 0)
      ..setUint8(10, 255)
      ..setUint8(11, 255)
      ..setUint8(12, 255)
      ..setUint8(13, 255)
      ..setUint8(14, 255)
      ..setUint8(15, 255);
    expect(
      ColorSamplingService.colorFromRgbaBytes(data, 2, 0, 0),
      const Color(0xFFFF0000),
    );
    expect(
      ColorSamplingService.colorFromRgbaBytes(data, 2, 1, 0),
      const Color(0xFF00FF00),
    );
    expect(
      ColorSamplingService.colorFromRgbaBytes(data, 2, 0, 1),
      const Color(0xFF0000FF),
    );
    expect(
      ColorSamplingService.colorFromRgbaBytes(data, 2, 1, 1),
      const Color(0xFFFFFFFF),
    );
  });

  test('取色：越界返回 null（纯防御）', () {
    final data = ByteData(16);
    expect(ColorSamplingService.colorFromRgbaBytes(data, 2, 2, 0), isNull);
    expect(ColorSamplingService.colorFromRgbaBytes(data, 2, -1, 0), isNull);
    expect(ColorSamplingService.colorFromRgbaBytes(data, 2, 0, 2), isNull);
  });
}
