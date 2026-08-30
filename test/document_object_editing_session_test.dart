import 'dart:ui' show Offset, Rect;

import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_object_editing_session.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DrawingDocument documentWithImages(List<DocumentImageItem> images) =>
      DrawingDocument(
        id: 'object_session',
        title: '对象编辑会话',
        infinite: true,
        imageItems: images,
      );

  test('会话独立拥有图片选择并提交可撤销的变换命令', () {
    final host = _ObjectEditingHost(
      documentWithImages([
        DocumentImageItem(
          id: 'base',
          x: 20,
          y: 30,
          width: 160,
          height: 90,
          zOrder: 1,
          filePath: '/assets/base.png',
        ),
        DocumentImageItem(
          id: 'top',
          x: 40,
          y: 40,
          width: 80,
          height: 60,
          zOrder: 2,
          filePath: '/assets/top.png',
        ),
      ]),
    );
    host.replaceStrokeSelection(
      const Selection(
        polygon: [Offset(0, 0), Offset(1, 0), Offset(1, 1)],
        selectedStrokeIndices: [0],
      ),
    );
    final session = DocumentObjectEditingSession(host);

    expect(session.selectDocumentImageAt(const Offset(60, 60))?.id, 'top');
    expect(session.selectedDocumentImageIds, {'top'});
    expect(host.strokeSelection, const Selection());

    session.moveSelectedDocumentImage(const Offset(24, -12));
    session.endDocumentImageTransform();

    expect(host.document.imageItems.last.position, const Offset(64, 28));
    expect(host.commands, hasLength(1));
    host.commands.single.undo();
    expect(host.document.imageItems.last.position, const Offset(40, 40));
    host.commands.single.redo();
    expect(host.document.imageItems.last.position, const Offset(64, 28));
    expect(host.changeNotifications, greaterThanOrEqualTo(2));
    expect(host.frameTicks, 1);
  });

  test('混合对象变换保留锁定图片且通过统一快照完整回滚', () {
    final host = _ObjectEditingHost(
      documentWithImages([
        DocumentImageItem(
          id: 'movable',
          x: 20,
          y: 20,
          width: 30,
          height: 20,
          filePath: '/assets/movable.png',
        ),
        DocumentImageItem(
          id: 'locked',
          x: 70,
          y: 20,
          width: 30,
          height: 20,
          locked: true,
          filePath: '/assets/locked.png',
        ),
      ]),
    );
    final session = DocumentObjectEditingSession(host);
    const selectionPolygon = <Offset>[
      Offset(0, 0),
      Offset(120, 0),
      Offset(120, 80),
      Offset(0, 80),
    ];

    session.selectDocumentObjectsInPolygon(
      selectionPolygon,
      selectedStrokeIndices: const [],
    );
    expect(session.selectedDocumentObjectCount, 2);
    expect(session.mixedDocumentSelectionHasLockedObjects, isTrue);

    session.moveSelectedDocumentObjects(const Offset(10, 15));
    session.endDocumentObjectsTransform();

    expect(host.document.imageItems[0].position, const Offset(30, 35));
    expect(host.document.imageItems[1].position, const Offset(70, 20));
    expect(host.commands, hasLength(1));
    host.commands.single.undo();
    expect(host.document.imageItems[0].position, const Offset(20, 20));
    expect(host.document.imageItems[1].position, const Offset(70, 20));
    host.commands.single.redo();
    expect(host.document.imageItems[0].position, const Offset(30, 35));
    expect(host.invalidatedLayerIds, isNotEmpty);
  });

  test('恢复快照由会话清理无效选择并协调缓存、索引和通知', () {
    final host = _ObjectEditingHost(
      DrawingDocument(
        id: 'restore_session',
        title: '恢复对象编辑会话',
        infinite: true,
        layers: <Layer>[
          Layer(id: 'base', name: '底层'),
          Layer(id: 'active', name: '活动层'),
        ],
        shapes: <PageShapeItem>[
          PageShapeItem(
            id: 'shape',
            shapeType: ShapeType.rect,
            x: 10,
            y: 10,
            width: 20,
            height: 20,
          ),
        ],
        imageItems: <DocumentImageItem>[
          DocumentImageItem(
            id: 'image',
            x: 40,
            y: 10,
            width: 20,
            height: 20,
            filePath: '/assets/image.png',
          ),
        ],
      ),
    );
    host._currentLayerIndex = 1;
    final session = DocumentObjectEditingSession(host);
    session.selectDocumentObjectsInPolygon(const <Offset>[
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 100),
      Offset(0, 100),
    ], selectedStrokeIndices: const <int>[]);
    final notificationsBeforeRestore = host.changeNotifications;
    final snapshot = DocumentObjectsSnapshot(
      layers: <Layer>[Layer(id: 'restored', name: '恢复层')],
      shapes: <PageShapeItem>[],
      images: <DocumentImageItem>[],
    );

    session.restoreDocumentObjectsSnapshot(snapshot);

    expect(host.currentLayerIndex, 0);
    expect(host.document.layers.single.id, 'restored');
    expect(session.selectedDocumentShapeIds, isEmpty);
    expect(session.selectedDocumentImageIds, isEmpty);
    expect(session.selectedDocumentShapeId, isNull);
    expect(session.selectedDocumentImageId, isNull);
    expect(host.cacheMapRebuilds, 1);
    expect(host.fullRebuilds, 1);
    expect(host.changeNotifications, notificationsBeforeRestore + 1);
  });

  test('图片和形状单点选择互斥，且选择集合只读', () {
    final host = _ObjectEditingHost(
      DrawingDocument(
        id: 'exclusive_selection',
        title: '互斥选择',
        infinite: true,
        shapes: <PageShapeItem>[
          PageShapeItem(
            id: 'shape',
            shapeType: ShapeType.rect,
            x: 10,
            y: 10,
            width: 20,
            height: 20,
          ),
        ],
        imageItems: <DocumentImageItem>[
          DocumentImageItem(
            id: 'image',
            x: 60,
            y: 10,
            width: 20,
            height: 20,
            filePath: '/assets/image.png',
          ),
        ],
      ),
    );
    final session = DocumentObjectEditingSession(host);

    session.selectDocumentImageAt(const Offset(65, 15));
    expect(session.selectedDocumentImageIds, {'image'});
    expect(session.selectedDocumentImageId, 'image');
    expect(session.selectedDocumentShapeIds, isEmpty);

    session.selectDocumentShapeAt(const Offset(15, 15));
    expect(session.selectedDocumentShapeIds, {'shape'});
    expect(session.selectedDocumentShapeId, 'shape');
    expect(session.selectedDocumentImageIds, isEmpty);
    expect(session.selectedDocumentImageId, isNull);
    expect(
      () => session.selectedDocumentShapeIds.add('unexpected'),
      throwsUnsupportedError,
    );
  });

  test('混合单选保留活动对象，按类型清理不影响另一类选择', () {
    final host = _ObjectEditingHost(
      DrawingDocument(
        id: 'mixed_selection',
        title: '混合选择',
        infinite: true,
        shapes: <PageShapeItem>[
          PageShapeItem(
            id: 'shape',
            shapeType: ShapeType.ellipse,
            x: 10,
            y: 10,
            width: 20,
            height: 20,
          ),
        ],
        imageItems: <DocumentImageItem>[
          DocumentImageItem(
            id: 'image',
            x: 50,
            y: 10,
            width: 20,
            height: 20,
            filePath: '/assets/image.png',
          ),
        ],
      ),
    );
    final session = DocumentObjectEditingSession(host);

    session.selectDocumentObjectsInPolygon(const <Offset>[
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 100),
      Offset(0, 100),
    ], selectedStrokeIndices: const <int>[]);
    expect(session.selectedDocumentShapeIds, {'shape'});
    expect(session.selectedDocumentImageIds, {'image'});
    expect(session.selectedDocumentShapeId, 'shape');
    expect(session.selectedDocumentImageId, 'image');

    session.clearDocumentImageSelection();
    expect(session.selectedDocumentImageIds, isEmpty);
    expect(session.selectedDocumentImageId, isNull);
    expect(session.selectedDocumentShapeIds, {'shape'});
    expect(session.selectedDocumentShapeId, 'shape');

    session.clearDocumentShapeSelection();
    expect(session.hasMixedDocumentObjectSelection, isFalse);
    expect(session.selectedDocumentObjectCount, 0);
  });

  test('形状快照恢复清理已经不存在的活动形状选择', () {
    final host = _ObjectEditingHost(
      DrawingDocument(
        id: 'shape_restore_selection',
        title: '形状恢复选择',
        infinite: true,
        shapes: <PageShapeItem>[
          PageShapeItem(
            id: 'shape',
            shapeType: ShapeType.line,
            x: 10,
            y: 10,
            width: 20,
            height: 20,
          ),
        ],
      ),
    );
    final session = DocumentObjectEditingSession(host);
    session.selectDocumentShapeAt(const Offset(15, 15));

    session.restoreDocumentShapesSnapshot(const <PageShapeItem>[]);

    expect(session.selectedDocumentShapeIds, isEmpty);
    expect(session.selectedDocumentShapeId, isNull);
  });
}

