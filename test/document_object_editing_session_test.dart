import 'dart:ui' show Offset, Rect;

import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_object_editing_session.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
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
