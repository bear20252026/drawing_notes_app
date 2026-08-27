import 'dart:ui' show Offset;

import 'package:drawing_notes_app/core/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 混合画布对象的无状态几何变换服务。
///
/// 服务只修改调用方提供的领域对象集合，并处理箭头绑定的端点投影；它不持有
/// 选择状态、不创建历史快照，也不触发文档缓存或 UI 刷新。这使
/// [DocumentObjectEditingSession] 可以专注于手势事务、快照和宿主协调。
class DocumentObjectTransformService {
  const DocumentObjectTransformService._();

  /// 判断当前选择中是否至少有一个可变换对象。
  static bool hasTransformableSelection({
    required Iterable<int> selectedStrokeIndices,
    required Iterable<PageShapeItem> shapes,
    required Set<String> selectedShapeIds,
    required Iterable<DocumentImageItem> images,
    required Set<String> selectedImageIds,
  }) =>
      selectedStrokeIndices.isNotEmpty ||
      shapes.any(
        (shape) => selectedShapeIds.contains(shape.id) && !shape.locked,
      ) ||
      images.any(
        (image) => selectedImageIds.contains(image.id) && !image.locked,
      );

  /// 对选中的笔画、形状和图片应用 [transform]。
  ///
  /// [scale] 为 `null` 时只平移位置；非空时同步缩放非线性形状和图片，并按
  /// 最小操作尺寸截断。被锁定的形状和图片始终保留原样。选中箭头的自由端
  /// 跟随变换，已绑定端则通过最终的 [reprojectBoundArrows] 保持锚点语义。
  static void transformSelection({
    required List<Stroke> strokes,
    required Iterable<int> selectedStrokeIndices,
    required List<PageShapeItem> shapes,
    required Set<String> selectedShapeIds,
    required List<DocumentImageItem> images,
    required Set<String> selectedImageIds,
    required Offset Function(Offset point) transform,
    required double? scale,
  }) {
    final selectedArrowEndpoints = <String, ({Offset start, Offset end})>{};
    for (final shape in shapes) {
      if (selectedShapeIds.contains(shape.id) &&
          !shape.locked &&
          shape.shapeType == ShapeType.arrow) {
        selectedArrowEndpoints[shape.id] =
            ShapeBindingGeometry.resolvedArrowEndpoints(shape, shapes);
      }
    }

    for (final index in selectedStrokeIndices.toSet().toList()..sort()) {
      if (index < 0 || index >= strokes.length) continue;
      final old = strokes[index];
      strokes[index] = Stroke(
        points: old.points
            .map((point) {
              final next = transform(point.offset);
              return StrokePoint(next.dx, next.dy, point.pressure);
            })
            .toList(growable: false),
        color: old.color,
        width: old.width,
        type: old.type,
        opacity: old.opacity,
      );
    }

    final nextScale = scale ?? 1.0;
    for (final shape in shapes) {
      if (!selectedShapeIds.contains(shape.id) ||
          shape.locked ||
          shape.shapeType == ShapeType.arrow) {
        continue;
      }
      final oldBounds = ShapeBindingGeometry.rawBounds(shape);
      final nextTopLeft = transform(oldBounds.topLeft);
      shape
        ..x = nextTopLeft.dx
        ..y = nextTopLeft.dy
        ..width = (oldBounds.width * nextScale).clamp(16.0, 8192.0)
        ..height = (oldBounds.height * nextScale).clamp(16.0, 8192.0);
    }

    for (final image in images) {
      if (!selectedImageIds.contains(image.id) || image.locked) continue;
      final nextTopLeft = transform(image.bounds.topLeft);
      image
        ..x = nextTopLeft.dx
        ..y = nextTopLeft.dy
        ..width = (image.width * nextScale).clamp(32.0, 8192.0)
        ..height = (image.height * nextScale).clamp(24.0, 8192.0);
    }

    for (final shape in shapes) {
      final endpoints = selectedArrowEndpoints[shape.id];
      if (endpoints == null) continue;
      final start = shape.startBinding == null
          ? transform(endpoints.start)
          : endpoints.start;
      final end = shape.endBinding == null
          ? transform(endpoints.end)
          : endpoints.end;
      ShapeBindingGeometry.applyArrowEndpoints(shape, start: start, end: end);
    }

    reprojectBoundArrows(shapes);
  }

