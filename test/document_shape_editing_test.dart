import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PageShapeItem node(String id, double x, double y) => PageShapeItem(
    id: id,
    shapeType: ShapeType.rect,
    x: x,
    y: y,
    width: 120,
    height: 80,
    zOrder: 1,
  );

  PageShapeItem arrow() => PageShapeItem(
    id: 'arrow',
    shapeType: ShapeType.arrow,
    x: 0,
    y: 0,
    width: 1,
    height: 1,
  );

  DrawingController makeController() {
    final left = node('left', 20, 20);
    final right = node('right', 300, 100);
    final connector = arrow();
    ShapeBindingGeometry.bindArrowAtEndpoints(
      connector,
      [left, right],
      start: const Offset(110, 60),
      end: const Offset(340, 160),
    );
    return DrawingController(
      DrawingDocument(
        id: 'shape_edit',
        title: '形状编辑',
        infinite: true,
        shapes: [left, right, connector],
      ),
    );
  }

  test('形状命中遵循视觉最上层优先', () {
    final lower = node('lower', 20, 20)..zOrder = 1;
    final upper = node('upper', 20, 20)..zOrder = 2;
    final controller = DrawingController(
      DrawingDocument(
        id: 'stacked_shapes',
        title: '堆叠形状',
        infinite: true,
        shapes: [lower, upper],
      ),
    );
    addTearDown(controller.dispose);

    expect(controller.selectDocumentShapeAt(const Offset(50, 50))?.id, 'upper');
  });

  test('移动形状会让绑定箭头随动并作为一条历史事务撤销重做', () {
    final controller = makeController();
    addTearDown(controller.dispose);

    final selected = controller.selectDocumentShapeAt(const Offset(40, 40));
    expect(selected?.id, 'left');
    controller.moveSelectedDocumentShape(const Offset(40, -10));
    controller.endDocumentShapeTransform();

    final movedLeft = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'left',
    );
    final connector = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'arrow',
    );
    expect(movedLeft.x, 60);
    expect(movedLeft.y, 10);
    expect(
      ShapeBindingGeometry.arrowEndpoints(connector).start,
      const Offset(150, 50),
    );
    expect(controller.canUndo, isTrue);

    controller.undo();
    final undoneLeft = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'left',
    );
    final undoneArrow = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'arrow',
    );
    expect(undoneLeft.x, 20);
    expect(undoneLeft.y, 20);
    expect(
      ShapeBindingGeometry.arrowEndpoints(undoneArrow).start,
      const Offset(110, 60),
    );

    controller.redo();
    final redoneArrow = controller.document.shapes.firstWhere(
      (shape) => shape.id == 'arrow',
    );
    expect(
      ShapeBindingGeometry.arrowEndpoints(redoneArrow).start,
      const Offset(150, 50),
    );
  });

  test('取消形状拖动会回滚目标及绑定箭头，不写入历史', () {
    final controller = makeController();
    addTearDown(controller.dispose);
    controller.selectDocumentShapeAt(const Offset(40, 40));
    controller.moveSelectedDocumentShape(const Offset(40, -10));

    expect(controller.selectedDocumentShape?.x, 60);
    expect(
      ShapeBindingGeometry.arrowEndpoints(
        controller.document.shapes.singleWhere((shape) => shape.id == 'arrow'),
      ).start,
      const Offset(150, 50),
    );

    controller.cancelDocumentShapeTransform();
    expect(controller.selectedDocumentShape?.x, 20);
    expect(
      ShapeBindingGeometry.arrowEndpoints(
        controller.document.shapes.singleWhere((shape) => shape.id == 'arrow'),
      ).start,
      const Offset(110, 60),
    );
    expect(controller.canUndo, isFalse);
  });

  test('锁定形状会阻止变换和删除，且状态支持撤销重做', () {
    final controller = makeController();
    addTearDown(controller.dispose);
    controller.selectDocumentShapeAt(const Offset(40, 40));

    controller.toggleSelectedDocumentShapeLock();
    final shape = controller.selectedDocumentShape!;
    expect(shape.locked, isTrue);
    controller.moveSelectedDocumentShape(const Offset(100, 50));
    controller.scaleSelectedDocumentShape(2);
    controller.deleteSelectedDocumentShape();
    expect(shape.x, 20);
    expect(shape.width, 120);
    expect(controller.document.shapes, hasLength(3));

    controller.undo();
    expect(controller.selectedDocumentShape?.locked, isFalse);
    controller.redo();
    expect(controller.selectedDocumentShape?.locked, isTrue);
  });

  test('删除绑定目标会冻结对应端点为自由端，撤销后完整恢复关系', () {
    final controller = makeController();
    addTearDown(controller.dispose);
    controller.selectDocumentShapeAt(const Offset(320, 120));
    controller.deleteSelectedDocumentShape();

    final connector = controller.document.shapes.singleWhere(
      (shape) => shape.id == 'arrow',
    );
    expect(connector.startBinding?.targetShapeId, 'left');
    expect(connector.endBinding, isNull);
    expect(
      ShapeBindingGeometry.arrowEndpoints(connector).end,
      const Offset(340, 160),
    );

    controller.undo();
    final restoredArrow = controller.document.shapes.singleWhere(
      (shape) => shape.id == 'arrow',
    );
    expect(restoredArrow.endBinding?.targetShapeId, 'right');
  });
}
