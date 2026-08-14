import 'dart:ui';

import '../models/shape_item.dart';

/// 由一次按下—拖拽—抬起手势生成形状的几何结果。
class ShapeCreationGeometry {
  const ShapeCreationGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.flipX,
    required this.flipY,
  });

  static const double _clickThreshold = 4;
  static const double _defaultWidth = 160;
  static const double _defaultHeight = 110;
  static const double _minSize = 2;
  static const double _maxSize = 10000;

  final double x;
  final double y;
  final double width;
  final double height;
  final bool flipX;
  final bool flipY;

  factory ShapeCreationGeometry.fromDrag(Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final isClick = dx.abs() < _clickThreshold && dy.abs() < _clickThreshold;
    final width = isClick
        ? _defaultWidth
        : dx.abs().clamp(_minSize, _maxSize).toDouble();
    final height = isClick
        ? _defaultHeight
        : dy.abs().clamp(_minSize, _maxSize).toDouble();
    return ShapeCreationGeometry(
      x: isClick ? start.dx - width / 2 : _min(start.dx, end.dx),
      y: isClick ? start.dy - height / 2 : _min(start.dy, end.dy),
      width: width,
      height: height,
      flipX: !isClick && dx < 0,
      flipY: !isClick && dy < 0,
    );
  }

  PageShapeItem createShape({
    required String id,
    required ShapeType shapeType,
    required int color,
    required double strokeWidth,
    String? boundElementId,
  }) => PageShapeItem(
    id: id,
    shapeType: shapeType,
    x: x,
    y: y,
    width: width,
    height: height,
    color: color,
    strokeWidth: strokeWidth.clamp(1, 20).toDouble(),
    flipX: flipX,
    flipY: flipY,
    boundElementId: boundElementId,
  );

  static double _min(double a, double b) => a < b ? a : b;
}
