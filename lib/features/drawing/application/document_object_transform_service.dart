import 'dart:ui' show Offset, Rect;

import 'package:drawing_notes_app/core/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/application/selection_geometry_service.dart';
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

/// 混合画布对象的命中与边界计算结果。
///
/// 只暴露不可变对象 id 集合；选择状态的写入和通知仍由调用方协调。
class DocumentObjectHitTestResult {
  DocumentObjectHitTestResult({
    required Set<String> shapeIds,
    required Set<String> imageIds,
  }) : shapeIds = Set.unmodifiable(shapeIds),
       imageIds = Set.unmodifiable(imageIds);

  final Set<String> shapeIds;
  final Set<String> imageIds;
}

/// 混合画布对象的无状态命中与边界计算服务。
///
/// 该服务只读取领域对象集合，不保存选择、不变更文档，也不触发通知。绑定
/// 箭头在计算前会投影为当前显示几何，保证框选、套索与选择框均遵循所见即
/// 所得的规则。
class DocumentObjectGeometryService {
  const DocumentObjectGeometryService._();

  /// 返回与 [polygon] 相交的形状和图片 id。
  static DocumentObjectHitTestResult objectsIntersectingPolygon({
    required List<Offset> polygon,
    required List<PageShapeItem> shapes,
    required List<DocumentImageItem> images,
  }) {
    if (polygon.length < 3) {
      return DocumentObjectHitTestResult(shapeIds: {}, imageIds: {});
    }
    final shapeIds = <String>{};
    for (final shape in shapes) {
      final rendered = projectedShapeForSelection(shape, shapes);
      if (rectIntersectsPolygon(_shapeBounds(rendered), polygon)) {
        shapeIds.add(shape.id);
      }
    }
    final imageIds = <String>{};
    for (final image in images) {
      if (rectIntersectsPolygon(image.bounds, polygon)) {
        imageIds.add(image.id);
      }
    }
    return DocumentObjectHitTestResult(shapeIds: shapeIds, imageIds: imageIds);
  }

  /// 计算笔画、形状和图片统一选择集合的可见包围盒。
  static Rect? selectedObjectsBounds({
    required List<Stroke> strokes,
    required Iterable<int> selectedStrokeIndices,
    required List<PageShapeItem> shapes,
    required Set<String> selectedShapeIds,
    required List<DocumentImageItem> images,
    required Set<String> selectedImageIds,
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    void include(Rect rect) {
      minX = minX < rect.left ? minX : rect.left;
      minY = minY < rect.top ? minY : rect.top;
      maxX = maxX > rect.right ? maxX : rect.right;
      maxY = maxY > rect.bottom ? maxY : rect.bottom;
    }

    for (final index in selectedStrokeIndices) {
      if (index < 0 || index >= strokes.length) continue;
      for (final point in strokes[index].points) {
        minX = minX < point.x ? minX : point.x;
        minY = minY < point.y ? minY : point.y;
        maxX = maxX > point.x ? maxX : point.x;
        maxY = maxY > point.y ? maxY : point.y;
      }
    }
    for (final shape in shapes) {
      if (selectedShapeIds.contains(shape.id)) {
        include(_shapeBounds(projectedShapeForSelection(shape, shapes)));
      }
    }
    for (final image in images) {
      if (selectedImageIds.contains(image.id)) include(image.bounds);
    }
    if (!minX.isFinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// 为命中与选中框生成绑定箭头的当前投影视图，绝不修改原始形状。
  static PageShapeItem projectedShapeForSelection(
    PageShapeItem shape,
    List<PageShapeItem> shapes,
  ) {
    if (shape.shapeType != ShapeType.arrow ||
        (shape.startBinding == null && shape.endBinding == null)) {
      return shape;
    }
    final rendered = shape.copy();
    final endpoints = ShapeBindingGeometry.resolvedArrowEndpoints(
      shape,
      shapes,
    );
    ShapeBindingGeometry.applyArrowEndpoints(
      rendered,
      start: endpoints.start,
      end: endpoints.end,
    );
    return rendered;
  }

  /// 判断 [rect] 是否与 [polygon] 发生面积、包含或边缘交集。
  static bool rectIntersectsPolygon(Rect rect, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    final corners = <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    if (corners.any(
      (corner) => SelectionGeometryService.pointInPolygon(corner, polygon),
    )) {
      return true;
    }
    if (polygon.any(rect.contains)) return true;
    for (var edge = 0; edge < polygon.length; edge++) {
      final start = polygon[edge];
      final end = polygon[(edge + 1) % polygon.length];
      for (var side = 0; side < corners.length; side++) {
        if (SelectionGeometryService.segmentsIntersect(
          start,
          end,
          corners[side],
          corners[(side + 1) % 4],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static Rect _shapeBounds(PageShapeItem shape) =>
      Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);
}
