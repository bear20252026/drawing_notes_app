import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:drawing_notes_app/core/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_object_transform_service.dart';
import 'package:drawing_notes_app/features/drawing/application/image_transform_service.dart';
import 'package:drawing_notes_app/features/drawing/application/selection_geometry_service.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 文档对象编辑会话与宿主控制器之间的最小协作边界。
///
/// 会话拥有图片、形状和混合对象的选择及变换中间状态；宿主保留笔画
/// 选区、历史、图层渲染缓存和 UI 通知的实际实现。此接口避免会话反向
/// 依赖 `DrawingController`，并使对象编辑逻辑可以脱离 UI 控制器测试。
abstract interface class DocumentObjectEditingHost {
  DrawingDocument get document;
  Layer get currentLayer;
  int get currentLayerIndex;
  void setCurrentLayerIndexForRestore(int value);

  Selection get strokeSelection;
  void replaceStrokeSelection(Selection value);
  void clearStrokeSelection();

  void pushCommand(DocCommand command);
  Future<void> invalidateLayer(String layerId, {Rect? region});
  void rebuildCacheMap();
  Future<void> rebuildAll();
  void notifyChanged();
  void tickFrame();
}

/// 文档图片、形状和混合对象的选择与变换运行时会话。
///
/// 会话直接修改 [DocumentObjectEditingHost.document] 中的持久对象，再通过
/// 宿主提交可逆命令、请求缓存刷新与派发通知；它不拥有绘图工具、笔画手势、
/// 历史游标或渲染资源生命周期。
class DocumentObjectEditingSession {
  DocumentObjectEditingSession(this._host);

  final DocumentObjectEditingHost _host;
  final Set<String> _selectedDocumentShapeIds = <String>{};
  final Set<String> _selectedDocumentImageIds = <String>{};
  String? _selectedDocumentImageId;
  DocumentImageItem? _documentImageTransformBefore;
  String? _selectedDocumentShapeId;
  List<PageShapeItem>? _documentShapesTransformBefore;
  DocumentObjectsSnapshot? _documentObjectsTransformBefore;

  DrawingDocument get _document => _host.document;

  Set<String> get selectedDocumentShapeIds =>
      Set<String>.unmodifiable(_selectedDocumentShapeIds);
  Set<String> get selectedDocumentImageIds =>
      Set<String>.unmodifiable(_selectedDocumentImageIds);

