/// 可渲染笔画抽象接口 — 零外部依赖。
///
/// 定义笔画渲染所需的最小契约，解除 core/rendering 与
/// features/drawing/domain/stroke.dart 的循环依赖。
///
/// 实现类：
/// - features/drawing/domain/stroke.dart（Stroke 类实现此接口）
library;

import 'dart:ui' as ui;

import 'dart:ui';

/// 笔画点（压感输入）。
class StrokePoint {
  const StrokePoint(this.x, this.y, [this.pressure = 0.5]);

  final double x;
  final double y;
  final double pressure;

  Offset get offset => Offset(x, y);
}

/// 可渲染笔画抽象接口。
///
/// 渲染器（StrokeRenderer/StrokePictureCache）只依赖此接口，
/// 不感知具体 Stroke 实现。
abstract interface class RenderableStroke {
  /// 笔画唯一标识。
  String get id;

  /// 笔画颜色。
  int get colorValue;

  /// 笔画线宽。
  double get width;

  /// 笔画类型。
  int get brushType;

  /// 笔画点列。
  List<StrokePoint> get points;

  /// 几何版本号（点列变化时递增）。
  int get geometryRevision;

  /// 是否已完成（true=已完成，false=正在绘制）。
  bool get isComplete;

  /// 笔画不透明度。
  double get opacity;

  /// 是否启用压感。
  bool get usePressure;

  /// 获取颜色（Flutter Color）。
  ui.Color get color => ui.Color(colorValue);
}
