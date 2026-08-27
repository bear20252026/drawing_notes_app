part of 'drawing_controller.dart';

/// 文档对象编辑 API 的兼容委托层。
///
/// 图片、形状和混合对象的选择、变换、锁定、删除及快照恢复都由
/// [DocumentObjectEditingSession] 持有。控制器保留此层，以维持既有 UI、
/// 命令回调和测试的稳定公开 API，同时避免对象会话反向依赖控制器实现。
extension DrawingControllerObjectOps on DrawingController {
  Future<void> _ensureDocumentImagesLoaded() =>
      _documentImageCache.ensureLoaded(_document.imageItems);

  Set<String> get selectedDocumentShapeIds =>
      _documentObjectEditingSession.selectedDocumentShapeIds;
  Set<String> get selectedDocumentImageIds =>
      _documentObjectEditingSession.selectedDocumentImageIds;

  String? get selectedDocumentImageId =>
      _documentObjectEditingSession.selectedDocumentImageId;
  DocumentImageItem? get selectedDocumentImage =>
      _documentObjectEditingSession.selectedDocumentImage;
  bool get hasSelectedDocumentImage =>
      _documentObjectEditingSession.hasSelectedDocumentImage;

  DocumentImageItem? selectDocumentImageAt(Offset canvasPoint) =>
      _documentObjectEditingSession.selectDocumentImageAt(canvasPoint);
  void clearDocumentImageSelection() =>
      _documentObjectEditingSession.clearDocumentImageSelection();
  void moveSelectedDocumentImage(Offset delta) =>
      _documentObjectEditingSession.moveSelectedDocumentImage(delta);
  void scaleSelectedDocumentImage(double factor) =>
      _documentObjectEditingSession.scaleSelectedDocumentImage(factor);
  void endDocumentImageTransform() =>
      _documentObjectEditingSession.endDocumentImageTransform();
  void cancelDocumentImageTransform() =>
      _documentObjectEditingSession.cancelDocumentImageTransform();
  void toggleSelectedDocumentImageLock() =>
      _documentObjectEditingSession.toggleSelectedDocumentImageLock();
  void deleteSelectedDocumentImage() =>
      _documentObjectEditingSession.deleteSelectedDocumentImage();
  void restoreDocumentImageState(String imageId, DocumentImageItem? snapshot) =>
      _documentObjectEditingSession.restoreDocumentImageState(
        imageId,
        snapshot,
      );

  String? get selectedDocumentShapeId =>
      _documentObjectEditingSession.selectedDocumentShapeId;
  PageShapeItem? get selectedDocumentShape =>
      _documentObjectEditingSession.selectedDocumentShape;
  bool get hasSelectedDocumentShape =>
      _documentObjectEditingSession.hasSelectedDocumentShape;

  PageShapeItem? selectDocumentShapeAt(Offset canvasPoint) =>
      _documentObjectEditingSession.selectDocumentShapeAt(canvasPoint);
  void clearDocumentShapeSelection() =>
      _documentObjectEditingSession.clearDocumentShapeSelection();
  void moveSelectedDocumentShape(Offset delta) =>
      _documentObjectEditingSession.moveSelectedDocumentShape(delta);
  void scaleSelectedDocumentShape(double factor) =>
      _documentObjectEditingSession.scaleSelectedDocumentShape(factor);
  void endDocumentShapeTransform() =>
      _documentObjectEditingSession.endDocumentShapeTransform();
  void cancelDocumentShapeTransform() =>
      _documentObjectEditingSession.cancelDocumentShapeTransform();
  void toggleSelectedDocumentShapeLock() =>
      _documentObjectEditingSession.toggleSelectedDocumentShapeLock();
  void deleteSelectedDocumentShape() =>
      _documentObjectEditingSession.deleteSelectedDocumentShape();
  void restoreDocumentShapesSnapshot(List<PageShapeItem> snapshot) =>
      _documentObjectEditingSession.restoreDocumentShapesSnapshot(snapshot);

  bool get hasMixedDocumentObjectSelection =>
      _documentObjectEditingSession.hasMixedDocumentObjectSelection;
  int get selectedDocumentObjectCount =>
      _documentObjectEditingSession.selectedDocumentObjectCount;
  bool get mixedDocumentSelectionHasLockedObjects =>
      _documentObjectEditingSession.mixedDocumentSelectionHasLockedObjects;

  void selectDocumentObjectsInPolygon(List<Offset> polygon) =>
      _documentObjectEditingSession.selectDocumentObjectsInPolygon(
        polygon,
        selectedStrokeIndices: _strokeSelectionInteractionSession
            .hitTestStrokes(polygon),
      );
  void clearDocumentObjectSelection() =>
      _documentObjectEditingSession.clearDocumentObjectSelection();
  Rect? get selectedDocumentObjectsBounds =>
      _documentObjectEditingSession.selectedDocumentObjectsBounds;
  void moveSelectedDocumentObjects(Offset delta) =>
      _documentObjectEditingSession.moveSelectedDocumentObjects(delta);
  void scaleSelectedDocumentObjects(double factor) =>
      _documentObjectEditingSession.scaleSelectedDocumentObjects(factor);
  void endDocumentObjectsTransform() =>
      _documentObjectEditingSession.endDocumentObjectsTransform();
  void cancelDocumentObjectsTransform() =>
      _documentObjectEditingSession.cancelDocumentObjectsTransform();
  void toggleSelectedDocumentObjectsLock() =>
      _documentObjectEditingSession.toggleSelectedDocumentObjectsLock();
  void deleteSelectedDocumentObjects() =>
      _documentObjectEditingSession.deleteSelectedDocumentObjects();
  void restoreDocumentObjectsSnapshot(DocumentObjectsSnapshot snapshot) =>
      _documentObjectEditingSession.restoreDocumentObjectsSnapshot(snapshot);
}
