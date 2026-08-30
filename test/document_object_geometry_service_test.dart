import 'dart:ui' show Color, Offset, Rect;

import 'package:drawing_notes_app/features/drawing/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/application/document_object_transform_service.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_endpoint_binding.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('多边形命中同时覆盖包含、边缘相交和图片边界', () {
    final shape = PageShapeItem(
      id: 'shape',
      shapeType: ShapeType.rect,
      x: 10,
      y: 10,
      width: 20,
      height: 20,
    );
    final image = DocumentImageItem(
      id: 'image',
      x: 50,
      y: 10,
      width: 20,
      height: 20,
      filePath: '/tmp/image.png',
    );

    final hitTest = DocumentObjectGeometryService.objectsIntersectingPolygon(
      polygon: const <Offset>[
        Offset(12, 12),
        Offset(14, 12),
        Offset(14, 14),
        Offset(12, 14),
      ],
      shapes: <PageShapeItem>[shape],
      images: <DocumentImageItem>[image],
    );

    expect(hitTest.shapeIds, <String>{shape.id});
    expect(hitTest.imageIds, isEmpty);
    expect(
      DocumentObjectGeometryService.rectIntersectsPolygon(
        Rect.fromLTWH(10, 10, 20, 20),
        const <Offset>[
          Offset(0, 20),
          Offset(40, 20),
          Offset(40, 25),
          Offset(0, 25),
        ],
      ),
      isTrue,
    );
  });

  test('绑定箭头按当前目标投影用于命中且不修改原始形状', () {
    final target = PageShapeItem(
      id: 'target',
      shapeType: ShapeType.rect,
      x: 100,
      y: 100,
      width: 40,
      height: 40,
    );
    final arrow = PageShapeItem(
      id: 'arrow',
      shapeType: ShapeType.arrow,
      x: 0,
      y: 0,
      width: 20,
      height: 20,
      startBinding: ShapeEndpointBinding(
        targetShapeId: target.id,
        anchorX: 0.5,
        anchorY: 0.5,
      ),
    );
    final shapes = <PageShapeItem>[target, arrow];
    final expectedStart = ShapeBindingGeometry.resolvedArrowEndpoints(
      arrow,
      shapes,
    ).start;

    final projected = DocumentObjectGeometryService.projectedShapeForSelection(
      arrow,
      shapes,
    );

    expect(projected, isNot(same(arrow)));
    expect(ShapeBindingGeometry.arrowEndpoints(projected).start, expectedStart);
    expect(arrow.position, const Offset(0, 0));
  });

  test('统一包围盒合并有效笔画、形状与图片并忽略无效索引', () {
    final strokes = <Stroke>[
      Stroke(
        points: const <StrokePoint>[StrokePoint(0, 2, 1), StrokePoint(3, 7, 1)],
        color: const Color(0xFF000000),
        width: 2,
        type: BrushType.pen,
      ),
    ];
    final shape = PageShapeItem(
      id: 'shape',
      shapeType: ShapeType.rect,
      x: 10,
      y: 20,
      width: 5,
      height: 10,
    );
    final image = DocumentImageItem(
      id: 'image',
      x: -2,
      y: 30,
      width: 3,
      height: 4,
      filePath: '/tmp/image.png',
    );

    final bounds = DocumentObjectGeometryService.selectedObjectsBounds(
      strokes: strokes,
      selectedStrokeIndices: const <int>[-1, 0, 9],
      shapes: <PageShapeItem>[shape],
      selectedShapeIds: <String>{shape.id},
      images: <DocumentImageItem>[image],
      selectedImageIds: <String>{image.id},
    );

    expect(bounds, const Rect.fromLTRB(-2, 2, 15, 34));
    expect(
      DocumentObjectGeometryService.selectedObjectsBounds(
        strokes: strokes,
        selectedStrokeIndices: const <int>[9],
        shapes: <PageShapeItem>[shape],
        selectedShapeIds: const <String>{},
        images: <DocumentImageItem>[image],
        selectedImageIds: const <String>{},
      ),
      isNull,
    );
  });
}
