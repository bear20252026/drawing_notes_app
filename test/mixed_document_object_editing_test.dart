import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DrawingDocument makeDocument({
    bool lockNode = false,
    bool lockImage = false,
  }) {
    final document = DrawingDocument(id: 'mixed_document', title: '混合对象');
    document.layers.first.strokes.add(
      Stroke(
        points: [StrokePoint(12, 12, 1), StrokePoint(36, 36, 0.8)],
        color: Color(0xFF112233),
        width: 5,
        type: BrushType.pen,
      ),
    );
    final node = PageShapeItem(
      id: 'node',
      shapeType: ShapeType.rect,
      x: 40,
      y: 40,
      width: 80,
      height: 50,
      locked: lockNode,
      zOrder: 1,
    );
    document.shapes.add(node);
    final arrow = PageShapeItem(
      id: 'arrow',
      shapeType: ShapeType.arrow,
      x: 40,
      y: 65,
      width: 180,
      height: 1,
      zOrder: 2,
    );
    ShapeBindingGeometry.bindArrowAtEndpoints(
      arrow,
      document.shapes,
      start: const Offset(40, 65),
      end: const Offset(220, 65),
    );
    document.shapes.add(arrow);
    document.imageItems.add(
      DocumentImageItem(
        id: 'image',
        x: 130,
        y: 20,
        width: 60,
        height: 45,
        filePath: '/managed/image.png',
        locked: lockImage,
        zOrder: 3,
      ),
    );
    return document;
  }

  List<Offset> allObjectsPolygon() => const [
    Offset(0, 0),
    Offset(260, 0),
    Offset(260, 130),
    Offset(0, 130),
  ];

  test('矩形/套索底层多边形可同时命中笔画、形状和图片，并给出统一包围盒', () {
    final controller = DrawingController(makeDocument());

    controller.selectDocumentObjectsInPolygon(allObjectsPolygon());

    expect(controller.hasMixedDocumentObjectSelection, isTrue);
    expect(controller.selectedDocumentObjectCount, 4);
    expect(controller.selection.selectedStrokeIndices, [0]);
    expect(controller.selectedDocumentShapeIds, {'node', 'arrow'});
    expect(controller.selectedDocumentImageIds, {'image'});
    expect(
      controller.selectedDocumentObjectsBounds,
      const Rect.fromLTRB(12, 12, 220, 90),
    );

    controller.dispose();
  });

  test('组移动将笔画、节点、图片和箭头自由端纳入单一事务，撤销重做保持绑定投影', () {
    final controller = DrawingController(makeDocument());
    controller.selectDocumentObjectsInPolygon(allObjectsPolygon());

    controller.moveSelectedDocumentObjects(const Offset(30, -10));
    controller.endDocumentObjectsTransform();

    final movedNode = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'node',
    );
    final movedArrow = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'arrow',
    );
    expect(movedNode.position, const Offset(70, 30));
    expect(
      controller.document.imageItems.single.position,
      const Offset(160, 10),
    );
    expect(
      controller.document.layers.single.strokes.single.points.first.offset,
      const Offset(42, 2),
    );
    expect(
      ShapeBindingGeometry.resolvedArrowEndpoints(
        movedArrow,
        controller.document.shapes,
      ).start,
      const Offset(70, 55),
    );
    expect(
      ShapeBindingGeometry.arrowEndpoints(movedArrow).end,
      const Offset(250, 55),
    );

    controller.undo();
    final undoneArrow = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'arrow',
    );
    expect(
      controller.document.shapes
          .firstWhere((shape) => shape.id == 'node')
          .position,
      const Offset(40, 40),
    );
    expect(
      controller.document.imageItems.single.position,
      const Offset(130, 20),
    );
    expect(
      controller.document.layers.single.strokes.single.points.first.offset,
      const Offset(12, 12),
    );
    expect(
      ShapeBindingGeometry.resolvedArrowEndpoints(
        undoneArrow,
        controller.document.shapes,
      ).start,
      const Offset(40, 65),
    );
    expect(
      ShapeBindingGeometry.arrowEndpoints(undoneArrow).end,
      const Offset(220, 65),
    );

    controller.redo();
    expect(
      controller.document.shapes
          .firstWhere((shape) => shape.id == 'node')
          .position,
      const Offset(70, 30),
    );
    expect(
      controller.document.imageItems.single.position,
      const Offset(160, 10),
    );

    controller.dispose();
  });

  test('组缩放围绕统一包围盒中心，绑定端点随节点重投影', () {
    final controller = DrawingController(makeDocument());
    controller.selectDocumentObjectsInPolygon(allObjectsPolygon());
    final beforeBounds = controller.selectedDocumentObjectsBounds!;

    controller.scaleSelectedDocumentObjects(0.5);
    controller.endDocumentObjectsTransform();

    final node = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'node',
    );
    final arrow = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'arrow',
    );
    expect(node.width, 40);
    expect(node.height, 25);
    expect(node.position, const Offset(78, 45.5));
    expect(
      ShapeBindingGeometry.resolvedArrowEndpoints(
        arrow,
        controller.document.shapes,
      ).start,
      const Offset(78, 58),
    );
    expect(controller.document.imageItems.single.width, 32);
    expect(controller.document.imageItems.single.height, 24);
    expect(
      controller.selectedDocumentObjectsBounds!.width,
      lessThan(beforeBounds.width),
    );

    controller.undo();
    expect(
      controller.document.shapes
          .firstWhere((shape) => shape.id == 'node')
          .width,
      80,
    );

    controller.dispose();
  });

  test('锁定对象保持选择反馈但拒绝变换，未锁笔画仍可在同一组中移动', () {
    final controller = DrawingController(
      makeDocument(lockNode: true, lockImage: true),
    );
    controller.selectDocumentObjectsInPolygon(allObjectsPolygon());

    expect(controller.mixedDocumentSelectionHasLockedObjects, isTrue);
    controller.moveSelectedDocumentObjects(const Offset(20, 10));
    controller.endDocumentObjectsTransform();

    expect(
      controller.document.shapes
          .firstWhere((shape) => shape.id == 'node')
          .position,
      const Offset(40, 40),
    );
    expect(
      controller.document.imageItems.single.position,
      const Offset(130, 20),
    );
    expect(
      controller.document.layers.single.strokes.single.points.first.offset,
      const Offset(32, 22),
    );

    controller.dispose();
  });

  test('取消组变换恢复完整快照；批量删除目标时箭头自由端降级且撤销可恢复关系', () {
    final controller = DrawingController(makeDocument());
    controller.selectDocumentObjectsInPolygon(allObjectsPolygon());

    controller.moveSelectedDocumentObjects(const Offset(50, 30));
    controller.cancelDocumentObjectsTransform();
    expect(
      controller.document.shapes
          .firstWhere((shape) => shape.id == 'node')
          .position,
      const Offset(40, 40),
    );
    expect(
      controller.document.imageItems.single.position,
      const Offset(130, 20),
    );

    controller.document.shapes
            .firstWhere((shape) => shape.id == 'arrow')
            .locked =
        true;
    controller.selectDocumentObjectsInPolygon(const [
      Offset(30, 30),
      Offset(125, 30),
      Offset(125, 100),
      Offset(30, 100),
    ]);
    expect(controller.selectedDocumentShapeIds, contains('node'));
    controller.deleteSelectedDocumentObjects();

    expect(
      controller.document.shapes.where((shape) => shape.id == 'node'),
      isEmpty,
    );
    final freedArrow = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'arrow',
    );
    expect(freedArrow.startBinding, isNull);
    expect(
      ShapeBindingGeometry.arrowEndpoints(freedArrow).start,
      const Offset(40, 66),
    );

    controller.undo();
    final restoredArrow = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'arrow',
    );
    expect(
      controller.document.shapes.where((shape) => shape.id == 'node'),
      hasLength(1),
    );
    expect(restoredArrow.startBinding?.targetShapeId, 'node');
    expect(
      ShapeBindingGeometry.resolvedArrowEndpoints(
        restoredArrow,
        controller.document.shapes,
      ).start,
      const Offset(40, 65),
    );

    controller.dispose();
  });
}
