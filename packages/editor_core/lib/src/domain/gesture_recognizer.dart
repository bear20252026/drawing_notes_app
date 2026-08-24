// editor_core——GestureRecognizer 高级手势（Excalidraw gesture.ts 借鉴——2026-08-21）。
//
// Excalidraw gesture.ts 本地化——高级手势识别（双指缩放/旋转/长按/双击）。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - gesture.ts——手势状态机（tap/drag/pinch/rotate/longPress/doubleTap）
// - 手势参数（速度/方向/压力/持续时间）
library;

import 'dart:math' as math;

/// 手势类型（Excalidraw gesture.ts 借鉴）。
enum GestureType {
  /// 点击（轻触）。
  tap,

  /// 双击。
  doubleTap,

  /// 长按。
  longPress,

  /// 拖拽（单指）。
  drag,

  /// 缩放（双指捏合）。
  pinch,

  /// 旋转（双指旋转）。
  rotate,
}

/// 手势状态（Excalidraw gesture 状态机借鉴）。
enum GesturePhase {
  /// 开始（手指按下）。
  began,

  /// 更新（手指移动）。
  updated,

  /// 结束（手指抬起）。
  ended,

  /// 取消（手势被中断）。
  cancelled,
}

/// 手势数据（Excalidraw gesture.ts 本地化——不可变）。
///
/// 存储手势识别结果——类型/阶段/参数/时间。
class GestureData {
  const GestureData({
    required this.type,
    required this.phase,
    required this.x,
    required this.y,
    this.x2,
    this.y2,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.velocity = 0.0,
    this.pressure = 1.0,
    this.timestamp,
  });

  final GestureType type;
  final GesturePhase phase;
  final double x;
  final double y;
  final double? x2; // 第二个触摸点（双指）。
  final double? y2;
  final double scale; // 缩放因子（pinch）。
  final double rotation; // 旋转角度（rotate——弧度）。
  final double velocity; // 速度（像素/秒）。
  final double pressure; // 压力（0~1）。
  final DateTime? timestamp;

  /// 是否双指手势。
  bool get isTwoFinger => x2 != null && y2 != null;

  /// 双指中心点。
  ({double x, double y})? get focalPoint {
    if (!isTwoFinger) return null;
    return (x: (x + x2!) / 2, y: (y + y2!) / 2);
  }

  /// 双指间距（缩放计算用）。
  double? get fingerDistance {
    if (!isTwoFinger) return null;
    final dx = x2! - x;
    final dy = y2! - y;
    return math.sqrt(dx * dx + dy * dy);
  }

  GestureData copyWith({
    GestureType? type,
    GesturePhase? phase,
    double? x,
    double? y,
    double? x2,
    double? y2,
    double? scale,
    double? rotation,
    double? velocity,
    double? pressure,
  }) {
    return GestureData(
      type: type ?? this.type,
      phase: phase ?? this.phase,
      x: x ?? this.x,
      y: y ?? this.y,
      x2: x2 ?? this.x2,
      y2: y2 ?? this.y2,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      velocity: velocity ?? this.velocity,
      pressure: pressure ?? this.pressure,
      timestamp: timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GestureData && type == other.type && phase == other.phase && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(type, phase, x, y);
}

/// 手势识别器（Excalidraw gesture.ts 本地化——纯 Dart 静态方法）。
///
/// 从原始触摸事件识别手势类型（tap/drag/pinch/rotate/longPress/doubleTap）。
/// 参数：
/// - 移动距离阈值（区分 tap 和 drag）
/// - 时间阈值（区分 tap 和 longPress）
/// - 缩放阈值（区分 drag 和 pinch）
class GestureRecognizer {
  const GestureRecognizer._();

  /// 移动距离阈值（像素——小于此为 tap，大于为 drag）。
  static const double tapThreshold = 10.0;

  /// 长按时间阈值（毫秒）。
  static const int longPressThreshold = 500;

  /// 缩放阈值（缩放因子变化小于此为 drag，大于为 pinch）。
  static const double pinchThreshold = 0.1;

  /// 旋转阈值（弧度——小于此为 pinch，大于为 rotate）。
  static const double rotateThreshold = 0.1;

  /// 识别手势类型（从起始点到当前点的距离 + 时间——Excalidraw gesture 识别）。
  static GestureType recognizeType({
    required double startX,
    required double startY,
    required double currentX,
    required double currentY,
    required int durationMs,
    double? startX2,
    double? startY2,
    double? currentX2,
    double? currentY2,
    double currentScale = 1.0,
    double currentRotation = 0.0,
  }) {
    final dx = currentX - startX;
    final dy = currentY - startY;
    final distance = math.sqrt(dx * dx + dy * dy);
    final isTwoFinger = startX2 != null && startY2 != null && currentX2 != null && currentY2 != null;

    if (isTwoFinger) {
      // 双指：检查缩放和旋转。
      final scaleDelta = (currentScale - 1.0).abs();
      final rotationDelta = currentRotation.abs();
      if (rotationDelta > rotateThreshold) return GestureType.rotate;
      if (scaleDelta > pinchThreshold) return GestureType.pinch;
      return GestureType.drag; // 双指拖拽。
    }

    // 单指。
    if (distance < tapThreshold) {
      // 几乎没移动。
      if (durationMs > longPressThreshold) return GestureType.longPress;
      return GestureType.tap;
    }

    return GestureType.drag;
  }

  /// 检测双击（两次 tap 间隔 < 300ms——Excalidraw doubleTap 识别）。
  static bool isDoubleTap(DateTime? lastTapTime, DateTime currentTapTime) {
    if (lastTapTime == null) return false;
    return currentTapTime.difference(lastTapTime).inMilliseconds < 300;
  }

  /// 计算速度（像素/秒）。
  static double velocity(double dx, double dy, int durationMs) {
    if (durationMs <= 0) return 0;
    final distance = math.sqrt(dx * dx + dy * dy);
    return distance / (durationMs / 1000);
  }
}
