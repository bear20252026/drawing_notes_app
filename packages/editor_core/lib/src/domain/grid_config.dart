// editor_core——GridConfig 网格吸附（Excalidraw 借鉴——2026-08-21）。
//
// Excalidraw Grid/Snap 本地化——网格对齐/元素吸附。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - scene/ 目录——grid snapping 实现
// - 可配置网格间距（gridSize）
// - snapToGrid（坐标吸附到最近网格点）
// - snapToElement（元素之间对齐吸附——边缘/中心/间距）
library;

/// 网格配置（Excalidraw Grid/Snap 本地化——不可变）。
///
/// 控制网格显示和吸附行为。
class GridConfig {
  const GridConfig({
    this.size = 20,
    this.snapEnabled = true,
    this.showGrid = true,
  });

  /// 网格间距（像素——默认 20——Excalidraw 默认值）。
  final int size;

  /// 是否启用吸附。
  final bool snapEnabled;

  /// 是否显示网格线。
  final bool showGrid;

  GridConfig copyWith({int? size, bool? snapEnabled, bool? showGrid}) {
    return GridConfig(
      size: size ?? this.size,
      snapEnabled: snapEnabled ?? this.snapEnabled,
      showGrid: showGrid ?? this.showGrid,
    );
  }

  /// 关闭网格。
  static const disabled = GridConfig(snapEnabled: false, showGrid: false);

  /// 精细网格（10px）。
  static const fine = GridConfig(size: 10);

  /// 粗网格（40px）。
  static const coarse = GridConfig(size: 40);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridConfig && size == other.size && snapEnabled == other.snapEnabled;

  @override
  int get hashCode => Object.hash(size, snapEnabled);
}

/// 对齐锚点类型（Excalidraw element snap 借鉴）。
enum SnapAnchor {
  /// 左边缘。
  left,

  /// 右边缘。
  right,

  /// 上边缘。
  top,

  /// 下边缘。
  bottom,

  /// 水平中心。
  centerX,

  /// 垂直中心。
  centerY,
}

/// 对齐结果（吸附计算输出——不可变）。
class SnapResult {
  const SnapResult({
    required this.snappedX,
    required this.snappedY,
    this.snappedAnchorsX = const [],
    this.snappedAnchorsY = const [],
  });

  final double snappedX;
  final double snappedY;
  final List<SnapAnchor> snappedAnchorsX;
  final List<SnapAnchor> snappedAnchorsY;

  /// 是否有吸附发生。
  bool get isSnapped => snappedAnchorsX.isNotEmpty || snappedAnchorsY.isNotEmpty;
}

/// 网格/吸附工具类（Excalidraw Grid/Snap 本地化——纯 Dart 静态方法）。
///
/// 功能：
/// - snapToGrid（坐标吸附到最近网格点）
/// - snapToElement（元素之间对齐吸附——边缘/中心/间距）
/// - 网格点列表生成（绘制网格用）
class GridSnap {
  const GridSnap._();

  /// 坐标吸附到最近网格点（Excalidraw snapToGrid 核心算法）。
  static double snapToGrid(double value, int gridSize) {
    return (value / gridSize).round() * gridSize.toDouble();
  }

  /// 点吸附到网格（二维）。
  static ({double x, double y}) snapPointToGrid(
      double x, double y, GridConfig config) {
    if (!config.snapEnabled) return (x: x, y: y);
    return (
      x: snapToGrid(x, config.size),
      y: snapToGrid(y, config.size),
    );
  }

  /// 元素对齐吸附（Excalidraw element snap 借鉴）。
  ///
  /// 检查移动元素与目标元素的对齐关系（边缘/中心/间距）。
  /// threshold：吸附阈值（像素——在此范围内触发吸附）。
  static SnapResult snapToElement({
    required double moveX,
    required double moveY,
    required double moveW,
    required double moveH,
    required double targetX,
    required double targetY,
    required double targetW,
    required double targetH,
    double threshold = 5.0,
  }) {
    var snappedX = moveX;
    var snappedY = moveY;
    final anchorsX = <SnapAnchor>[];
    final anchorsY = <SnapAnchor>[];

    // 水平对齐检查（左-左/左-右/右-左/右-右/中-中）。
    final moveLeft = moveX;
    final moveRight = moveX + moveW;
    final moveCenterX = moveX + moveW / 2;
    final targetLeft = targetX;
    final targetRight = targetX + targetW;
    final targetCenterX = targetX + targetW / 2;

    if ((moveLeft - targetLeft).abs() <= threshold) {
      snappedX = targetLeft;
      anchorsX.add(SnapAnchor.left);
    } else if ((moveLeft - targetRight).abs() <= threshold) {
      snappedX = targetRight;
      anchorsX.add(SnapAnchor.left);
    } else if ((moveRight - targetLeft).abs() <= threshold) {
      snappedX = targetLeft - moveW;
      anchorsX.add(SnapAnchor.right);
    } else if ((moveRight - targetRight).abs() <= threshold) {
      snappedX = targetRight - moveW;
      anchorsX.add(SnapAnchor.right);
    } else if ((moveCenterX - targetCenterX).abs() <= threshold) {
      snappedX = targetCenterX - moveW / 2;
      anchorsX.add(SnapAnchor.centerX);
    }

    // 垂直对齐检查（上-上/上-下/下-上/下-下/中-中）。
    final moveTop = moveY;
    final moveBottom = moveY + moveH;
    final moveCenterY = moveY + moveH / 2;
    final targetTop = targetY;
    final targetBottom = targetY + targetH;
    final targetCenterY = targetY + targetH / 2;

    if ((moveTop - targetTop).abs() <= threshold) {
      snappedY = targetTop;
      anchorsY.add(SnapAnchor.top);
    } else if ((moveTop - targetBottom).abs() <= threshold) {
      snappedY = targetBottom;
      anchorsY.add(SnapAnchor.top);
    } else if ((moveBottom - targetTop).abs() <= threshold) {
      snappedY = targetTop - moveH;
      anchorsY.add(SnapAnchor.bottom);
    } else if ((moveBottom - targetBottom).abs() <= threshold) {
      snappedY = targetBottom - moveH;
      anchorsY.add(SnapAnchor.bottom);
    } else if ((moveCenterY - targetCenterY).abs() <= threshold) {
      snappedY = targetCenterY - moveH / 2;
      anchorsY.add(SnapAnchor.centerY);
    }

    return SnapResult(
      snappedX: snappedX,
      snappedY: snappedY,
      snappedAnchorsX: anchorsX,
      snappedAnchorsY: anchorsY,
    );
  }

  /// 生成网格点列表（绘制网格用）。
  static List<({double x, double y})> gridPoints(
      double viewLeft, double viewTop, double viewRight, double viewBottom,
      GridConfig config) {
    if (!config.showGrid) return [];
    final points = <({double x, double y})>[];
    final startX = snapToGrid(viewLeft, config.size);
    final startY = snapToGrid(viewTop, config.size);
    for (var x = startX; x <= viewRight; x += config.size) {
      for (var y = startY; y <= viewBottom; y += config.size) {
        points.add((x: x, y: y));
      }
    }
    return points;
  }
}
