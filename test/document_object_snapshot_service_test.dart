import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DrawingDocument document({
    required List<Layer> layers,
    required List<PageShapeItem> shapes,
    required List<DocumentImageItem> images,
  }) => DrawingDocument(
    id: 'snapshot_document',
    title: '快照测试',
    infinite: true,
    layers: layers,
    shapes: shapes,
    imageItems: images,
  );

  test('捕获快照与后续形状、图片、图层列表变更隔离', () {
    final source = document(
      layers: <Layer>[Layer(id: 'base', name: '底层')],
      shapes: <PageShapeItem>[
        PageShapeItem(id: 'shape', shapeType: ShapeType.rect, x: 10, y: 20),
      ],
      images: <DocumentImageItem>[
        DocumentImageItem(
          id: 'image',
          x: 30,
          y: 40,
          filePath: '/assets/image.png',
        ),
      ],
    );

    final snapshot = DocumentObjectSnapshotService.capture(source);
    source.shapes.single.x = 99;
    source.imageItems.single.y = 88;
    source.layers.add(Layer(id: 'extra', name: '新增'));

    expect(snapshot.layers, hasLength(1));
    expect(snapshot.shapes.single.x, 10);
    expect(snapshot.images.single.y, 40);
  });

  test('恢复完整替换对象集合并维持快照与目标对象独立', () {
    final source = document(
      layers: <Layer>[
        Layer(id: 'base', name: '底层'),
        Layer(id: 'top', name: '顶层'),
      ],
      shapes: <PageShapeItem>[
        PageShapeItem(
          id: 'shape',
          shapeType: ShapeType.ellipse,
          x: 10,
          y: 20,
          width: 30,
          height: 40,
        ),
      ],
      images: <DocumentImageItem>[
        DocumentImageItem(
          id: 'image',
          x: 50,
          y: 60,
          filePath: '/assets/image.png',
        ),
      ],
    );
    final snapshot = DocumentObjectSnapshotService.capture(source);
    final target = document(
      layers: <Layer>[Layer(id: 'stale', name: '过期')],
      shapes: <PageShapeItem>[],
      images: <DocumentImageItem>[],
    );

    DocumentObjectSnapshotService.restore(target, snapshot);

    expect(target.layers.map((layer) => layer.id), <String>['base', 'top']);
    expect(target.shapes.single.id, 'shape');
    expect(target.imageItems.single.id, 'image');
    target.shapes.single.x = 77;
    target.imageItems.single.y = 66;
    expect(snapshot.shapes.single.x, 10);
    expect(snapshot.images.single.y, 60);
  });

  test('内容比较与当前图层索引修正遵循快照恢复语义', () {
    final source = document(
      layers: <Layer>[Layer(id: 'base', name: '底层')],
      shapes: <PageShapeItem>[],
      images: <DocumentImageItem>[],
    );
    final before = DocumentObjectSnapshotService.capture(source);
    final after = DocumentObjectSnapshotService.capture(source);

    expect(DocumentObjectSnapshotService.isSame(before, after), isTrue);
    source.layers.single.name = '已修改';
    final changed = DocumentObjectSnapshotService.capture(source);
    expect(DocumentObjectSnapshotService.isSame(before, changed), isFalse);
    expect(
      DocumentObjectSnapshotService.correctedCurrentLayerIndex(
        currentLayerIndex: 3,
        restoredLayerCount: 2,
      ),
      1,
    );
    expect(
      DocumentObjectSnapshotService.correctedCurrentLayerIndex(
        currentLayerIndex: 1,
        restoredLayerCount: 2,
      ),
      isNull,
    );
  });
}
