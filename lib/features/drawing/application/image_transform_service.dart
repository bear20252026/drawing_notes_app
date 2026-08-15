import 'dart:ui';

/// 图片变换计算服务（Q-1 God Class 拆分 2026-08-16——第五步）。
///
/// 多方调研（snow_draw 纯 Dart 引擎 geometry 独立 + markdraw 变换计算）
/// 印证：从 DrawingController.scaleSelectedDocumentImage 提取纯计算——
/// 围绕中心缩放 + 尺寸 clamp（无副作用——可独立单测）；controller 保留
/// 变换协调（快照/通知）。
class ImageTransformService {
  const ImageTransformService();

  /// 围绕图片中心缩放（保持比例 + 尺寸 clamp 32..8192 / 24..8192）。
  /// 返回 (x, y, width, height) 变换结果（中心保持不变）。
  static ({double x, double y, double width, double height}) clampedScale({
    required double x,
    required double y,
    required double width,
    required double height,
    required double factor,
  }) {
    final center = Offset(x + width / 2, y + height / 2);
    final nextWidth = (width * factor).clamp(32.0, 8192.0);
    final ratio = height / width;
    final nextHeight = (nextWidth * ratio).clamp(24.0, 8192.0);
    return (
      x: center.dx - nextWidth / 2,
      y: center.dy - nextHeight / 2,
      width: nextWidth,
      height: nextHeight,
    );
  }

  /// 形状围绕中心等比缩放（尺寸分别 clamp 16..8192——形状最小 16）。
  /// 中心由调用方计算（rawBounds——含旋转形状包围盒）——忠实原语义。
  /// 返回 (x, y, width, height) 变换结果。
  static ({double x, double y, double width, double height}) clampedShapeScale({
    required Offset center,
    required double width,
    required double height,
    required double factor,
  }) {
    final nextWidth = (width * factor).clamp(16.0, 8192.0);
    final nextHeight = (height * factor).clamp(16.0, 8192.0);
    return (
      x: center.dx - nextWidth / 2,
      y: center.dy - nextHeight / 2,
      width: nextWidth,
      height: nextHeight,
    );
  }
}
