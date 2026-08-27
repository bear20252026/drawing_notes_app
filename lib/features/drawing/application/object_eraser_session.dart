import 'dart:ui' show Offset;

import 'package:drawing_notes_app/core/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/application/selection_geometry_service.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 一次对象橡皮擦手势所产生的增量变更。
///
/// 删除前位置和对象引用可由命令层精确回放，无需为连续擦除手势复制整层数据。
typedef ObjectEraseResult = ({
  List<({int layerIndex, int index, Stroke stroke})> removedStrokes,
  List<PageShapeItem> removedShapes,
  Set<int> changedLayerIndices,
});

/// 一次橡皮擦采样点对当前文档产生的即时变更。
typedef ObjectEraseStep = ({bool changed, Set<int> changedLayerIndices});

/// 运行时对象橡皮擦会话。
///
/// 该会话管理“整笔擦除”手势的开始、连续命中、形状擦除开关以及增量结果；
/// 它直接更新绘图文档，但不接触撤销栈、离屏缓存或 UI 通知，因而可由
/// [DrawingController] 在手势结束时将结果包装为单条命令。
class ObjectEraserSession {
  bool canEraseShapesStroke = true;
  bool canEraseShapesPixel = true;

  final List<({int layerIndex, int index, Stroke stroke})> _removedStrokes =
      <({int layerIndex, int index, Stroke stroke})>[];
  final List<PageShapeItem> _removedShapes = <PageShapeItem>[];
  final Set<int> _changedLayerIndices = <int>{};

  bool _changed = false;

  bool get hasChanges => _changed;

  bool canEraseShapes(EraserMode mode) =>
      mode == EraserMode.stroke ? canEraseShapesStroke : canEraseShapesPixel;

  void begin() {
    _removedStrokes.clear();
    _removedShapes.clear();
    _changedLayerIndices.clear();
    _changed = false;
  }

  /// 从文档中删除命中的整条笔画和允许擦除的标准形状。
  ///
  /// 返回本次采样点的即时变更。连续手势可反复调用，完整结果会累积到同一
  /// 会话中，以便结束时只生成一条撤销记录。
  ObjectEraseStep eraseAt(
    DrawingDocument document,
    Offset canvasPoint, {
    required double eraserSize,
    required EraserMode mode,
  }) {
    final radius = eraserSize / 2;
    var changedAtPoint = false;
    final changedLayerIndices = <int>{};

    for (
      var layerIndex = 0;
      layerIndex < document.layers.length;
      layerIndex++
    ) {
      final layer = document.layers[layerIndex];
      if (!layer.visible) continue;
      final removed = <({int index, Stroke stroke})>[];
      for (var index = 0; index < layer.strokes.length; index++) {
        final stroke = layer.strokes[index];
        if (_strokeHitsCircle(stroke, canvasPoint, radius)) {
          removed.add((index: index, stroke: stroke));
        }
      }
      if (removed.isEmpty) continue;
      for (final entry in removed.reversed) {
        layer.strokes.removeAt(entry.index);
      }
      _removedStrokes.addAll(<({int layerIndex, int index, Stroke stroke})>[
        for (final entry in removed)
          (layerIndex: layerIndex, index: entry.index, stroke: entry.stroke),
      ]);
      _changedLayerIndices.add(layerIndex);
      changedLayerIndices.add(layerIndex);
      changedAtPoint = true;
    }

    if (canEraseShapes(mode) && document.shapes.isNotEmpty) {
      final hitShapes = <PageShapeItem>[
        for (final shape in document.shapes)
          if (_shapeHitsEraser(shape, canvasPoint, radius)) shape,
      ];
      if (hitShapes.isNotEmpty) {
        for (final shape in hitShapes) {
          document.shapes.remove(shape);
        }
        _removedShapes.addAll(hitShapes);
        changedAtPoint = true;
      }
    }

    if (changedAtPoint) _changed = true;
    return (
      changed: changedAtPoint,
      changedLayerIndices: Set<int>.of(changedLayerIndices),
    );
  }

  /// 返回本次手势的不可变结果并开始新的空会话；无变更时返回 null。
  ObjectEraseResult? consumeResult() {
    if (!_changed) {
      begin();
      return null;
    }
    final result = (
      removedStrokes: List<({int layerIndex, int index, Stroke stroke})>.of(
        _removedStrokes,
      ),
      removedShapes: List<PageShapeItem>.of(_removedShapes),
      changedLayerIndices: Set<int>.of(_changedLayerIndices),
    );
    begin();
    return result;
  }

  static bool _shapeHitsEraser(
    PageShapeItem shape,
    Offset center,
    double radius,
  ) {
    final bounds = ShapeBindingGeometry.rawBounds(shape).inflate(radius);
    if (!bounds.contains(center)) return false;
    // 线和箭头按实际端点检测，避免宽外接框造成错误擦除。
    if (shape.shapeType != ShapeType.line &&
        shape.shapeType != ShapeType.arrow) {
      return true;
    }
    final start = shape.lineStart ?? Offset(0, shape.height);
    final end = shape.lineEnd ?? Offset(shape.width, 0);
    final origin = Offset(shape.x, shape.y);
    return _distanceToSegment(center, start + origin, end + origin) <= radius;
  }

  static bool _strokeHitsCircle(Stroke stroke, Offset center, double radius) {
    if (stroke.points.isEmpty) return false;
    final threshold = radius + stroke.width / 2;
    for (var index = 0; index < stroke.points.length - 1; index++) {
      if (_distanceToSegment(
            center,
            stroke.points[index].offset,
            stroke.points[index + 1].offset,
          ) <=
          threshold) {
        return true;
      }
    }
    return stroke.points.any(
      (point) => (point.offset - center).distance <= threshold,
    );
  }

  static double _distanceToSegment(Offset point, Offset start, Offset end) =>
      SelectionGeometryService.distanceToSegment(point, start, end);
}
