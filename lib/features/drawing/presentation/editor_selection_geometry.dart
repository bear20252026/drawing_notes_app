import 'dart:ui' show Offset, Rect, Size;

// ---------------------------------------------------------------------------
// 编辑器选区几何（presentation 层纯计算）。
//
// 本文件聚合"缩放/旋转选区"与"图片裁剪"两套纯几何计算：二者都以画布坐标
// 快照为输入、以确定性换算为输出，不读取文件、不解码图像、不修改交互状态、
// 不通知或保存，故可独立单测。聚合避免重复的几何小文件，并减少目录文件数
// 逼近结构门禁上限。
// ---------------------------------------------------------------------------

/// 形状边界的不可变画布坐标快照。
///
/// 该值对象只描述编辑器缩放操作的输入和输出；不持有领域对象、控制器、
/// Widget、存储或任何通知回调。
class EditorShapeBounds {
  const EditorShapeBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

/// 八向缩放手柄的语义标识。
///
/// 手柄不再以局部像素坐标和布尔角标记隐式表达含义，使调用方可以明确
/// 传递左/右/上/下的锚点语义。
enum EditorShapeResizeHandle {
  topLeft,
  top,
  topRight,
  left,
  right,
  bottomLeft,
  bottom,
  bottomRight,
}

/// 编辑器形状缩放的纯几何计算。
///
/// 输入增量必须已由宿主从屏幕坐标换算为画布坐标；本类不感知视口缩放、
/// 旋转或手势生命周期，只保留既有的锚点和尺寸钳制规则。
abstract final class EditorShapeResizeGeometry {
  static const double minExtent = 20;
  static const double maxExtent = 1000;

  static EditorShapeBounds resize({
    required EditorShapeBounds bounds,
    required EditorShapeResizeHandle handle,
    required Offset canvasDelta,
  }) {
    final movesLeft = switch (handle) {
      EditorShapeResizeHandle.topLeft ||
      EditorShapeResizeHandle.left ||
      EditorShapeResizeHandle.bottomLeft => true,
      _ => false,
    };
    final movesRight = switch (handle) {
      EditorShapeResizeHandle.topRight ||
      EditorShapeResizeHandle.right ||
      EditorShapeResizeHandle.bottomRight => true,
      _ => false,
    };
    final movesTop = switch (handle) {
      EditorShapeResizeHandle.topLeft ||
      EditorShapeResizeHandle.top ||
      EditorShapeResizeHandle.topRight => true,
      _ => false,
    };
    final movesBottom = switch (handle) {
      EditorShapeResizeHandle.bottomLeft ||
      EditorShapeResizeHandle.bottom ||
      EditorShapeResizeHandle.bottomRight => true,
      _ => false,
    };

    var x = bounds.x;
    var y = bounds.y;
    var width = bounds.width;
    var height = bounds.height;

    if (movesLeft) {
      x += canvasDelta.dx;
      width = (width - canvasDelta.dx).clamp(minExtent, maxExtent);
    } else if (movesRight) {
      width = (width + canvasDelta.dx).clamp(minExtent, maxExtent);
    }

    if (movesTop) {
      y += canvasDelta.dy;
      height = (height - canvasDelta.dy).clamp(minExtent, maxExtent);
    } else if (movesBottom) {
      height = (height + canvasDelta.dy).clamp(minExtent, maxExtent);
    }

    return EditorShapeBounds(x: x, y: y, width: width, height: height);
  }
}

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