class _ObjectEditingHost implements DocumentObjectEditingHost {
  _ObjectEditingHost(this.document);

  @override
  final DrawingDocument document;
  int _currentLayerIndex = 0;
  Selection _strokeSelection = const Selection();
  final List<DocCommand> commands = <DocCommand>[];
  final List<String> invalidatedLayerIds = <String>[];
  int changeNotifications = 0;
  int frameTicks = 0;
  int cacheMapRebuilds = 0;
  int fullRebuilds = 0;

  @override
  Layer get currentLayer => document.layers[_currentLayerIndex];

  @override
  int get currentLayerIndex => _currentLayerIndex;

  @override
  Selection get strokeSelection => _strokeSelection;

  @override
  void clearStrokeSelection() => _strokeSelection = const Selection();

  @override
  Future<void> invalidateLayer(String layerId, {Rect? region}) async {
    invalidatedLayerIds.add(layerId);
  }

  @override
  void notifyChanged() => changeNotifications++;

  @override
  void pushCommand(DocCommand command) => commands.add(command);

  @override
  void rebuildCacheMap() => cacheMapRebuilds++;

  @override
  Future<void> rebuildAll() async {
    fullRebuilds++;
  }

  @override
  void replaceStrokeSelection(Selection value) => _strokeSelection = value;

  @override
  void setCurrentLayerIndexForRestore(int value) => _currentLayerIndex = value;

  @override
  void tickFrame() => frameTicks++;
}
