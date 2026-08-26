// core/abstractions — 形状绑定几何抽象接口
// 遵循 Clean Architecture：定义抽象契约，实现由 Infrastructure 层提供

import 'dart:ui';

import '../../../features/drawing/domain/shape_item.dart';

/// 形状绑定几何抽象接口
///
/// 计算形状与笔画之间的绑定关系
abstract class ShapeBindingGeometry {
  /// 计算形状绑定的笔画
  List<int> boundStrokes(PageShapeItem shape, List<dynamic> strokes);

  /// 计算形状的锚点
  List<Offset> anchorPoints(PageShapeItem shape);
}