  /// 根据当前目标形状重新投影所有绑定箭头。
  static void reprojectBoundArrows(List<PageShapeItem> shapes) {
    for (final arrow in shapes) {
      ShapeBindingGeometry.reprojectArrow(arrow, shapes);
    }
  }
}

/// 混合画布对象的无状态删除服务。
///
/// 服务只处理调用方提供集合的删除和箭头绑定降级，不持有选择、不创建快照，
/// 也不触发缓存或 UI 刷新。事务、选择清理和撤销命令仍由
/// `DocumentObjectEditingSession` 协调。
class DocumentObjectDeletionService {
  const DocumentObjectDeletionService._();

  /// 删除当前选中的未锁形状、未锁图片和笔画。
  ///
  /// 若删除形状是箭头端点绑定目标，先冻结箭头的当前绝对端点并清除失效绑定，
  /// 从而使未删除的箭头保持可见几何而不遗留悬挂对象 id。返回值表示是否实际
  /// 修改了任一集合。
  static bool deleteSelection({
    required List<Stroke> strokes,
    required Iterable<int> selectedStrokeIndices,
    required List<PageShapeItem> shapes,
    required Set<String> selectedShapeIds,
    required List<DocumentImageItem> images,
    required Set<String> selectedImageIds,
  }) {
    final deleteShapeIds = shapes
        .where((shape) => selectedShapeIds.contains(shape.id) && !shape.locked)
        .map((shape) => shape.id)
        .toSet();
    final deleteImageIds = images
        .where((image) => selectedImageIds.contains(image.id) && !image.locked)
        .map((image) => image.id)
        .toSet();
    final orderedStrokeIndices = selectedStrokeIndices.toSet().toList()..sort();
    final hasValidStroke = orderedStrokeIndices.any(
      (index) => index >= 0 && index < strokes.length,
    );
    if (deleteShapeIds.isEmpty && deleteImageIds.isEmpty && !hasValidStroke) {
      return false;
    }

    detachBindingsForDeletedShapes(shapes, deleteShapeIds);
    shapes.removeWhere((shape) => deleteShapeIds.contains(shape.id));
    images.removeWhere((image) => deleteImageIds.contains(image.id));
    for (final index in orderedStrokeIndices.reversed) {
      if (index >= 0 && index < strokes.length) strokes.removeAt(index);
    }
    return true;
  }

  /// 将指向被删除形状的箭头端点降级为冻结的自由端点。
  static void detachBindingsForDeletedShapes(
    List<PageShapeItem> shapes,
    Set<String> deletedShapeIds,
  ) {
    if (deletedShapeIds.isEmpty) return;
    for (final arrow in shapes) {
      if (arrow.shapeType != ShapeType.arrow ||
          deletedShapeIds.contains(arrow.id)) {
        continue;
      }
      final endpoints = ShapeBindingGeometry.resolvedArrowEndpoints(
        arrow,
        shapes,
      );
      var changed = false;
      if (deletedShapeIds.contains(arrow.startBinding?.targetShapeId)) {
        arrow.startBinding = null;
        changed = true;
      }
      if (deletedShapeIds.contains(arrow.endBinding?.targetShapeId)) {
        arrow.endBinding = null;
        changed = true;
      }
      if (changed) {
        ShapeBindingGeometry.applyArrowEndpoints(
          arrow,
          start: endpoints.start,
          end: endpoints.end,
        );
      }
    }
  }
}
