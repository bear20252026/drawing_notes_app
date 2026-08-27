import 'dart:ui' show Offset;

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
