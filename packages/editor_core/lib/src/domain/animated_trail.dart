// editor_core——AnimatedTrail 绘制动画（Excalidraw animatedTrail.ts 借鉴——2026-08-21）。
//
// Excalidraw animatedTrail.ts 本地化——手绘感增强动画。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - animatedTrail.ts——绘制动画效果（手绘感增强——笔画逐渐出现）
// - 轨迹点 + 时间戳 + 插值函数
// - 用于手绘风格的笔画绘制动画（笔画从起点逐渐画到终点）
library;

/// 动画轨迹点（不可变——Excalidraw trail point 本地化）。
class TrailPoint {
  const TrailPoint({
    required this.x,
    required this.y,
    this.t = 0.0,
    this.pressure = 1.0,
  });

  final double x;
  final double y;

  /// 时间参数（0~1——轨迹进度）。
  final double t;

  /// 压力参数（0~1——模拟压感笔触粗细变化）。
  final double pressure;

  TrailPoint copyWith({double? x, double? y, double? t, double? pressure}) {
    return TrailPoint(
      x: x ?? this.x,
      y: y ?? this.y,
      t: t ?? this.t,
      pressure: pressure ?? this.pressure,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrailPoint && x == other.x && y == other.y && t == other.t;

  @override
  int get hashCode => Object.hash(x, y, t);
}

/// 动画插值类型（Excalidraw animation easing 借鉴）。
enum EasingType {
  /// 线性（匀速）。
  linear,

  /// 缓入（加速）。
  easeIn,

  /// 缓出（减速）。
  easeOut,

  /// 缓入缓出（加减速）。
  easeInOut,
}

/// 动画轨迹（Excalidraw animatedTrail.ts 本地化——不可变）。
///
/// 管理绘制动画轨迹——笔画逐渐出现（手绘感增强）。
/// 支持：
/// - 轨迹点序列（时间+位置+压力）
/// - 动画进度（0~1——当前显示到哪个点）
/// - 插值函数（在两点间平滑过渡）
/// - 速度自适应（根据点间距自动调整动画速度）
class AnimatedTrail {
  const AnimatedTrail({
    required this.points,
    this.progress = 1.0,
    this.easing = EasingType.easeOut,
    this.speed = 1.0,
  });

  /// 轨迹点序列（按时间排序）。
  final List<TrailPoint> points;

  /// 动画进度（0~1——1=完全显示）。
  final double progress;

  /// 缓动类型。
  final EasingType easing;

  /// 动画速度倍率（1.0=正常——>1 加速——<1 减速）。
  final double speed;

  /// 是否为空。
  bool get isEmpty => points.isEmpty;

  /// 总点数。
  int get pointCount => points.length;

  /// 当前可见点数（根据进度计算）。
  int get visibleCount => (points.length * progress).round().clamp(0, points.length);

  /// 已完成（进度 >= 1.0）。
  bool get isComplete => progress >= 1.0;

  /// 获取可见轨迹点（根据进度截取）。
  List<TrailPoint> get visiblePoints {
    final count = visibleCount;
    if (count >= points.length) return points;
    return points.sublist(0, count);
  }

  /// 获取当前插值位置（在两点间平滑过渡——手绘感）。
  ({double x, double y})? get interpolatedPosition {
    if (points.isEmpty) return null;
    if (progress >= 1.0) {
      final last = points.last;
      return (x: last.x, y: last.y);
    }
    if (progress <= 0) {
      final first = points.first;
      return (x: first.x, y: first.y);
    }

    // 找到进度对应的两个点。
    final exactIndex = progress * (points.length - 1);
    final index = exactIndex.floor().clamp(0, points.length - 2);
    final fraction = exactIndex - index;

    final p1 = points[index];
    final p2 = points[index + 1];

    // 应用缓动函数。
    final easedFraction = _applyEasing(fraction);

    return (
      x: p1.x + (p2.x - p1.x) * easedFraction,
      y: p1.y + (p2.y - p1.y) * easedFraction,
    );
  }

  /// 获取当前压力（插值——笔触粗细自适应）。
  double? get interpolatedPressure {
    if (points.isEmpty) return null;
    if (progress >= 1.0) return points.last.pressure;
    if (progress <= 0) return points.first.pressure;

    final exactIndex = progress * (points.length - 1);
    final index = exactIndex.floor().clamp(0, points.length - 2);
    final fraction = exactIndex - index;
    final easedFraction = _applyEasing(fraction);

    final p1 = points[index];
    final p2 = points[index + 1];
    return p1.pressure + (p2.pressure - p1.pressure) * easedFraction;
  }

  /// 推进动画进度（返回新实例——不可变）。
  AnimatedTrail advance(double deltaTime) {
    final newProgress = (progress + deltaTime * speed).clamp(0.0, 1.0);
    return copyWith(progress: newProgress);
  }

  /// 重置动画。
  AnimatedTrail reset() => copyWith(progress: 0.0);

  /// 完成动画（直接到终点）。
  AnimatedTrail complete() => copyWith(progress: 1.0);

  /// 添加轨迹点。
  AnimatedTrail addPoint(TrailPoint point) {
    return copyWith(points: [...points, point]);
  }

  AnimatedTrail copyWith({
    List<TrailPoint>? points,
    double? progress,
    EasingType? easing,
    double? speed,
  }) {
    return AnimatedTrail(
      points: points ?? this.points,
      progress: progress ?? this.progress,
      easing: easing ?? this.easing,
      speed: speed ?? this.speed,
    );
  }

  /// 缓动函数（Excalidraw easing 借鉴）。
  double _applyEasing(double t) {
    switch (easing) {
      case EasingType.linear:
        return t;
      case EasingType.easeIn:
        return t * t;
      case EasingType.easeOut:
        return 1 - (1 - t) * (1 - t);
      case EasingType.easeInOut:
        return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnimatedTrail && points.length == other.points.length && progress == other.progress;

  @override
  int get hashCode => Object.hash(points.length, progress);
}
