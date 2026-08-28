import 'dart:ui' show Offset, Rect, Size;

/// 图片裁剪框的四个角手柄。
///
/// 以命名语义取代页面内按局部 [Offset] 比较的隐式分派，使裁剪几何的
/// 输入和输出可独立测试。
enum EditorImageCropHandle { topLeft, topRight, bottomLeft, bottomRight }

/// 编辑器图片裁剪的纯几何计算。
///
/// 本类只处理画布矩形与原图像素矩形的确定性换算，不读取文件、不解码
/// 图像、不修改交互状态，也不通知或保存。
abstract final class EditorImageCropGeometry {
  static const double minCropExtent = 10;

  /// 按四角手柄和画布增量计算新的裁剪矩形。
  ///
  /// [imageBounds] 是图片在画布上的完整边界。输出始终限制在该边界内，
  /// 且沿两个轴均保持现有的最小 10 画布单位尺寸规则。
  static Rect resizeCropRect({
    required Rect cropRect,
    required Rect imageBounds,
    required EditorImageCropHandle handle,
    required Offset canvasDelta,
  }) {
    return switch (handle) {
      EditorImageCropHandle.topLeft => Rect.fromLTRB(
        (cropRect.left + canvasDelta.dx)
            .clamp(imageBounds.left, cropRect.right - minCropExtent)
            .toDouble(),
        (cropRect.top + canvasDelta.dy)
            .clamp(imageBounds.top, cropRect.bottom - minCropExtent)
            .toDouble(),
        cropRect.right,
        cropRect.bottom,
      ),
      EditorImageCropHandle.topRight => Rect.fromLTRB(
        cropRect.left,
        (cropRect.top + canvasDelta.dy)
            .clamp(imageBounds.top, cropRect.bottom - minCropExtent)
            .toDouble(),
        (cropRect.right + canvasDelta.dx)
            .clamp(cropRect.left + minCropExtent, imageBounds.right)
            .toDouble(),
        cropRect.bottom,
      ),
      EditorImageCropHandle.bottomLeft => Rect.fromLTRB(
        (cropRect.left + canvasDelta.dx)
            .clamp(imageBounds.left, cropRect.right - minCropExtent)
            .toDouble(),
        cropRect.top,
        cropRect.right,
        (cropRect.bottom + canvasDelta.dy)
            .clamp(cropRect.top + minCropExtent, imageBounds.bottom)
            .toDouble(),
      ),
      EditorImageCropHandle.bottomRight => Rect.fromLTRB(
        cropRect.left,
        cropRect.top,
        (cropRect.right + canvasDelta.dx)
            .clamp(cropRect.left + minCropExtent, imageBounds.right)
            .toDouble(),
        (cropRect.bottom + canvasDelta.dy)
            .clamp(cropRect.top + minCropExtent, imageBounds.bottom)
            .toDouble(),
      ),
    };
  }

  /// 将画布裁剪矩形映射为原始图片像素矩形。
  ///
  /// 保持编辑器已有的 `sourceExtent / (canvasExtent + 1)` 比例与钳制规则，
  /// 避免本次职责迁移造成单像素范围的行为变化。
  static Rect sourceRectForCrop({
    required Rect cropRect,
    required Rect imageBounds,
    required Size sourceSize,
  }) {
    final scaleX = sourceSize.width / (imageBounds.width + 1);
    final scaleY = sourceSize.height / (imageBounds.height + 1);
    return Rect.fromLTWH(
      (cropRect.left - imageBounds.left)
              .clamp(0, imageBounds.width)
              .toDouble() *
          scaleX,
      (cropRect.top - imageBounds.top).clamp(0, imageBounds.height).toDouble() *
          scaleY,
      cropRect.width.clamp(0, imageBounds.width).toDouble() * scaleX,
      cropRect.height.clamp(0, imageBounds.height).toDouble() * scaleY,
    );
  }
}
