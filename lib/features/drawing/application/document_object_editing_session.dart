import 'dart:ui' show Offset, Rect;

import 'package:drawing_notes_app/features/drawing/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_object_transform_service.dart';
import 'package:drawing_notes_app/features/drawing/application/image_transform_service.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';

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
  final _DocumentObjectSelectionState _selection =
      _DocumentObjectSelectionState();
  DocumentImageItem? _documentImageTransformBefore;
  List<PageShapeItem>? _documentShapesTransformBefore;
  DocumentObjectsSnapshot? _documentObjectsTransformBefore;

  DrawingDocument get _document => _host.document;

  Set<String> get selectedDocumentShapeIds => _selection.shapeIds;
  Set<String> get selectedDocumentImageIds => _selection.imageIds;

  /// 独立画布当前选中的图片。图片选择与笔画套索分离，避免文档图片被错误
  String? get selectedDocumentImageId => _selection.activeImageId;
  DocumentImageItem? get selectedDocumentImage {
    final id = _selection.activeImageId;
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
    _selection.selectImage(hit?.id);
    _host.notifyChanged();
    return hit;
  }

  void clearDocumentImageSelection() {
    if (!_selection.clearImages()) return;
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
    _selection.removeImage(image.id);
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
      _selection.removeImage(imageId);
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
  String? get selectedDocumentShapeId => _selection.activeShapeId;
  PageShapeItem? get selectedDocumentShape {
    final id = _selection.activeShapeId;
    if (id == null) return null;
    for (final shape in _document.shapes) {
      if (shape.id == id) return shape;
    }
    return null;
  }

  bool get hasSelectedDocumentShape => selectedDocumentShape != null;

  /// 命中最上层形状。封闭形状使用原始 bounds（避免 rough 模式抖动轮廓造成
  /// 不可预测的选择热区）；线性元素（直线/箭头）改用点到线段距离判定
  /// （≤ 线宽/2 + 6px，审计二-5：细斜线的外接框大片空白不再误选，
  /// 也不再挡住其后的元素）。绑定箭头使用已投影端点，命中区域与显示一致。
  PageShapeItem? selectDocumentShapeAt(Offset canvasPoint) {
    final shapes = List<PageShapeItem>.of(_document.shapes)
      ..sort((a, b) => b.zOrder.compareTo(a.zOrder));
    PageShapeItem? hit;
    for (final shape in shapes) {
      if (shapeHitTest(shape, canvasPoint, _document.shapes)) {
        hit = shape;
        break;
      }
    }
    _host.clearStrokeSelection();
    _selection.selectShape(hit?.id);
    _host.notifyChanged();
    return hit;
  }

  /// 单形状命中测试：封闭形状 → 外接框包含；线性元素 → 点到线段距离。
  static bool shapeHitTest(
    PageShapeItem shape,
    Offset canvasPoint,
    Iterable<PageShapeItem> allShapes,
  ) {
    if (!ShapeBindingGeometry.isLinear(shape)) {
      return ShapeBindingGeometry.rawBounds(shape).contains(canvasPoint);
    }
    final endpoints = shape.shapeType == ShapeType.arrow
        ? ShapeBindingGeometry.resolvedArrowEndpoints(shape, allShapes)
        : ShapeBindingGeometry.linearEndpoints(shape);
    return ShapeBindingGeometry.distanceToSegment(
          canvasPoint,
          endpoints.start,
          endpoints.end,
        ) <=
        shape.strokeWidth / 2 + ShapeBindingGeometry.linearHitSlack;
  }

  void clearDocumentShapeSelection() {
    if (!_selection.clearShapes()) return;
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

  // ---------------- 线性元素端点编辑（审计二-2/二-3，2026-09-06） ----------------

  /// 开始一次线性端点编辑手势：快照形状集合，结束时只产生一条撤销记录。
  void beginLinearEndpointEdit() => _ensureDocumentShapesTransformBefore();

  /// 把选中线性元素（直线/箭头）的 [isStart] 端移动到画布坐标 [point]。
  ///
  /// 吸附规则（与创建时刻一致）：箭头端点落在可绑定形状 8px 邻域内时吸附
  /// 到其外接框周界并（重）建立该端绑定；否则对另一端为锚做 0°/45°/90°
  /// 角度磁吸；[snapToGrid] 时改按 20px 网格吸附。自由端拖离目标即解绑。
  void updateSelectedLinearEndpoint({
    required bool isStart,
    required Offset point,
    bool snapToGrid = false,
  }) {
    final shape = selectedDocumentShape;
    if (shape == null ||
        shape.locked ||
        !ShapeBindingGeometry.isLinear(shape)) {
      return;
    }
    _ensureDocumentShapesTransformBefore();
    final isArrow = shape.shapeType == ShapeType.arrow;
    final endpoints = isArrow
        ? ShapeBindingGeometry.resolvedArrowEndpoints(shape, _document.shapes)
        : ShapeBindingGeometry.linearEndpoints(shape);
    final anchor = isStart ? endpoints.end : endpoints.start;
    var target = point;
    PageShapeItem? bound;
    if (snapToGrid) {
      target = ShapeBindingGeometry.snapToGrid(
        target,
        ShapeBindingGeometry.gridSnapStep,
      );
    } else if (isArrow) {
      bound = ShapeBindingGeometry.bindableShapeNear(
        target,
        _document.shapes,
        excludingId: shape.id,
      );
      if (bound != null) {
        target = ShapeBindingGeometry.projectPointToBounds(
          target,
          ShapeBindingGeometry.rawBounds(bound),
        );
      }
    }
    if (bound == null && !snapToGrid) {
      target = ShapeBindingGeometry.snapDragAngle(anchor, target);
    }
    if (isArrow) {
      final binding = bound == null
          ? null
          : ShapeBindingGeometry.bindingAt(bound, target);
      if (isStart) {
        shape.startBinding = binding;
      } else {
        shape.endBinding = binding;
      }
    }
    ShapeBindingGeometry.applyLinearEndpoints(
      shape,
      start: isStart ? target : anchor,
      end: isStart ? anchor : target,
    );
    _document.touch();
    _host.tickFrame();
  }

  /// 结算线性端点编辑手势（一条历史命令，含关系图整体状态）。
  void endLinearEndpointEdit() => endDocumentShapeTransform();

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
    _selection.removeShape(selected.id);
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
    _selection.retainExisting(
      shapeIds: _document.shapes.map((shape) => shape.id),
      imageIds: _document.imageItems.map((image) => image.id),
    );
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
      _selection.hasObjectSelection;

  int get selectedDocumentObjectCount =>
      _host.strokeSelection.selectedStrokeIndices.length +
      _selection.objectSelectionCount;

  /// 多选中是否包含锁定的形状或图片。锁定对象保持可见选择反馈，但不会参与
  /// 移动、缩放和删除，防止资料底图或固定节点被批量误触。
  bool get mixedDocumentSelectionHasLockedObjects =>
      _document.shapes.any(
        (shape) => _selection.containsShape(shape.id) && shape.locked,
      ) ||
      _document.imageItems.any(
        (image) => _selection.containsImage(image.id) && image.locked,
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
    final hitTest = DocumentObjectGeometryService.objectsIntersectingPolygon(
      polygon: polygon,
      shapes: _document.shapes,
      images: _document.imageItems,
    );
    _host.replaceStrokeSelection(
      Selection(
        polygon: List<Offset>.unmodifiable(polygon),
        selectedStrokeIndices: selectedStrokeIndices,
      ),
    );
    _selection.selectMixed(
      shapeIds: hitTest.shapeIds,
      imageIds: hitTest.imageIds,
    );
    _host.notifyChanged();
  }

  /// 清除笔画、形状和图片的统一选择状态。
  void clearDocumentObjectSelection() {
    final changed =
        _host.strokeSelection.polygon.isNotEmpty || _selection.hasAnySelection;
    _host.clearStrokeSelection();
    _selection.clearAll();
    if (changed) _host.notifyChanged();
  }

  /// 统一选择集合的可见包围盒。笔画依据真实采样点计算，形状与图片依据对象
  /// bounds 计算；锁定对象也在包围盒中，保持所见即所得的选择反馈。
  Rect? get selectedDocumentObjectsBounds =>
      DocumentObjectGeometryService.selectedObjectsBounds(
        strokes: _host.currentLayer.strokes,
        selectedStrokeIndices: _host.strokeSelection.selectedStrokeIndices,
        shapes: _document.shapes,
        selectedShapeIds: _selection.shapeIds,
        images: _document.imageItems,
        selectedImageIds: _selection.imageIds,
      );

  DocumentObjectsSnapshot _documentObjectsSnapshot() =>
      DocumentObjectSnapshotService.capture(_document);

  void _ensureDocumentObjectsTransformBefore() {
    _documentObjectsTransformBefore ??= _documentObjectsSnapshot();
  }

  bool get _hasTransformableMixedDocumentObject =>
      DocumentObjectTransformService.hasTransformableSelection(
        selectedStrokeIndices: _host.strokeSelection.selectedStrokeIndices,
        shapes: _document.shapes,
        selectedShapeIds: _selection.shapeIds,
        images: _document.imageItems,
        selectedImageIds: _selection.imageIds,
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
      selectedShapeIds: _selection.shapeIds,
      images: _document.imageItems,
      selectedImageIds: _selection.imageIds,
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
    if (DocumentObjectSnapshotService.isSame(before, after)) return;
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
        .where((shape) => _selection.containsShape(shape.id))
        .toList(growable: false);
    final selectedImages = _document.imageItems
        .where((image) => _selection.containsImage(image.id))
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
      selectedShapeIds: _selection.shapeIds,
      images: _document.imageItems,
      selectedImageIds: _selection.imageIds,
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
    DocumentObjectSnapshotService.restore(_document, snapshot);
    final correctedLayerIndex =
        DocumentObjectSnapshotService.correctedCurrentLayerIndex(
          currentLayerIndex: _host.currentLayerIndex,
          restoredLayerCount: _document.layers.length,
        );
    if (correctedLayerIndex != null) {
      _host.setCurrentLayerIndexForRestore(correctedLayerIndex);
    }
    _selection.retainExisting(
      shapeIds: _document.shapes.map((shape) => shape.id),
      imageIds: _document.imageItems.map((image) => image.id),
    );
    _document.touch();
    _host.rebuildCacheMap();
    _host.notifyChanged();
    _host.rebuildAll();
  }
}

/// 独立画布对象选择的会话级暂态。
///
/// 此对象只维护形状/图片的选择 id 与活动 id 之间的一致性；不持有文档、
/// 控制器、历史、缓存或通知能力。它仅由 [DocumentObjectEditingSession] 使用，
/// 不与 Riverpod 的只读可见选择状态构成第二个写入源。
class _DocumentObjectSelectionState {
  final Set<String> _shapeIds = <String>{};
  final Set<String> _imageIds = <String>{};
  String? _activeShapeId;
  String? _activeImageId;

  Set<String> get shapeIds => Set<String>.unmodifiable(_shapeIds);
  Set<String> get imageIds => Set<String>.unmodifiable(_imageIds);
  String? get activeShapeId => _activeShapeId;
  String? get activeImageId => _activeImageId;

  bool get hasObjectSelection => _shapeIds.isNotEmpty || _imageIds.isNotEmpty;
  bool get hasAnySelection =>
      hasObjectSelection || _activeShapeId != null || _activeImageId != null;
  int get objectSelectionCount => _shapeIds.length + _imageIds.length;

  bool containsShape(String id) => _shapeIds.contains(id);
  bool containsImage(String id) => _imageIds.contains(id);

  /// 设置单一图片选择，并清除形状选择及两种活动对象的互斥状态。
  void selectImage(String? imageId) {
    _imageIds
      ..clear()
      ..addAll(imageId == null ? const <String>[] : <String>[imageId]);
    _shapeIds.clear();
    _activeImageId = imageId;
    _activeShapeId = null;
  }

  /// 设置单一形状选择，并清除图片选择及两种活动对象的互斥状态。
  void selectShape(String? shapeId) {
    _shapeIds
      ..clear()
      ..addAll(shapeId == null ? const <String>[] : <String>[shapeId]);
    _imageIds.clear();
    _activeShapeId = shapeId;
    _activeImageId = null;
  }

  /// 设置多对象选择。活动 id 只在对应类型恰好选择一个对象时保留。
  void selectMixed({
    required Iterable<String> shapeIds,
    required Iterable<String> imageIds,
  }) {
    _shapeIds
      ..clear()
      ..addAll(shapeIds);
    _imageIds
      ..clear()
      ..addAll(imageIds);
    _activeShapeId = _shapeIds.length == 1 ? _shapeIds.single : null;
    _activeImageId = _imageIds.length == 1 ? _imageIds.single : null;
  }

  bool clearShapes() {
    final changed = _shapeIds.isNotEmpty || _activeShapeId != null;
    _shapeIds.clear();
    _activeShapeId = null;
    return changed;
  }

  bool clearImages() {
    final changed = _imageIds.isNotEmpty || _activeImageId != null;
    _imageIds.clear();
    _activeImageId = null;
    return changed;
  }

  bool clearAll() {
    final changed = hasAnySelection;
    _shapeIds.clear();
    _imageIds.clear();
    _activeShapeId = null;
    _activeImageId = null;
    return changed;
  }

  void removeShape(String id) {
    _shapeIds.remove(id);
    if (_activeShapeId == id) _activeShapeId = null;
  }

  void removeImage(String id) {
    _imageIds.remove(id);
    if (_activeImageId == id) _activeImageId = null;
  }

  /// 快照恢复后只保留仍属于文档的对象选择，并清除失效活动对象。
  void retainExisting({
    required Iterable<String> shapeIds,
    required Iterable<String> imageIds,
  }) {
    final existingShapeIds = shapeIds.toSet();
    final existingImageIds = imageIds.toSet();
    _shapeIds.removeWhere((id) => !existingShapeIds.contains(id));
    _imageIds.removeWhere((id) => !existingImageIds.contains(id));
    if (_activeShapeId == null || !_shapeIds.contains(_activeShapeId)) {
      _activeShapeId = null;
    }
    if (_activeImageId == null || !_imageIds.contains(_activeImageId)) {
      _activeImageId = null;
    }
  }
}
