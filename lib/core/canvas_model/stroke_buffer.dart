import 'dart:typed_data';
import 'dart:ui' show Rect;

/// 笔画点列的紧凑运行时视图（内核 P0-1，专家审计整改清单 2026-10-10）。
///
/// 以 `Float32List`（stride=3：x,y,pressure）承载点列，替代逐点对象遍历。
/// 当前定位是 [Stroke] 的**派生缓存**（按 geometryRevision 失效），供渲染
/// 轮廓构建、包围盒计算等热路径免对象中转直读；点列的权威存储仍是
/// `Stroke.points`（存储反转为独立评审批，见整改清单 §七 P0 触发条件）。
///
/// 序列化不受影响：JSON 落盘沿用既有扁平数值数组（与缓冲区同构，
/// `fromPoints`/`toList` 与 DocumentCodec 的编解码语义逐字段一致）。
class StrokeBuffer {
  StrokeBuffer._(this._data, this._pointCount);

  /// 每点占用分量数：x, y, pressure。
  static const int stride = 3;

  final Float32List _data;
  final int _pointCount;

  /// 从点列对象构建紧凑缓冲（渲染热路径唯一的对象遍历点）。
  factory StrokeBuffer.fromPoints(Iterable<StrokePointLike> points) {
    final count = points.length;
    final data = Float32List(count * stride);
    var i = 0;
    for (final p in points) {
      data[i++] = p.x;
      data[i++] = p.y;
      data[i++] = p.pressure;
    }
    return StrokeBuffer._(data, count);
  }

  /// 从扁平数值数组构建（与落盘 JSON 的 `[x0,y0,p0, x1,...]` 同构）。
  factory StrokeBuffer.fromFlat(List<num> flat) {
    final count = flat.length ~/ stride;
    final data = Float32List(count * stride);
    for (var i = 0; i < count * stride; i++) {
      data[i] = flat[i].toDouble();
    }
    return StrokeBuffer._(data, count);
  }

  /// 点数。
  int get length => _pointCount;

  bool get isEmpty => _pointCount == 0;

  double xAt(int index) => _data[index * stride];
  double yAt(int index) => _data[index * stride + 1];
  double pressureAt(int index) => _data[index * stride + 2];

  /// 包围盒（惰性计算后由调用方持有——本类不缓存，缓存策略归 [Stroke]）。
  Rect? computeBounds() {
    if (_pointCount == 0) return null;
    var minX = _data[0], maxX = _data[0];
    var minY = _data[1], maxY = _data[1];
    for (var i = stride; i < _data.length; i += stride) {
      final x = _data[i], y = _data[i + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// 还原为逐点对象（兼容接口——消费方迁移完成前保留）。
  List<(double, double, double)> toTuples() => [
    for (var i = 0; i < _pointCount; i++)
      (xAt(i), yAt(i), pressureAt(i)),
  ];
}

/// 缓冲区构建所需的点形状（结构化最小接口——StrokePoint 天然满足；
/// 用接口而非具体类型可让实时预览的临时点结构零拷贝接入）。
abstract interface class StrokePointLike {
  double get x;
  double get y;
  double get pressure;
}
