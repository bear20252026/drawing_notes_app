import 'dart:typed_data';
import 'dart:ui';

/// 取色几何服务（Q-1 God Class 拆分 2026-08-16——第四步）。
///
/// Flutter 官方"逐功能重构"渐进节奏延续——从 DrawingController.pickColorAt
/// 提取像素坐标→RGBA 字节→Color 的纯计算（无副作用、无 canvas 依赖——
/// 可独立单测）；canvas 重绘协调保留在 controller。
class ColorSamplingService {
  const ColorSamplingService();

  /// 从 rawRgba 字节读取 [x],[y] 像素颜色（RGBA 字节序——每像素 4 字节）。
  /// 坐标越界返回 null（纯防御——调用方已 clamp，此处双保险）。
  static Color? colorFromRgbaBytes(
    ByteData data,
    int width,
    int x,
    int y,
  ) {
    if (x < 0 || y < 0 || width <= 0 || x >= width) return null;
    final height = data.lengthInBytes ~/ (width * 4);
    if (y >= height) return null;
    final offset = (y * width + x) * 4;
    return Color.fromARGB(
      data.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  }
}
