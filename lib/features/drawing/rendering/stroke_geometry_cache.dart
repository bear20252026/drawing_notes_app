import 'package:drawing_notes_app/core/canvas_model/stroke.dart';

/// 笔画的双质量几何缓存。
///
/// 高采样率触控笔可在一个显示帧内产生大量近似重合的 PointerMove 事件。
/// 实时预览只维护稀疏点列，并以最后一点跟随笔尖；收笔后再从完整原始
/// 采样中构建用于保存和重绘的高质量点列。这既降低书写中的路径构造成本，
/// 也避免导出或重开文档时损失压感细节。
class StrokeGeometryCache {
  StrokeGeometryCache(StrokePoint firstPoint)
    : _rawPoints = <StrokePoint>[firstPoint],
      _previewPoints = <StrokePoint>[firstPoint];

  /// 相邻预览锚点的最小间隔。小于该距离的连续移动只更新预览末端。
  static const double previewSpacing = 1.5;

  /// 持久化时允许压缩的近点间隔。
  static const double finalSpacing = 0.35;

  /// 压感变化达到阈值时，即使位置很近也保留该点。
  static const double pressureTolerance = 0.015;

  final List<StrokePoint> _rawPoints;
  final List<StrokePoint> _previewPoints;

  /// 当前给活动笔画渲染的低开销点列。调用方不可替换该列表。
  List<StrokePoint> get previewPoints => _previewPoints;

  /// 收笔前的完整原始采样数，供性能诊断与测试使用。
  int get rawPointCount => _rawPoints.length;

  /// 追加一个原始输入样本，并同步更新稀疏预览。
  void append(StrokePoint point) {
    _rawPoints.add(point);
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
