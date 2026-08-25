import 'dart:math' as math;

import '../../features/drawing/domain/stroke.dart';

/// 笔画的双质量几何缓存。
///
/// 高采样率触控笔可在一个显示帧内产生大量近似重合的 PointerMove 事件。
/// 实时预览只维护稀疏点列，并以最后一点跟随笔尖；收笔后再从完整原始
/// 采样中构建用于保存和重绘的高质量点列。这既降低书写中的路径构造成本，
/// 也避免导出或重开文档时损失压感细节。
///
/// 速度感知宽度（借鉴 Saber 思路）：快速书写时笔触自动变细，慢速时变粗，
/// 模拟真实钢笔的墨水流量特性。速度通过相邻采样点的距离/时间差计算，
/// 并经过 EMA 平滑避免突变。
class StrokeGeometryCache {
  StrokeGeometryCache(StrokePoint firstPoint)
    : _rawPoints = <StrokePoint>[firstPoint],
      _previewPoints = <StrokePoint>[firstPoint],
      _lastAppendTime = DateTime.now();

  /// 相邻预览锚点的最小间隔。小于该距离的连续移动只更新预览末端。
  static const double previewSpacing = 1.5;

  /// 持久化时允许压缩的近点间隔。
  static const double finalSpacing = 0.35;

  /// 压感变化达到阈值时，即使位置很近也保留该点。
  static const double pressureTolerance = 0.015;

  /// 速度→宽度映射的平滑系数（EMA）。0 = 不平滑，1 = 完全平滑。
  static const double speedSmoothing = 0.3;

  /// 参考速度（像素/毫秒）：低于此速度使用全宽，高于此速度线性减细。
  /// 约等于正常书写速度。
  static const double referenceSpeed = 0.8;

  /// 最小宽度系数：速度极快时笔触不会细于 baseWidth × minWidthFactor。
  static const double speedMinWidthFactor = 0.35;

  final List<StrokePoint> _rawPoints;
  final List<StrokePoint> _previewPoints;
  DateTime _lastAppendTime;
  double _smoothedSpeed = 0;

  /// 当前给活动笔画渲染的低开销点列。调用方不可替换该列表。
  List<StrokePoint> get previewPoints => _previewPoints;

  /// 收笔前的完整原始采样数，供性能诊断与测试使用。
  int get rawPointCount => _rawPoints.length;

  /// 当前平滑后的速度（像素/毫秒），供外部读取。
  double get currentSpeed => _smoothedSpeed;

  /// 根据当前速度计算宽度系数（0~1），用于调制笔触宽度。
  ///
  /// 速度越快系数越小（笔触越细），模拟真实钢笔墨水流量。
  /// 返回值在 [speedMinWidthFactor, 1.0] 范围内。
  static double speedWidthFactor(double speed) {
    if (speed <= referenceSpeed) return 1.0;
    final excess = (speed - referenceSpeed) / referenceSpeed;
    return (1.0 - excess * 0.6).clamp(speedMinWidthFactor, 1.0);
  }

  /// 追加一个原始输入样本，并同步更新稀疏预览与速度追踪。
  void append(StrokePoint point) {
    _rawPoints.add(point);

    // 速度计算：距离 / 时间差
    final now = DateTime.now();
    final dt = now.difference(_lastAppendTime).inMilliseconds;
    if (dt > 0) {
      final tail = _previewPoints.last;
      final dx = point.x - tail.x;
      final dy = point.y - tail.y;
      final distance = math.sqrt(dx * dx + dy * dy);
      final instantSpeed = distance / dt;
      _smoothedSpeed =
          _smoothedSpeed * speedSmoothing + instantSpeed * (1 - speedSmoothing);
    }
    _lastAppendTime = now;

    final tail = _previewPoints.last;
    if (_distanceSquared(tail, point) >= previewSpacing * previewSpacing ||
        (tail.pressure - point.pressure).abs() >= pressureTolerance) {
      _previewPoints.add(point);
    } else {
      // 不增加几何复杂度，但让当前笔尖准确跟随输入位置。
      _previewPoints[_previewPoints.length - 1] = point;
    }
  }

  /// 基于完整原始采样构建最终点列。
  ///
  /// 只删除空间与压感都近似不变的重复样本；第一点、最后一点以及任何明显
  /// 压感变化均会保留，因此最终路径的质量不依赖于实时预览的稀疏程度。
  List<StrokePoint> finish() {
    if (_rawPoints.length <= 2) return List<StrokePoint>.of(_rawPoints);

    final result = <StrokePoint>[_rawPoints.first];
    for (var i = 1; i < _rawPoints.length - 1; i++) {
      final point = _rawPoints[i];
      final last = result.last;
      final isFarEnough =
          _distanceSquared(last, point) >= finalSpacing * finalSpacing;
      final hasPressureChange =
          (last.pressure - point.pressure).abs() >= pressureTolerance;
      if (isFarEnough || hasPressureChange) {
        result.add(point);
      }
    }

    final lastPoint = _rawPoints.last;
    if (!_sameSample(result.last, lastPoint)) result.add(lastPoint);
    return result;
  }

  static bool _sameSample(StrokePoint a, StrokePoint b) =>
      a.x == b.x && a.y == b.y && a.pressure == b.pressure;

  static double _distanceSquared(StrokePoint a, StrokePoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return dx * dx + dy * dy;
  }
}
