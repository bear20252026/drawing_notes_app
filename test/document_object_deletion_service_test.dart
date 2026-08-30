import 'dart:ui' show Color, Offset;

import 'package:drawing_notes_app/features/drawing/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/application/document_object_transform_service.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_endpoint_binding.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('删除绑定目标会冻结箭头端点并解除失效绑定', () {
    final target = PageShapeItem(
      id: 'target',
      shapeType: ShapeType.rect,
      x: 40,
      y: 50,
      width: 80,
      height: 40,
    );
    final arrow = PageShapeItem(
      id: 'arrow',
      shapeType: ShapeType.arrow,
      x: 0,
      y: 0,
      width: 200,
      height: 100,
      startBinding: ShapeEndpointBinding(
        targetShapeId: target.id,
        anchorX: 0.5,
        anchorY: 0.5,
      ),
    );
    final shapes = <PageShapeItem>[target, arrow];
    final frozenStart = ShapeBindingGeometry.resolvedArrowEndpoints(
      arrow,
      shapes,
    ).start;

    final changed = DocumentObjectDeletionService.deleteSelection(
      strokes: <Stroke>[],
      selectedStrokeIndices: const <int>[],
      shapes: shapes,
      selectedShapeIds: <String>{target.id},
      images: <DocumentImageItem>[],
      selectedImageIds: const <String>{},
    );

    expect(changed, isTrue);
    expect(shapes, <PageShapeItem>[arrow]);
    expect(arrow.startBinding, isNull);
    expect(ShapeBindingGeometry.arrowEndpoints(arrow).start, frozenStart);
  });

  test('锁定对象不会被删除，未锁笔画按降序索引移除', () {
    Stroke strokeAt(double x) => Stroke(
      points: <StrokePoint>[StrokePoint(x, 0, 1)],
      color: const Color(0xFF000000),
      width: 2,
      type: BrushType.pen,
    );

    final strokes = <Stroke>[strokeAt(0), strokeAt(10), strokeAt(20)];
    final lockedImage = DocumentImageItem(
      id: 'locked-image',
      x: 0,
      y: 0,
      filePath: '/tmp/locked.png',
      locked: true,
    );
    final images = <DocumentImageItem>[lockedImage];

    final changed = DocumentObjectDeletionService.deleteSelection(
      strokes: strokes,
      selectedStrokeIndices: const <int>[0, 2],
      shapes: <PageShapeItem>[],
      selectedShapeIds: const <String>{},
      images: images,
      selectedImageIds: <String>{lockedImage.id},
    );

    expect(changed, isTrue);
    expect(strokes, hasLength(1));
    expect(strokes.single.points.single.offset, const Offset(10, 0));
    expect(images, <DocumentImageItem>[lockedImage]);
  });

  test('仅选择锁定对象不会修改集合', () {
    final lockedShape = PageShapeItem(
      id: 'locked-shape',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      locked: true,
    );

    final changed = DocumentObjectDeletionService.deleteSelection(
      strokes: <Stroke>[],
      selectedStrokeIndices: const <int>[],
      shapes: <PageShapeItem>[lockedShape],
      selectedShapeIds: <String>{lockedShape.id},
      images: <DocumentImageItem>[],
      selectedImageIds: const <String>{},
    );

    expect(changed, isFalse);
    expect(lockedShape.locked, isTrue);
  });
}