  /// 独立画布当前选中的图片。图片选择与笔画套索分离，避免文档图片被错误
  String? get selectedDocumentImageId => _selectedDocumentImageId;
  DocumentImageItem? get selectedDocumentImage {
    final id = _selectedDocumentImageId;
    if (id == null) return null;
    for (final item in _document.imageItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool get hasSelectedDocumentImage => selectedDocumentImage != null;

  /// 在画布坐标中选取最上层图片；命中测试使用已持久化的目标矩形，而非解码位图，
  /// 因而图片仍在异步加载时也可以移动、缩放或删除。
  DocumentImageItem? selectDocumentImageAt(Offset canvasPoint) {
    final images = List<DocumentImageItem>.of(_document.imageItems)
      ..sort((a, b) => b.zOrder.compareTo(a.zOrder));
    final hit = images
        .where((item) => item.bounds.contains(canvasPoint))
        .firstOrNull;
    _host.clearStrokeSelection();
    _selectedDocumentImageIds
      ..clear()
      ..addAll(hit == null ? const <String>[] : <String>[hit.id]);
    _selectedDocumentShapeIds.clear();
    _selectedDocumentImageId = hit?.id;
    _selectedDocumentShapeId = null;
    _host.notifyChanged();
    return hit;
  }

  void clearDocumentImageSelection() {
    if (_selectedDocumentImageId == null && _selectedDocumentImageIds.isEmpty) {
      return;
    }
    _selectedDocumentImageId = null;
    _selectedDocumentImageIds.clear();
    _host.notifyChanged();
  }

  void _ensureDocumentImageTransformBefore() {
    _documentImageTransformBefore ??= selectedDocumentImage?.copy();
  }

  /// 平移当前图片。连续 move 只请求画布重绘；结束时再形成一条历史命令。
  void moveSelectedDocumentImage(Offset delta) {
    final image = selectedDocumentImage;
    if (image == null || image.locked || delta.distance <= 0.001) return;
    _ensureDocumentImageTransformBefore();
    image
      ..x += delta.dx
      ..y += delta.dy;
    _document.touch();
    _host.tickFrame();
  }

  /// 围绕图片自身中心缩放，保留长宽比例并限制最小可操作尺寸。
  void scaleSelectedDocumentImage(double factor) {
    final image = selectedDocumentImage;
    if (image == null || image.locked || !factor.isFinite || factor <= 0) {
      return;
    }
    _ensureDocumentImageTransformBefore();
    // Q-1 拆分（2026-08-16）：缩放纯计算委托 ImageTransformService。
    final result = ImageTransformService.clampedScale(
      x: image.x,
      y: image.y,
      width: image.width,
      height: image.height,
      factor: factor,
    );
    image
      ..x = result.x
      ..y = result.y
      ..width = result.width
      ..height = result.height;
    _document.touch();
    _host.tickFrame();
  }

  /// 结算一次图片拖动/缩放，恰好加入一条撤销记录。
  void endDocumentImageTransform() {
    final before = _documentImageTransformBefore;
    final image = selectedDocumentImage;
    _documentImageTransformBefore = null;
    if (before == null ||
        image == null ||
        _sameDocumentImageState(before, image)) {
      return;
    }
    _host.pushCommand(
      DocumentImageStateCommand(
        restoreImageState: restoreDocumentImageState,
        imageId: image.id,
        before: before,
        after: image,
      ),
    );
    _host.notifyChanged();
  }

  void cancelDocumentImageTransform() {
    final before = _documentImageTransformBefore;
    _documentImageTransformBefore = null;
    if (before != null) restoreDocumentImageState(before.id, before);
  }

  /// 切换当前图片锁定状态。锁定是持久对象属性，不是短暂 UI 状态，因此会
  /// 保存、重开并参与撤销重做；它用于保护 PDF 页面、参考图和已排版资料。
  void toggleSelectedDocumentImageLock() {
    final image = selectedDocumentImage;
    if (image == null) return;
    final before = image.copy();
    image.locked = !image.locked;
    _document.touch();
    _host.pushCommand(
      DocumentImageStateCommand(
        restoreImageState: restoreDocumentImageState,
        imageId: image.id,
        before: before,
        after: image,
      ),
    );
    _host.notifyChanged();
  }

  /// 删除当前图片并以专用命令记录，资源文件仍留在文档资产目录中以支持撤销；
  /// 未来可由存储层在确认永久删除且不再被任何对象引用时统一回收。
  void deleteSelectedDocumentImage() {
    final image = selectedDocumentImage;
    if (image == null || image.locked) return;
    final before = image.copy();
    _document.imageItems.remove(image);
    _selectedDocumentImageId = null;
    _document.touch();
    _host.pushCommand(
      DocumentImageStateCommand(
        restoreImageState: restoreDocumentImageState,
        imageId: image.id,
        before: before,
        after: null,
      ),
    );
    _host.notifyChanged();
  }

  /// 供 [DocumentImageStateCommand] 以快照重建、覆盖或移除图片状态。
  void restoreDocumentImageState(String imageId, DocumentImageItem? snapshot) {
    final index = _document.imageItems.indexWhere((item) => item.id == imageId);
    if (snapshot == null) {
      if (index >= 0) _document.imageItems.removeAt(index);
      if (_selectedDocumentImageId == imageId) _selectedDocumentImageId = null;
    } else if (index >= 0) {
      _document.imageItems[index].restoreFrom(snapshot);
    } else {
      _document.imageItems.add(snapshot.copy());
    }
    _document.touch();
    _host.notifyChanged();
  }

  static bool _sameDocumentImageState(
    DocumentImageItem a,
    DocumentImageItem b,
  ) =>
      a.x == b.x &&
      a.y == b.y &&
      a.width == b.width &&
      a.height == b.height &&
      a.zOrder == b.zOrder &&
      a.filePath == b.filePath &&
      a.locked == b.locked;

  /// 独立画布当前选中的形状。形状选择与图片/笔画选择分离，避免对象 ID
  String? get selectedDocumentShapeId => _selectedDocumentShapeId;
  PageShapeItem? get selectedDocumentShape {
    final id = _selectedDocumentShapeId;
    if (id == null) return null;
    for (final shape in _document.shapes) {
      if (shape.id == id) return shape;
    }
    return null;
  }

  bool get hasSelectedDocumentShape => selectedDocumentShape != null;

  /// 命中最上层形状。使用原始 bounds 而非绘制后的抖动轮廓，避免 rough 模式
  /// 造成不可预测的选择热区；绑定箭头同样可选择以供锁定或删除。
  PageShapeItem? selectDocumentShapeAt(Offset canvasPoint) {
    final shapes = List<PageShapeItem>.of(_document.shapes)
      ..sort((a, b) => b.zOrder.compareTo(a.zOrder));
    PageShapeItem? hit;
    for (final shape in shapes) {
      if (ShapeBindingGeometry.rawBounds(shape).contains(canvasPoint)) {
        hit = shape;
        break;
      }
    }
    _host.clearStrokeSelection();
    _selectedDocumentShapeIds
      ..clear()
      ..addAll(hit == null ? const <String>[] : <String>[hit.id]);
    _selectedDocumentImageIds.clear();
    _selectedDocumentShapeId = hit?.id;
    _selectedDocumentImageId = null;
    _host.notifyChanged();
    return hit;
  }

  void clearDocumentShapeSelection() {
    if (_selectedDocumentShapeId == null && _selectedDocumentShapeIds.isEmpty) {
      return;
    }
    _selectedDocumentShapeId = null;
    _selectedDocumentShapeIds.clear();
    _host.notifyChanged();
  }

  List<PageShapeItem> _documentShapeSnapshot() =>
      _document.shapes.map((shape) => shape.copy()).toList(growable: false);

  void _ensureDocumentShapesTransformBefore() {
    _documentShapesTransformBefore ??= _documentShapeSnapshot();
  }

  /// 平移当前形状；任何引用它的绑定箭头在同一帧按锚点重新投影。
  void moveSelectedDocumentShape(Offset delta) {
    final shape = selectedDocumentShape;
    if (shape == null || shape.locked || delta.distance <= 0.001) return;
    _ensureDocumentShapesTransformBefore();
    shape
      ..x += delta.dx
      ..y += delta.dy;
    _reprojectBoundArrows();
    _document.touch();
    _host.tickFrame();
  }

  /// 围绕形状自身中心等比缩放，防止节点缩放时破坏其视觉比例；绑定箭头
  /// 由锚点比例同步重投影。
  void scaleSelectedDocumentShape(double factor) {
    final shape = selectedDocumentShape;
    if (shape == null || shape.locked || !factor.isFinite || factor <= 0) {
      return;
    }
    _ensureDocumentShapesTransformBefore();
    // Q-1 拆分（2026-08-16）：形状缩放纯计算委托 ImageTransformService。
    final result = ImageTransformService.clampedShapeScale(
      center: ShapeBindingGeometry.rawBounds(shape).center,
      width: shape.width,
      height: shape.height,
      factor: factor,
    );
    shape
      ..x = result.x
      ..y = result.y
      ..width = result.width
      ..height = result.height;
    _reprojectBoundArrows();
    _document.touch();
    _host.tickFrame();
  }

  /// 结算一次形状拖动/缩放。受影响箭头已包含在形状集合快照中，因此只有
  /// 一条命令，撤销不会产生“节点和连接线不同步”的中间状态。
  void endDocumentShapeTransform() {
    final before = _documentShapesTransformBefore;
    _documentShapesTransformBefore = null;
    if (before == null || _sameDocumentShapes(before, _document.shapes)) {
      return;
    }
    _host.pushCommand(
      DocumentShapesSnapshotCommand(
        restoreShapesSnapshot: restoreDocumentShapesSnapshot,
        before: before,
        after: _document.shapes,
      ),
    );
    _host.notifyChanged();
  }

  void cancelDocumentShapeTransform() {
    final before = _documentShapesTransformBefore;
    _documentShapesTransformBefore = null;
    if (before != null) restoreDocumentShapesSnapshot(before);
  }

  /// 切换当前形状锁定状态，并作为单一可逆对象事务记录。
  void toggleSelectedDocumentShapeLock() {
    final shape = selectedDocumentShape;
    if (shape == null) return;
    final before = _documentShapeSnapshot();
    shape.locked = !shape.locked;
    _document.touch();
    _host.pushCommand(
      DocumentShapesSnapshotCommand(
        restoreShapesSnapshot: restoreDocumentShapesSnapshot,
        before: before,
        after: _document.shapes,
      ),
    );
    _host.notifyChanged();
  }

  /// 删除当前形状。作为绑定目标的箭头会在删除前冻结对应端点、解除该端绑定，
  /// 并保留另一端关系或自由端，从而不会遗留悬挂对象 ID。
  void deleteSelectedDocumentShape() {
    final selected = selectedDocumentShape;
    if (selected == null || selected.locked) return;
    final before = _documentShapeSnapshot();
    DocumentObjectDeletionService.detachBindingsForDeletedShapes(
      _document.shapes,
      <String>{selected.id},
    );
    _document.shapes.remove(selected);
    _selectedDocumentShapeId = null;
    _document.touch();
    _host.pushCommand(
      DocumentShapesSnapshotCommand(
        restoreShapesSnapshot: restoreDocumentShapesSnapshot,
        before: before,
        after: _document.shapes,
      ),
    );
    _host.notifyChanged();
  }

  /// 供 [DocumentShapesSnapshotCommand] 恢复整个形状关系图。
  void restoreDocumentShapesSnapshot(List<PageShapeItem> snapshot) {
    _document.shapes
      ..clear()
      ..addAll(snapshot.map((shape) => shape.copy()));
    if (selectedDocumentShape == null) {
      _selectedDocumentShapeId = null;
    }
    _document.touch();
    _host.notifyChanged();
  }

  void _reprojectBoundArrows() =>
      DocumentObjectTransformService.reprojectBoundArrows(_document.shapes);

  static bool _sameDocumentShapes(
    List<PageShapeItem> a,
    List<PageShapeItem> b,
  ) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].toJson().toString() != b[index].toJson().toString()) {
        return false;
      }
    }
    return true;
  }

  // ---------------- 独立绘图文档混合对象选择与变换 ----------------

  /// 当前独立文档中是否存在由框选/套索确定的混合对象集合。
  bool get hasMixedDocumentObjectSelection =>
      _host.strokeSelection.selectedStrokeIndices.isNotEmpty ||
      _selectedDocumentShapeIds.isNotEmpty ||
      _selectedDocumentImageIds.isNotEmpty;

  int get selectedDocumentObjectCount =>
      _host.strokeSelection.selectedStrokeIndices.length +
      _selectedDocumentShapeIds.length +
      _selectedDocumentImageIds.length;

  /// 多选中是否包含锁定的形状或图片。锁定对象保持可见选择反馈，但不会参与
  /// 移动、缩放和删除，防止资料底图或固定节点被批量误触。
  bool get mixedDocumentSelectionHasLockedObjects =>
      _document.shapes.any(
        (shape) => _selectedDocumentShapeIds.contains(shape.id) && shape.locked,
      ) ||
      _document.imageItems.any(
        (image) => _selectedDocumentImageIds.contains(image.id) && image.locked,
      );

  /// 以矩形或套索多边形命中笔画、形状和图片。对象与选区相交即被选择；对
  /// 箭头使用当前投影视图 bounds，确保绑定端点移动后命中区域与显示一致。
  void selectDocumentObjectsInPolygon(
    List<Offset> polygon, {
    required List<int> selectedStrokeIndices,
  }) {
    if (polygon.length < 3) {
      clearDocumentObjectSelection();
      return;
    }
    final selectedShapeIds = <String>{};
    for (final shape in _document.shapes) {
      final rendered = _shapeForSelection(shape);
      final bounds = Rect.fromLTWH(
        rendered.x,
        rendered.y,
        rendered.width,
        rendered.height,
      );
      if (_rectIntersectsPolygon(bounds, polygon)) {
        selectedShapeIds.add(shape.id);
      }
    }
    final selectedImageIds = <String>{};
    for (final image in _document.imageItems) {
      if (_rectIntersectsPolygon(image.bounds, polygon)) {
        selectedImageIds.add(image.id);
      }
    }
    _host.replaceStrokeSelection(
      Selection(
        polygon: List<Offset>.unmodifiable(polygon),
        selectedStrokeIndices: selectedStrokeIndices,
      ),
    );
    _selectedDocumentShapeIds
      ..clear()
      ..addAll(selectedShapeIds);
    _selectedDocumentImageIds
      ..clear()
      ..addAll(selectedImageIds);
    _selectedDocumentShapeId = selectedShapeIds.length == 1
        ? selectedShapeIds.single
        : null;
    _selectedDocumentImageId = selectedImageIds.length == 1
        ? selectedImageIds.single
        : null;
    _host.notifyChanged();
  }

  /// 清除笔画、形状和图片的统一选择状态。
  void clearDocumentObjectSelection() {
    final changed =
        _host.strokeSelection.polygon.isNotEmpty ||
        _selectedDocumentShapeIds.isNotEmpty ||
        _selectedDocumentImageIds.isNotEmpty ||
        _selectedDocumentShapeId != null ||
        _selectedDocumentImageId != null;
    _host.clearStrokeSelection();
    _selectedDocumentShapeIds.clear();
    _selectedDocumentImageIds.clear();
    _selectedDocumentShapeId = null;
    _selectedDocumentImageId = null;
    if (changed) _host.notifyChanged();
  }

  /// 统一选择集合的可见包围盒。笔画依据真实采样点计算，形状与图片依据对象
  /// bounds 计算；锁定对象也在包围盒中，保持所见即所得的选择反馈。
  Rect? get selectedDocumentObjectsBounds {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    void include(Rect rect) {
      minX = math.min(minX, rect.left);
      minY = math.min(minY, rect.top);
      maxX = math.max(maxX, rect.right);
      maxY = math.max(maxY, rect.bottom);
    }

    for (final index in _host.strokeSelection.selectedStrokeIndices) {
      if (index < 0 || index >= _host.currentLayer.strokes.length) continue;
      for (final point in _host.currentLayer.strokes[index].points) {
        minX = math.min(minX, point.x);
        minY = math.min(minY, point.y);
        maxX = math.max(maxX, point.x);
        maxY = math.max(maxY, point.y);
      }
    }
    for (final shape in _document.shapes) {
      if (_selectedDocumentShapeIds.contains(shape.id)) {
        final rendered = _shapeForSelection(shape);
        include(
          Rect.fromLTWH(
            rendered.x,
            rendered.y,
            rendered.width,
            rendered.height,
          ),
        );
      }
    }
    for (final image in _document.imageItems) {
      if (_selectedDocumentImageIds.contains(image.id)) include(image.bounds);
    }
    if (!minX.isFinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  DocumentObjectsSnapshot _documentObjectsSnapshot() => DocumentObjectsSnapshot(
    layers: _layerSnapshot(),
    shapes: _documentShapeSnapshot(),
    images: _document.imageItems,
  );

  List<Layer> _layerSnapshot() => _document.layers
      .map(
        (layer) => Layer(
          id: layer.id,
          name: layer.name,
          visible: layer.visible,
          opacity: layer.opacity,
          strokes: List<Stroke>.of(layer.strokes),
        ),
      )
      .toList(growable: false);

  PageShapeItem _shapeForSelection(PageShapeItem shape) {
    if (shape.shapeType != ShapeType.arrow ||
        (shape.startBinding == null && shape.endBinding == null)) {
      return shape;
    }
    final rendered = shape.copy();
    final endpoints = ShapeBindingGeometry.resolvedArrowEndpoints(
      shape,
      _document.shapes,
    );
    ShapeBindingGeometry.applyArrowEndpoints(
      rendered,
      start: endpoints.start,
      end: endpoints.end,
    );
    return rendered;
  }

  void _ensureDocumentObjectsTransformBefore() {
    _documentObjectsTransformBefore ??= _documentObjectsSnapshot();
  }

  bool get _hasTransformableMixedDocumentObject =>
      DocumentObjectTransformService.hasTransformableSelection(
        selectedStrokeIndices: _host.strokeSelection.selectedStrokeIndices,
        shapes: _document.shapes,
        selectedShapeIds: _selectedDocumentShapeIds,
        images: _document.imageItems,
        selectedImageIds: _selectedDocumentImageIds,
      );

  /// 平移统一选择集合。绑定箭头在目标节点变化后统一重投影，选中的自由箭头端
  /// 则随组变换；整个手势只在结束时创建一条历史命令。
  void moveSelectedDocumentObjects(Offset delta) {
    if (delta.distance <= 0.001 || !_hasTransformableMixedDocumentObject) {
      return;
    }
    _ensureDocumentObjectsTransformBefore();
    _transformSelectedDocumentObjects((point) => point + delta, scale: null);
  }

  /// 围绕统一包围盒中心等比缩放选择集合。锁定对象不变，但仍保留在选择框内。
  void scaleSelectedDocumentObjects(double factor) {
    final bounds = selectedDocumentObjectsBounds;
    if (bounds == null ||
        !_hasTransformableMixedDocumentObject ||
        !factor.isFinite ||
        factor <= 0) {
      return;
    }
    final center = bounds.center;
    _ensureDocumentObjectsTransformBefore();
    _transformSelectedDocumentObjects(
      (point) => center + (point - center) * factor,
      scale: factor,
    );
  }

  void _transformSelectedDocumentObjects(
    Offset Function(Offset point) transform, {
    required double? scale,
  }) {
    DocumentObjectTransformService.transformSelection(
      strokes: _host.currentLayer.strokes,
      selectedStrokeIndices: _host.strokeSelection.selectedStrokeIndices,
      shapes: _document.shapes,
      selectedShapeIds: _selectedDocumentShapeIds,
      images: _document.imageItems,
      selectedImageIds: _selectedDocumentImageIds,
      transform: transform,
      scale: scale,
    );
    _document.touch();
    _host.invalidateLayer(_host.currentLayer.id);
    _host.tickFrame();
  }

  /// 结算混合对象手势。图层、形状（含关系图）和图片只形成一条撤销记录。
  void endDocumentObjectsTransform() {
    final before = _documentObjectsTransformBefore;
    _documentObjectsTransformBefore = null;
    if (before == null) return;
    final after = _documentObjectsSnapshot();
    if (_sameDocumentObjectsSnapshot(before, after)) return;
    _host.pushCommand(
      DocumentObjectsSnapshotCommand(
        restoreObjectsSnapshot: restoreDocumentObjectsSnapshot,
        before: before,
        after: after,
      ),
    );
    _host.notifyChanged();
  }

  /// 取消拖动或缩放，严格还原本次手势起始状态且不写入历史。
  void cancelDocumentObjectsTransform() {
    final before = _documentObjectsTransformBefore;
    _documentObjectsTransformBefore = null;
    if (before != null) restoreDocumentObjectsSnapshot(before);
  }

  /// 批量切换已选形状和图片的锁定状态。只要集合中存在未锁对象，就统一锁定；
  /// 全部已锁时统一解锁。笔画没有锁定字段，不受此操作影响。
  void toggleSelectedDocumentObjectsLock() {
    final selectedShapes = _document.shapes
        .where((shape) => _selectedDocumentShapeIds.contains(shape.id))
        .toList(growable: false);
    final selectedImages = _document.imageItems
        .where((image) => _selectedDocumentImageIds.contains(image.id))
        .toList(growable: false);
    if (selectedShapes.isEmpty && selectedImages.isEmpty) return;
    final before = _documentObjectsSnapshot();
    final shouldLock =
        selectedShapes.any((shape) => !shape.locked) ||
        selectedImages.any((image) => !image.locked);
    for (final shape in selectedShapes) {
      shape.locked = shouldLock;
    }
    for (final image in selectedImages) {
      image.locked = shouldLock;
    }
    _document.touch();
    _host.pushCommand(
      DocumentObjectsSnapshotCommand(
        restoreObjectsSnapshot: restoreDocumentObjectsSnapshot,
        before: before,
        after: _documentObjectsSnapshot(),
      ),
    );
    _host.notifyChanged();
  }

  /// 批量删除当前选择。锁定形状/图片保留；作为被删形状目标的箭头端点先冻结
  /// 为当前绝对位置并解绑，因而不会留下悬挂 ID 或改变另一端可见几何。
  void deleteSelectedDocumentObjects() {
    if (!hasMixedDocumentObjectSelection) return;
    final before = _documentObjectsSnapshot();
    final deleted = DocumentObjectDeletionService.deleteSelection(
      strokes: _host.currentLayer.strokes,
      selectedStrokeIndices: _host.strokeSelection.selectedStrokeIndices,
      shapes: _document.shapes,
      selectedShapeIds: _selectedDocumentShapeIds,
      images: _document.imageItems,
      selectedImageIds: _selectedDocumentImageIds,
    );
    if (!deleted) return;
    clearDocumentObjectSelection();
    _document.touch();
    _host.invalidateLayer(_host.currentLayer.id);
    _host.pushCommand(
      DocumentObjectsSnapshotCommand(
        restoreObjectsSnapshot: restoreDocumentObjectsSnapshot,
        before: before,
        after: _documentObjectsSnapshot(),
      ),
    );
    _host.notifyChanged();
  }

  /// 供 [DocumentObjectsSnapshotCommand] 恢复混合文档状态。此入口在恢复后统一
  /// 重建笔画缓存、修正选择 ID，并在单次通知中让关系图与图片同步刷新。
  void restoreDocumentObjectsSnapshot(DocumentObjectsSnapshot snapshot) {
    _document.layers
      ..clear()
      ..addAll(
        snapshot.layers.map(
          (layer) => Layer(
            id: layer.id,
            name: layer.name,
            visible: layer.visible,
            opacity: layer.opacity,
            strokes: List.of(layer.strokes),
          ),
        ),
      );
    _document.shapes
      ..clear()
      ..addAll(snapshot.shapes.map((shape) => shape.copy()));
    _document.imageItems
      ..clear()
      ..addAll(snapshot.images.map((image) => image.copy()));
    if (_host.currentLayerIndex >= _document.layers.length) {
      _host.setCurrentLayerIndexForRestore(_document.layers.length - 1);
    }
    _selectedDocumentShapeIds.removeWhere(
      (id) => !_document.shapes.any((shape) => shape.id == id),
    );
    _selectedDocumentImageIds.removeWhere(
      (id) => !_document.imageItems.any((image) => image.id == id),
    );
    if (_selectedDocumentShapeId != null &&
        !_selectedDocumentShapeIds.contains(_selectedDocumentShapeId)) {
      _selectedDocumentShapeId = null;
    }
    if (_selectedDocumentImageId != null &&
        !_selectedDocumentImageIds.contains(_selectedDocumentImageId)) {
      _selectedDocumentImageId = null;
    }
    _document.touch();
    _host.rebuildCacheMap();
    _host.notifyChanged();
    _host.rebuildAll();
  }

  static bool _sameDocumentObjectsSnapshot(
    DocumentObjectsSnapshot a,
    DocumentObjectsSnapshot b,
  ) {
    if (a.layers.length != b.layers.length ||
        a.shapes.length != b.shapes.length ||
        a.images.length != b.images.length) {
      return false;
    }
    for (var index = 0; index < a.layers.length; index++) {
      if (a.layers[index].toJson().toString() !=
          b.layers[index].toJson().toString()) {
        return false;
      }
    }
    for (var index = 0; index < a.shapes.length; index++) {
      if (a.shapes[index].toJson().toString() !=
          b.shapes[index].toJson().toString()) {
        return false;
      }
    }
    for (var index = 0; index < a.images.length; index++) {
      if (a.images[index].toJson().toString() !=
          b.images[index].toJson().toString()) {
        return false;
      }
    }
    return true;
  }

  static bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (
      var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++
    ) {
      final currentPoint = polygon[index];
      final previousPoint = polygon[previous];
      final crossesRay =
          (currentPoint.dy > point.dy) != (previousPoint.dy > point.dy) &&
          point.dx <
              (previousPoint.dx - currentPoint.dx) *
                      (point.dy - currentPoint.dy) /
                      (previousPoint.dy - currentPoint.dy) +
                  currentPoint.dx;
      if (crossesRay) inside = !inside;
    }
    return inside;
  }

  bool _rectIntersectsPolygon(Rect rect, List<Offset> polygon) {
    final corners = <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    if (corners.any((corner) => _pointInPolygon(corner, polygon))) return true;
    if (polygon.any(rect.contains)) return true;
    for (var edge = 0; edge < polygon.length; edge++) {
      final a = polygon[edge];
      final b = polygon[(edge + 1) % polygon.length];
      for (var side = 0; side < corners.length; side++) {
        if (SelectionGeometryService.segmentsIntersect(
          a,
          b,
          corners[side],
          corners[(side + 1) % 4],
        )) {
          return true;
        }
      }
    }
    return false;
  }
}
