import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Paint, FilterQuality, Rect;

import 'package:flutter/foundation.dart';

import '../models/document.dart';
import '../models/document_image_item.dart';
import '../models/layer.dart';
import '../models/selection.dart';
import '../models/shape_item.dart';
import '../models/stroke.dart';
import '../storage/local_id_generator.dart';
import 'document_commands.dart';
import 'eraser_mode.dart';
import 'ink_layer_painter.dart';
import 'layer_compositor.dart';
import 'stroke_geometry_cache.dart';
import 'shape_recognizer.dart';
import 'shape_binding_geometry.dart';
import 'shape_renderer.dart';
import 'stroke_renderer.dart';

part 'drawing_controller_temporary.dart';

/// 绘图引擎控制器：UI 层与数据模型之间的唯一桥梁。
///
/// 职责：
/// 1. 维护当前文档 [document] 与工具状态（笔刷/颜色/粗细/图层索引）；
/// 2. 提供笔画绘制入口（start/extend/endStroke）；
/// 3. 提供图层操作（新建/删除/显隐/透明度/排序/合并）与撤销重做；
/// 4. 管理各图层的离屏位图缓存 [LayerRenderCache]，供 CustomPainter 绘制；
/// 5. 负责把视图坐标转换为画布坐标（视口变换）。
///
/// 设计原则：本类不依赖任何 UI 组件，只通过 [ChangeNotifier] 通知变化，
/// 便于独立测试与后续替换存储层。
class DrawingController extends ChangeNotifier {
  DrawingController(this._document) {
    _rebuildCacheMap();
  }

  final DrawingDocument _document;
  DrawingDocument get document => _document;

  final Map<String, ui.Image> _documentImages = <String, ui.Image>{};
  final Set<String> _loadingDocumentImageIds = <String>{};

  /// 取得文档图片的已解码位图；首次访问会异步加载并在完成后刷新画布。
  ///
  /// 解码缓存只保存运行时资源，JSON 仍只持久化离线文件路径，因此关闭重开后
  /// 仍可按需恢复且不会把大图二进制写入工程文件。
  ui.Image? documentImage(DocumentImageItem item) {
    final cached = _documentImages[item.id];
    if (cached != null) return cached;
    if (_loadingDocumentImageIds.add(item.id)) {
      unawaited(_loadDocumentImage(item));
    }
    return null;
  }

  Future<void> _ensureDocumentImagesLoaded() async {
    await Future.wait([
      for (final item in _document.imageItems)
        if (!_documentImages.containsKey(item.id)) _loadDocumentImage(item),
    ]);
  }

  Future<void> _loadDocumentImage(DocumentImageItem item) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(item.filePath);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      _documentImages.remove(item.id)?.dispose();
      _documentImages[item.id] = frame.image;
      tickFrame();
    } catch (_) {
      // 图片缺失/损坏不应阻止整个工程打开；画布保持其余内容可编辑。
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
      _loadingDocumentImageIds.remove(item.id);
    }
  }

  /// 独立绘图文档的统一对象选择。笔画仍使用当前图层索引，形状与图片使用
  /// 持久 ID；三者可以同时存在于同一个框选/套索集合中。
  final Set<String> _selectedDocumentShapeIds = <String>{};
  final Set<String> _selectedDocumentImageIds = <String>{};

  Set<String> get selectedDocumentShapeIds =>
      Set<String>.unmodifiable(_selectedDocumentShapeIds);
  Set<String> get selectedDocumentImageIds =>
      Set<String>.unmodifiable(_selectedDocumentImageIds);

  /// 独立画布当前选中的图片。图片选择与笔画套索分离，避免文档图片被错误
  /// 当作笔画索引；渲染器据此绘制专属边框与缩放手柄。
  String? _selectedDocumentImageId;
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
    _selection = const Selection();
    _selectedDocumentImageIds
      ..clear()
      ..addAll(hit == null ? const <String>[] : <String>[hit.id]);
    _selectedDocumentShapeIds.clear();
    _selectedDocumentImageId = hit?.id;
    _selectedDocumentShapeId = null;
    notifyListeners();
    return hit;
  }

  void clearDocumentImageSelection() {
    if (_selectedDocumentImageId == null && _selectedDocumentImageIds.isEmpty) {
      return;
    }
    _selectedDocumentImageId = null;
    _selectedDocumentImageIds.clear();
    notifyListeners();
  }

  DocumentImageItem? _documentImageTransformBefore;

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
    tickFrame();
  }

  /// 围绕图片自身中心缩放，保留长宽比例并限制最小可操作尺寸。
  void scaleSelectedDocumentImage(double factor) {
    final image = selectedDocumentImage;
    if (image == null || image.locked || !factor.isFinite || factor <= 0) {
      return;
    }
    _ensureDocumentImageTransformBefore();
    final center = image.bounds.center;
    final nextWidth = (image.width * factor).clamp(32.0, 8192.0);
    final ratio = image.height / image.width;
    image
      ..width = nextWidth
      ..height = (nextWidth * ratio).clamp(24.0, 8192.0)
      ..x = center.dx - nextWidth / 2
      ..y = center.dy - image.height / 2;
    _document.touch();
    tickFrame();
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
    _pushCommand(
      DocumentImageStateCommand(
        this,
        imageId: image.id,
        before: before,
        after: image,
      ),
    );
    notifyListeners();
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
    _pushCommand(
      DocumentImageStateCommand(
        this,
        imageId: image.id,
        before: before,
        after: image,
      ),
    );
    notifyListeners();
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
    _pushCommand(
      DocumentImageStateCommand(
        this,
        imageId: image.id,
        before: before,
        after: null,
      ),
    );
    notifyListeners();
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
    notifyListeners();
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
  /// 在不同集合中冲突并让画布可为不同对象绘制专属选中反馈。
  String? _selectedDocumentShapeId;
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
    _selection = const Selection();
    _selectedDocumentShapeIds
      ..clear()
      ..addAll(hit == null ? const <String>[] : <String>[hit.id]);
    _selectedDocumentImageIds.clear();
    _selectedDocumentShapeId = hit?.id;
    _selectedDocumentImageId = null;
    notifyListeners();
    return hit;
  }

  void clearDocumentShapeSelection() {
    if (_selectedDocumentShapeId == null && _selectedDocumentShapeIds.isEmpty) {
      return;
    }
    _selectedDocumentShapeId = null;
    _selectedDocumentShapeIds.clear();
    notifyListeners();
  }

  List<PageShapeItem>? _documentShapesTransformBefore;

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
    tickFrame();
  }

  /// 围绕形状自身中心等比缩放，防止节点缩放时破坏其视觉比例；绑定箭头
  /// 由锚点比例同步重投影。
  void scaleSelectedDocumentShape(double factor) {
    final shape = selectedDocumentShape;
    if (shape == null || shape.locked || !factor.isFinite || factor <= 0) {
      return;
    }
    _ensureDocumentShapesTransformBefore();
    final center = ShapeBindingGeometry.rawBounds(shape).center;
    final width = (shape.width * factor).clamp(16.0, 8192.0);
    final height = (shape.height * factor).clamp(16.0, 8192.0);
    shape
      ..width = width
      ..height = height
      ..x = center.dx - width / 2
      ..y = center.dy - height / 2;
    _reprojectBoundArrows();
    _document.touch();
    tickFrame();
  }

  /// 结算一次形状拖动/缩放。受影响箭头已包含在形状集合快照中，因此只有
  /// 一条命令，撤销不会产生“节点和连接线不同步”的中间状态。
  void endDocumentShapeTransform() {
    final before = _documentShapesTransformBefore;
    _documentShapesTransformBefore = null;
    if (before == null || _sameDocumentShapes(before, _document.shapes)) {
      return;
    }
    _pushCommand(
      DocumentShapesSnapshotCommand(
        this,
        before: before,
        after: _document.shapes,
      ),
    );
    notifyListeners();
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
    _pushCommand(
      DocumentShapesSnapshotCommand(
        this,
        before: before,
        after: _document.shapes,
      ),
    );
    notifyListeners();
  }

  /// 删除当前形状。作为绑定目标的箭头会在删除前冻结对应端点、解除该端绑定，
  /// 并保留另一端关系或自由端，从而不会遗留悬挂对象 ID。
  void deleteSelectedDocumentShape() {
    final selected = selectedDocumentShape;
    if (selected == null || selected.locked) return;
    final before = _documentShapeSnapshot();
    for (final arrow in _document.shapes) {
      if (arrow.shapeType != ShapeType.arrow || arrow.id == selected.id) {
        continue;
      }
      final endpoints = ShapeBindingGeometry.resolvedArrowEndpoints(
        arrow,
        _document.shapes,
      );
      var changed = false;
      if (arrow.startBinding?.targetShapeId == selected.id) {
        arrow.startBinding = null;
        changed = true;
      }
      if (arrow.endBinding?.targetShapeId == selected.id) {
        arrow.endBinding = null;
        changed = true;
      }
      if (changed) {
        ShapeBindingGeometry.applyArrowEndpoints(
          arrow,
          start: endpoints.start,
          end: endpoints.end,
        );
      }
    }
    _document.shapes.remove(selected);
    _selectedDocumentShapeId = null;
    _document.touch();
    _pushCommand(
      DocumentShapesSnapshotCommand(
        this,
        before: before,
        after: _document.shapes,
      ),
    );
    notifyListeners();
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
    notifyListeners();
  }

  void _reprojectBoundArrows() {
    for (final arrow in _document.shapes) {
      ShapeBindingGeometry.reprojectArrow(arrow, _document.shapes);
    }
  }

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
      hasSelectedStrokes ||
      _selectedDocumentShapeIds.isNotEmpty ||
      _selectedDocumentImageIds.isNotEmpty;

  int get selectedDocumentObjectCount =>
      _selection.selectedStrokeIndices.length +
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
  void selectDocumentObjectsInPolygon(List<Offset> polygon) {
    if (polygon.length < 3) {
      clearDocumentObjectSelection();
      return;
    }
    final selectedShapeIds = <String>{};
    for (final shape in _document.shapes) {
      final rendered = shapeForRendering(shape);
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
    _selection = Selection(
      polygon: List<Offset>.unmodifiable(polygon),
      selectedStrokeIndices: _hitTestStrokes(polygon),
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
    notifyListeners();
  }

  /// 清除笔画、形状和图片的统一选择状态。
  void clearDocumentObjectSelection() {
    final changed =
        _selection.polygon.isNotEmpty ||
        _selectedDocumentShapeIds.isNotEmpty ||
        _selectedDocumentImageIds.isNotEmpty ||
        _selectedDocumentShapeId != null ||
        _selectedDocumentImageId != null;
    _selection = const Selection();
    _selectedDocumentShapeIds.clear();
    _selectedDocumentImageIds.clear();
    _selectedDocumentShapeId = null;
    _selectedDocumentImageId = null;
    if (changed) notifyListeners();
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

    for (final index in _selection.selectedStrokeIndices) {
      if (index < 0 || index >= currentLayer.strokes.length) continue;
      for (final point in currentLayer.strokes[index].points) {
        minX = math.min(minX, point.x);
        minY = math.min(minY, point.y);
        maxX = math.max(maxX, point.x);
        maxY = math.max(maxY, point.y);
      }
    }
    for (final shape in _document.shapes) {
      if (_selectedDocumentShapeIds.contains(shape.id)) {
        final rendered = shapeForRendering(shape);
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

  DocumentObjectsSnapshot? _documentObjectsTransformBefore;

  DocumentObjectsSnapshot _documentObjectsSnapshot() => DocumentObjectsSnapshot(
    layers: _snapshotLayers(),
    shapes: _documentShapeSnapshot(),
    images: _document.imageItems,
  );

  void _ensureDocumentObjectsTransformBefore() {
    _documentObjectsTransformBefore ??= _documentObjectsSnapshot();
  }

  bool get _hasTransformableMixedDocumentObject =>
      hasSelectedStrokes ||
      _document.shapes.any(
        (shape) =>
            _selectedDocumentShapeIds.contains(shape.id) && !shape.locked,
      ) ||
      _document.imageItems.any(
        (image) =>
            _selectedDocumentImageIds.contains(image.id) && !image.locked,
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
    final selectedArrowEndpoints = <String, ({Offset start, Offset end})>{};
    for (final shape in _document.shapes) {
      if (_selectedDocumentShapeIds.contains(shape.id) &&
          !shape.locked &&
          shape.shapeType == ShapeType.arrow) {
        selectedArrowEndpoints[shape.id] =
            ShapeBindingGeometry.resolvedArrowEndpoints(
              shape,
              _document.shapes,
            );
      }
    }

    for (final index in _selection.selectedStrokeIndices.reversed) {
      if (index < 0 || index >= currentLayer.strokes.length) continue;
      final old = currentLayer.strokes[index];
      currentLayer.strokes[index] = Stroke(
        points: old.points
            .map((point) {
              final next = transform(point.offset);
              return StrokePoint(next.dx, next.dy, point.pressure);
            })
            .toList(growable: false),
        color: old.color,
        width: old.width,
        type: old.type,
        opacity: old.opacity,
      );
    }

    for (final shape in _document.shapes) {
      if (!_selectedDocumentShapeIds.contains(shape.id) || shape.locked) {
        continue;
      }
      if (shape.shapeType == ShapeType.arrow) continue;
      final oldBounds = ShapeBindingGeometry.rawBounds(shape);
      final nextTopLeft = transform(oldBounds.topLeft);
      final nextScale = scale ?? 1.0;
      final nextWidth = (oldBounds.width * nextScale).clamp(16.0, 8192.0);
      final nextHeight = (oldBounds.height * nextScale).clamp(16.0, 8192.0);
      shape
        ..x = nextTopLeft.dx
        ..y = nextTopLeft.dy
        ..width = nextWidth
        ..height = nextHeight;
    }

    for (final image in _document.imageItems) {
      if (!_selectedDocumentImageIds.contains(image.id) || image.locked) {
        continue;
      }
      final nextTopLeft = transform(image.bounds.topLeft);
      final nextScale = scale ?? 1.0;
      image
        ..x = nextTopLeft.dx
        ..y = nextTopLeft.dy
        ..width = (image.width * nextScale).clamp(32.0, 8192.0)
        ..height = (image.height * nextScale).clamp(24.0, 8192.0);
    }

    for (final shape in _document.shapes) {
      final endpoints = selectedArrowEndpoints[shape.id];
      if (endpoints == null) continue;
      final start = shape.startBinding == null
          ? transform(endpoints.start)
          : endpoints.start;
      final end = shape.endBinding == null
          ? transform(endpoints.end)
          : endpoints.end;
      ShapeBindingGeometry.applyArrowEndpoints(shape, start: start, end: end);
    }

    _reprojectBoundArrows();
    _document.touch();
    _invalidateLayer(currentLayer.id);
    tickFrame();
  }

  /// 结算混合对象手势。图层、形状（含关系图）和图片只形成一条撤销记录。
  void endDocumentObjectsTransform() {
    final before = _documentObjectsTransformBefore;
    _documentObjectsTransformBefore = null;
    if (before == null) return;
    final after = _documentObjectsSnapshot();
    if (_sameDocumentObjectsSnapshot(before, after)) return;
    _pushCommand(
      DocumentObjectsSnapshotCommand(this, before: before, after: after),
    );
    notifyListeners();
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
    _pushCommand(
      DocumentObjectsSnapshotCommand(
        this,
        before: before,
        after: _documentObjectsSnapshot(),
      ),
    );
    notifyListeners();
  }

  /// 批量删除当前选择。锁定形状/图片保留；作为被删形状目标的箭头端点先冻结
  /// 为当前绝对位置并解绑，因而不会留下悬挂 ID 或改变另一端可见几何。
  void deleteSelectedDocumentObjects() {
    if (!hasMixedDocumentObjectSelection) return;
    final before = _documentObjectsSnapshot();
    final deleteShapeIds = _document.shapes
        .where(
          (shape) =>
              _selectedDocumentShapeIds.contains(shape.id) && !shape.locked,
        )
        .map((shape) => shape.id)
        .toSet();
    final deleteImageIds = _document.imageItems
        .where(
          (image) =>
              _selectedDocumentImageIds.contains(image.id) && !image.locked,
        )
        .map((image) => image.id)
        .toSet();
    final deleteStrokeIndices = _selection.selectedStrokeIndices.toSet();
    if (deleteShapeIds.isEmpty &&
        deleteImageIds.isEmpty &&
        deleteStrokeIndices.isEmpty) {
      return;
    }

    for (final arrow in _document.shapes) {
      if (arrow.shapeType != ShapeType.arrow ||
          deleteShapeIds.contains(arrow.id)) {
        continue;
      }
      final endpoints = ShapeBindingGeometry.resolvedArrowEndpoints(
        arrow,
        _document.shapes,
      );
      var changed = false;
      if (deleteShapeIds.contains(arrow.startBinding?.targetShapeId)) {
        arrow.startBinding = null;
        changed = true;
      }
      if (deleteShapeIds.contains(arrow.endBinding?.targetShapeId)) {
        arrow.endBinding = null;
        changed = true;
      }
      if (changed) {
        ShapeBindingGeometry.applyArrowEndpoints(
          arrow,
          start: endpoints.start,
          end: endpoints.end,
        );
      }
    }
    _document.shapes.removeWhere((shape) => deleteShapeIds.contains(shape.id));
    _document.imageItems.removeWhere(
      (image) => deleteImageIds.contains(image.id),
    );
    final strokes = currentLayer.strokes;
    final orderedStrokeIndices = deleteStrokeIndices.toList()..sort();
    for (final index in orderedStrokeIndices.reversed) {
      if (index >= 0 && index < strokes.length) strokes.removeAt(index);
    }
    clearDocumentObjectSelection();
    _document.touch();
    _invalidateLayer(currentLayer.id);
    _pushCommand(
      DocumentObjectsSnapshotCommand(
        this,
        before: before,
        after: _documentObjectsSnapshot(),
      ),
    );
    notifyListeners();
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
    if (_currentLayerIndex >= _document.layers.length) {
      _currentLayerIndex = _document.layers.length - 1;
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
    _rebuildCacheMap();
    notifyListeners();
    _rebuildAll();
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
        if (_segmentsIntersect(a, b, corners[side], corners[(side + 1) % 4])) {
          return true;
        }
      }
    }
    return false;
  }

  /// 已销毁标记：dispose 后拒绝一切变更与通知（防止异步回调越界）。
  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// 高频绘制帧通知（笔触/选区拖动/视口变换期间触发）。
  ///
  /// 设计说明（性能关键）：
  /// 鼠标/手指移动事件远高于屏幕刷新率，若每个事件都调用
  /// [notifyListeners]，会导致工具栏/图层面板等低频组件整树重建，
  /// 造成画布"跟手延迟"。因此：
  /// - 正在拖动中的连续更新（笔画延伸、选区扩展、视口变换）→ 只 tick [frameTick]，
  ///   仅触发画布局部重绘（CustomPainter 的 repaint 监听）；
  /// - 一次操作完成或状态切换（笔画提交、图层操作、撤销）→ 调用 [notifyListeners]，
  ///   重建低频组件。
  final ValueNotifier<int> frameTick = ValueNotifier<int>(0);

  /// 触发一次高频重绘（仅画布，不重建低频 UI）。
  void tickFrame() {
    if (_disposed) return;
    frameTick.value++;
  }

  // ---------------- 工具状态 ----------------

  /// 当前工具类型（画笔/橡皮擦等）。
  BrushType _tool = BrushType.pen;
  BrushType get tool => _tool;
  set tool(BrushType value) {
    if (_tool != value) {
      _tool = value;
      notifyListeners();
    }
  }

  /// 当前画笔颜色（吸管取色后也会更新这里）。
  Color _color = const Color(0xFF1A1A1A);
  Color get color => _color;
  set color(Color value) {
    _color = value;
    notifyListeners();
  }

  /// 画笔粗细（逻辑像素）。
  double _brushSize = 6.0;
  double get brushSize => _brushSize;
  set brushSize(double value) {
    _brushSize = value;
    notifyListeners();
  }

  /// 橡皮擦粗细（逻辑像素）。
  double _eraserSize = 24.0;

  /// [EraserMode.stroke] 直接删除命中的整笔；[EraserMode.pixel] 记录透明
  /// 合成轨迹。模式只影响编辑语义，不改变普通钢笔/高亮笔的数据格式。
  EraserMode _eraserMode = EraserMode.stroke;
  EraserMode get eraserMode => _eraserMode;
  set eraserMode(EraserMode value) {
    if (_eraserMode == value) return;
    _eraserMode = value;
    notifyListeners();
  }

  double get eraserSize => _eraserSize;
  set eraserSize(double value) {
    _eraserSize = value;
    notifyListeners();
  }

  /// 当前绘制工具对应的线宽（画笔粗细或橡皮擦粗细）。
  double get currentSize =>
      _tool == BrushType.eraser ? _eraserSize : _brushSize;

  /// 当前图层索引（列表尾部为最上层）。
  int _currentLayerIndex = 0;
  int get currentLayerIndex => _currentLayerIndex;
  set currentLayerIndex(int value) {
    if (value >= 0 && value < _document.layers.length) {
      _currentLayerIndex = value;
      notifyListeners();
    }
  }

  Layer get currentLayer => _document.layers[_currentLayerIndex];

  // ---------------- 视口变换 ----------------

  /// 画布缩放比例（1.0 = 实际大小）。
  double viewScale = 1.0;

  /// 画布在视口中的平移偏移（画布中心相对视口中心的位移）。
  Offset viewOffset = Offset.zero;

  /// 画布旋转角度（弧度，Phase 7 双指旋转用）。
  double viewRotation = 0.0;

  /// 画布文档中心（缩放/旋转的基准点）。
  Offset get _canvasCenter => _document.size.center(Offset.zero);

  /// 把视图坐标（像素）转换为画布逻辑坐标。
  ///
  /// 变换模型（与 CanvasPainter 严格互逆）：
  ///   view = R(rot) · (scale · (p - center)) + center + offset
  ///   逆：p = R(-rot) · (view - center - offset) / scale + center
  Offset viewToCanvas(Offset viewPoint) {
    final c = _canvasCenter;
    final t = _rotatePoint(viewPoint - c - viewOffset, -viewRotation);
    return t / viewScale + c;
  }

  /// 把画布坐标转换为视图坐标。
  Offset canvasToView(Offset canvasPoint) {
    final c = _canvasCenter;
    final t = _rotatePoint((canvasPoint - c) * viewScale, viewRotation);
    return t + c + viewOffset;
  }

  static Offset _rotatePoint(Offset p, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
  }

  // ---------------- 图层渲染缓存 ----------------

  final LayerCompositor _compositor = const LayerCompositor();
  final Map<String, LayerRenderCache> _caches = {};

  /// 重建缓存索引（图层增删后调用）。
  ///
  /// 注意：被移除的缓存必须释放位图，否则 ui.Image 泄漏。
  void _rebuildCacheMap() {
    final ids = _document.layers.map((l) => l.id).toSet();
    final removed = <String>[];
    _caches.removeWhere((key, _) {
      if (ids.contains(key)) return false;
      removed.add(key);
      return true;
    });
    for (final key in removed) {
      _caches.remove(key)?.dispose();
    }
    for (final layer in _document.layers) {
      _caches.putIfAbsent(layer.id, LayerRenderCache.new);
    }
  }

  /// 标记图层内容/属性变化，触发异步重建缓存。
  ///
  /// [region] 非空时执行增量脏矩形重建：只重绘该区域内的笔画，
  /// 区域外内容保持不变（性能优化，避免整层反复光栅化）。
  Future<void> _invalidateLayer(String layerId, {Rect? region}) async {
    // 无限画布不使用固定宽高的离屏位图缓存；直接按当前可视区绘制矢量点列，
    // 从根源避免坐标超出文档默认尺寸后被缓存裁剪。
    if (_document.infinite) {
      notifyListeners();
      return;
    }
    final cache = _caches[layerId];
    final layer = _document.layers.where((l) => l.id == layerId).firstOrNull;
    if (cache == null || layer == null) return;
    cache.dirty = true;
    cache.dirtyRegion = region;
    await _rebuildLayer(layer);
    // 复查：若重建被并发跳过（_rebuilding 为 true 直接返回）或
    // 期间又有新变更，此处确保脏状态不被遗留。
    if (cache.dirty && !_disposed) {
      await _rebuildLayer(layer);
    }
  }

  /// 图层位图重建是否正在进行中（全局串行标志）。
  ///
  /// 用途：防止连续快速绘制时多个异步重建并发，导致竞态下
  /// 全部重建被"防护逻辑"放弃、图层位图永远停留在旧状态
  /// （表现为"画几笔就画不上去了/橡皮擦失效"）。
  bool _rebuilding = false;

  /// 重建单个图层的位图缓存。
  ///
  /// 串行化设计（修复竞态缺陷）：
  /// - 同一时刻只允许一个重建循环运行：若已有重建在跑，本次调用
  ///   直接返回，由进行中的循环通过复查 dirty 处理本次变更；
  /// - 循环复查：每轮重建开始前清 dirty，完成后若期间又有新变更
  ///   （dirty 被再次置位）则继续重建，直到位图内容为最新；
  /// - 每一轮完成的位图都会被采纳（不再"放弃"），保证最终画面
  ///   一定包含最新笔画/橡皮擦效果。
  ///
  /// 增量重建（性能优化）：若缓存携带 dirtyRegion，则只重绘该区域
  /// （区域外旧内容保留），大幅减少反复光栅化整层的开销。
  Future<void> _rebuildLayer(Layer layer) async {
    final cache = _caches[layer.id];
    if (cache == null || _disposed) return;
    if (_rebuilding) return; // 已有重建循环在跑，由它复查 dirty。
    _rebuilding = true;
    try {
      // 循环重建直到位图与当前图层内容一致。
      while (cache.dirty && !_disposed) {
        cache.dirty = false; // 先清标志，重建期间若有新变更会重新置位。
        // 增量重建：只在有脏矩形且已有底图时启用（否则必须整层重建）。
        final region = (cache.image != null && cache.dirtyRegion != null)
            ? cache.dirtyRegion
            : null;
        final base = region != null ? cache.image : null; // 旧位图作为底
        cache.dirtyRegion = null; // 本次重建消费掉脏矩形。
        final newImage = await _compositor.rasterize(
          layer,
          _document.width,
          _document.height,
          region: region,
          base: base,
        );
        if (_disposed) {
          newImage.dispose();
          return;
        }
        final old = cache.image;
        cache.image = newImage;
        old?.dispose();
        notifyListeners(); // 每次位图更新后通知画布重绘。
        // 循环条件：重建期间又新增笔画（dirty 重新置位）→ 继续重建。
      }
    } finally {
      _rebuilding = false;
    }
  }

  /// 为绘制提供图层位图视图列表（自底向上）。
  List<LayerPaintView> get paintViews => [
    for (final layer in _document.layers)
      LayerPaintView(
        image: _caches[layer.id]?.image,
        visible: layer.visible,
        opacity: layer.opacity,
      ),
  ];

  /// 将图层中的矢量墨迹直接绘制到当前 Canvas。
  ///
  /// 供无限画布的可视区域渲染和导出使用；[bounds] 应为当前 Canvas 的局部
  /// 裁剪范围，避免高亮笔局部合成器创建超大离屏层。
  void paintVectorLayers(
    ui.Canvas canvas,
    Rect bounds, {
    Set<BrushType> excludedTypes = const {},
  }) {
    for (final layer in _document.layers) {
      if (!layer.visible || layer.opacity <= 0) continue;
      final strokes = excludedTypes.isEmpty
          ? layer.strokes
          : layer.strokes
                .where((stroke) => !excludedTypes.contains(stroke.type))
                .toList(growable: false);
      if (layer.opacity >= 1) {
        InkLayerPainter.paintStrokes(canvas, bounds, strokes);
        continue;
      }
      canvas.saveLayer(
        bounds,
        Paint()..color = Color.fromRGBO(0, 0, 0, layer.opacity),
      );
      InkLayerPainter.paintStrokes(canvas, bounds, strokes);
      canvas.restore();
    }
  }

  // ---------------- 笔画绘制 ----------------

  /// 当前正在绘制中的笔画（未提交到图层，仅用于实时预览）。
  Stroke? _activeStroke;
  Stroke? get activeStroke => _activeStroke;

  /// 一笔的原始采样与实时预览几何。仅在书写期间存在。
  StrokeGeometryCache? _activeGeometry;

  /// 激光工具的起笔时刻；收笔后据此按起笔端逐段消退。
  DateTime? _activeLaserStartedAt;

  /// 临时荧光笔开关。开启后笔画仅短暂显示，不写入页面数据、历史或导出。
  bool _temporaryMarkerEnabled = false;
  bool get temporaryMarkerEnabled => _temporaryMarkerEnabled;
  set temporaryMarkerEnabled(bool value) {
    if (_temporaryMarkerEnabled == value) return;
    _temporaryMarkerEnabled = value;
    notifyListeners();
  }

  static const Duration temporaryMarkerLifetime = Duration(seconds: 4);
  static const Duration laserHoldDuration = Duration(milliseconds: 700);
  static const Duration laserSweepDuration = Duration(milliseconds: 1800);
  static const Duration laserFinalFadeDuration = Duration(milliseconds: 260);
  final List<_TemporaryInk> _temporaryInks = <_TemporaryInk>[];
  final List<_TemporaryLaserInk> _temporaryLasers = <_TemporaryLaserInk>[];
  Timer? _temporaryInkTicker;

  /// 尚在淡出期的临时高亮笔，供画布在矢量图层之上直接绘制。
  List<({Stroke stroke, double opacity})> get temporaryMarkerStrokes {
    final now = DateTime.now();
    _pruneTemporaryInks(now);
    return _temporaryInks
        .map((entry) => (stroke: entry.stroke, opacity: entry.opacityAt(now)))
        .where((entry) => entry.opacity > 0)
        .toList(growable: false);
  }

  /// 激光尾迹的可见片段。首点索引随时间前移，实现从起笔端逐段消退。
  List<({Stroke stroke, int firstPointIndex, double opacity})>
  get temporaryLaserStrokes {
    final now = DateTime.now();
    _pruneTemporaryInks(now);
    return _temporaryLasers
        .map(
          (entry) => (
            stroke: entry.stroke,
            firstPointIndex: entry.firstVisiblePointAt(now),
            opacity: entry.opacityAt(now),
          ),
        )
        .where((entry) => entry.opacity > 0)
        .toList(growable: false);
  }

  /// 是否正在绘制。
  bool get isDrawing => _activeStroke != null;

  /// 对象橡皮擦手势的增量记录（对齐 excalidraw StoreDelta 只存变更）。
  /// 记录被删笔画：(图层索引, 删除前原位置, 笔画对象)，整段擦除只生成
  /// 一条撤销记录，且不深拷贝整层。
  final List<({int layerIndex, int index, Stroke stroke})> _objectEraseRemoved =
      [];
  bool _objectEraseChanged = false;

  /// 被擦除的标准形状（问题3）：整笔/透明模式的擦除开关。
  ///
  /// 用户实测反馈"标准直线无法被橡皮擦擦除"，且需要按擦除模式细分：
  /// 两个开关分别控制整笔模式（[EraserMode.stroke]）与透明模式
  /// （[EraserMode.pixel]）是否擦除标准形状；两者都关 = 形状不可被擦除，
  /// 只开其一 = 仅该模式可擦除，两者都开 = 两种模式均可擦除。
  bool _eraserCanEraseShapesStroke = true;
  bool _eraserCanEraseShapesPixel = true;
  bool get eraserCanEraseShapesStroke => _eraserCanEraseShapesStroke;
  bool get eraserCanEraseShapesPixel => _eraserCanEraseShapesPixel;
  set eraserCanEraseShapesStroke(bool value) {
    if (_eraserCanEraseShapesStroke == value) return;
    _eraserCanEraseShapesStroke = value;
    notifyListeners();
  }

  set eraserCanEraseShapesPixel(bool value) {
    if (_eraserCanEraseShapesPixel == value) return;
    _eraserCanEraseShapesPixel = value;
    notifyListeners();
  }

  /// 当前擦除模式是否允许擦除标准形状。
  bool get _eraserCanEraseShapes =>
      _eraserMode == EraserMode.stroke
          ? _eraserCanEraseShapesStroke
          : _eraserCanEraseShapesPixel;

  /// 本次手势中被擦除的标准形状（按引用记录，供增量命令还原）。
  final List<PageShapeItem> _objectEraseShapes = [];

  /// 命中测试：橡皮擦中心点是否触及标准形状（外接框膨胀橡皮擦半径）。
  bool _eraserHitsShape(PageShapeItem shape, Offset center, double radius) {
    final bounds = ShapeBindingGeometry.rawBounds(shape).inflate(radius);
    if (!bounds.contains(center)) return false;
    // 线性元素（直线/箭头）用真实端点做线段距离判定，避免大外接框误擦。
    if (shape.shapeType == ShapeType.line ||
        shape.shapeType == ShapeType.arrow) {
      final start = shape.lineStart ?? Offset(0, shape.height);
      final end = shape.lineEnd ?? Offset(shape.width, 0);
      // 审查发现 P1：绝对坐标基准必须用形状原始外接框左上角
      // （shape.position），而不是已膨胀 radius 的 bounds.topLeft，
      // 否则线段整体偏移 radius 导致命中判定偏差（漏擦/误擦）。
      final origin = Offset(shape.x, shape.y);
      final startAbs = start + origin;
      final endAbs = end + origin;
      return _distanceToSegment(center, startAbs, endAbs) <= radius;
    }
    return true;
  }

  /// 开始对象橡皮擦手势。调用方只在 [EraserMode.stroke] 下调用。
  void beginObjectErase() {
    _objectEraseRemoved.clear();
    _objectEraseShapes.clear();
    _objectEraseChanged = false;
  }

  /// 擦除以 [canvasPoint] 为中心、以橡皮擦半径命中的整条笔画。
  ///
  /// 该模式不生成任何 [BrushType.eraser] 伪笔画，因此不会在画面上留下黑线，
  /// 命中的线条会立即从对象模型、保存文件和后续导出中消失。
  bool eraseStrokesAt(Offset canvasPoint) {
    final radius = _eraserSize / 2;
    var changed = false;
    final changedLayers = <int>[];
    for (
      var layerIndex = 0;
      layerIndex < _document.layers.length;
      layerIndex++
    ) {
      final layer = _document.layers[layerIndex];
      if (!layer.visible) continue;
      // 记录命中笔画在删除前的原位置，供增量命令精确还原。
      final removed = <({int index, Stroke stroke})>[];
      for (var i = 0; i < layer.strokes.length; i++) {
        final stroke = layer.strokes[i];
        if (_strokeHitsCircle(stroke, canvasPoint, radius)) {
          removed.add((index: i, stroke: stroke));
        }
      }
      if (removed.isEmpty) continue;
      for (final entry in removed.reversed) {
        layer.strokes.removeAt(entry.index);
      }
      _objectEraseRemoved.addAll([
        for (final entry in removed)
          (layerIndex: layerIndex, index: entry.index, stroke: entry.stroke),
      ]);
      changed = true;
      changedLayers.add(layerIndex);
    }

    // 标准形状擦除（问题3）：开关开启时，命中标准直线/图案也一并删除，
    // 并纳入同一条增量撤销记录。线性元素按真实端点做线段距离判定。
    if (_eraserCanEraseShapes && _document.shapes.isNotEmpty) {
      final hitShapes = <PageShapeItem>[];
      for (final shape in _document.shapes) {
        if (_eraserHitsShape(shape, canvasPoint, radius)) {
          hitShapes.add(shape);
        }
      }
      if (hitShapes.isNotEmpty) {
        for (final shape in hitShapes) {
          _document.shapes.remove(shape);
        }
        _objectEraseShapes.addAll(hitShapes);
        changed = true;
      }
    }

    if (!changed) return false;
    _objectEraseChanged = true;
    _document.touch();
    for (final layerIndex in changedLayers) {
      unawaited(_invalidateLayer(_document.layers[layerIndex].id));
    }
    notifyListeners();
    return true;
  }

  /// 提交一个对象橡皮擦手势的统一撤销记录（增量命令，零整层拷贝）。
  void endObjectErase() {
    if (!_objectEraseChanged) {
      _objectEraseRemoved.clear();
      _objectEraseShapes.clear();
      return;
    }
    _objectEraseChanged = false;
    _pushCommand(
      EraseStrokesCommand(
        this,
        List.of(_objectEraseRemoved),
        removedShapes: List.of(_objectEraseShapes),
      ),
    );
    _objectEraseRemoved.clear();
    _objectEraseShapes.clear();
    notifyListeners();
  }

  /// 取消对象橡皮擦手势；如已经移除对象则还原（按增量记录插回）。
  void cancelObjectErase() {
    final changed = _objectEraseChanged;
    if (changed && (_objectEraseRemoved.isNotEmpty || _objectEraseShapes.isNotEmpty)) {
      EraseStrokesCommand(
        this,
        List.of(_objectEraseRemoved),
        removedShapes: List.of(_objectEraseShapes),
      ).undo();
    }
    _objectEraseRemoved.clear();
    _objectEraseShapes.clear();
    _objectEraseChanged = false;
  }

  static bool _strokeHitsCircle(Stroke stroke, Offset center, double radius) {
    if (stroke.points.isEmpty) return false;
    final threshold = radius + stroke.width / 2;
    if (stroke.points.length == 1) {
      return (stroke.points.first.offset - center).distance <= threshold;
    }
    for (var i = 1; i < stroke.points.length; i++) {
      if (_distanceToSegment(
            center,
            stroke.points[i - 1].offset,
            stroke.points[i].offset,
          ) <=
          threshold) {
        return true;
      }
    }
    return false;
  }

  static double _distanceToSegment(Offset point, Offset a, Offset b) {
    final segment = b - a;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    if (lengthSquared <= 1e-8) return (point - a).distance;
    final projected =
        ((point - a).dx * segment.dx + (point - a).dy * segment.dy) /
        lengthSquared;
    final t = projected.clamp(0.0, 1.0);
    return (point - (a + segment * t)).distance;
  }

  /// 开始一笔：创建活动笔画。
  void startStroke(Offset canvasPoint, {double pressure = 1.0}) {
    _activeLaserStartedAt = _tool == BrushType.laser ? DateTime.now() : null;
    final first = StrokePoint(canvasPoint.dx, canvasPoint.dy, pressure);
    final geometry = StrokeGeometryCache(first);
    _activeGeometry = geometry;
    _activeStroke = Stroke(
      points: geometry.previewPoints,
      color: _tool == BrushType.eraser ? const Color(0x00000000) : _color,
      width: currentSize,
      type: _tool,
    );
    tickFrame(); // 仅重绘画布（活动笔画预览），不重建低频 UI。
  }

  /// 延伸当前笔画（追加采样点）。
  void extendStroke(Offset canvasPoint, {double pressure = 1.0}) {
    final geometry = _activeGeometry;
    if (_activeStroke == null || geometry == null) return;
    geometry.append(StrokePoint(canvasPoint.dx, canvasPoint.dy, pressure));
    tickFrame(); // 高频路径：只通知画布重绘。
  }

  /// 取消当前未提交笔画。
  ///
  /// 用于双指缩放或掌托策略判定为误触时的安全回退。取消动作不会修改图层、
  /// 历史栈、保存点或文档时间戳，只刷新活动笔画预览。
  void cancelActiveStroke() {
    if (_activeStroke == null) return;
    _activeStroke = null;
    _activeGeometry = null;
    _activeLaserStartedAt = null;
    tickFrame();
  }

  /// 结束一笔：提交到当前图层并记录撤销历史。
  Future<void> endStroke() async {
    final s = _activeStroke;
    final geometry = _activeGeometry;
    final laserStartedAt = _activeLaserStartedAt;
    if (s == null || geometry == null) return;
    _activeStroke = null;
    _activeGeometry = null;
    _activeLaserStartedAt = null;

    // 收笔从完整输入样本构建持久化点列；活动笔画始终引用同一个可变列表，
    // 因此无需变更 Stroke 数据结构或文档格式。replacePoints 会递增几何版本，
    // 使 StrokeRenderer 的 Path 惰性缓存失效，收笔后的首次重绘重新生成轮廓。
    s.replacePoints(geometry.finish());
    if (s.points.length < 2 && s.type != BrushType.eraser) {
      // 孤点（单击未拖动）：仍保留为单个圆点，便于"点一下"产生墨点。
    }

    if (s.type == BrushType.marker && _temporaryMarkerEnabled) {
      _addTemporaryMarker(s);
      tickFrame();
      return;
    }

    if (s.type == BrushType.laser) {
      _addTemporaryLaser(s, laserStartedAt ?? DateTime.now());
      tickFrame();
      return;
    }

    final recognized = ShapeRecognizer.recognize(s);
    if (recognized != null) {
      final shape = PageShapeItem(
        id: LocalIdGenerator.next('shape'),
        shapeType: recognized.type,
        x: recognized.bounds.left,
        y: recognized.bounds.top,
        width: recognized.bounds.width,
        height: recognized.bounds.height,
        color: s.color.toARGB32(),
        strokeWidth: s.width.clamp(1, 20).toDouble(),
        flipX: recognized.flipX,
        flipY: recognized.flipY,
        // 线性元素保存真实端点，确保直线/箭头方向与鼠标轨迹一致
        // （修复"从左往右画却生成反向/斜线"的问题，参考 Saber shape_pen）。
        lineStart: recognized.lineStart,
        lineEnd: recognized.lineEnd,
      );
      _document.shapes.add(shape);
      _document.touch();
      _pushCommand(
        ReplaceStrokeWithShapeCommand(this, _currentLayerIndex, s, shape),
      );
      await _invalidateLayer(currentLayer.id);
      notifyListeners();
      return;
    }

    currentLayer.strokes.add(s);
    _document.touch();
    // 命令模式：新增笔画用零拷贝逆操作命令（撤销=移除，重做=重加）。
    _pushCommand(AddStrokeCommand(this, _currentLayerIndex, s));

    // 增量脏矩形重建：只重绘新笔画的包围盒区域（含线宽余量），
    // 区域外旧内容保持不变，避免整层反复光栅化（性能优化）。
    // 橡皮擦同样走区域重建——合成器会用 clipRect 限定清除范围。
    final region = StrokeRenderer.strokeBounds(s);
    await _invalidateLayer(currentLayer.id, region: region);
    notifyListeners();
  }

  void _addTemporaryMarker(Stroke stroke) {
    _temporaryInks.add(_TemporaryInk(stroke, DateTime.now()));
    _ensureTemporaryInkTicker();
  }

  void _addTemporaryLaser(Stroke stroke, DateTime startedAt) {
    _temporaryLasers.add(_TemporaryLaserInk(stroke, startedAt));
    _ensureTemporaryInkTicker();
  }

  void _ensureTemporaryInkTicker() {
    _temporaryInkTicker ??= Timer.periodic(const Duration(milliseconds: 16), (
      _,
    ) {
      final now = DateTime.now();
      _pruneTemporaryInks(now);
      if (_temporaryInks.isEmpty && _temporaryLasers.isEmpty) {
        _temporaryInkTicker?.cancel();
        _temporaryInkTicker = null;
      }
      tickFrame();
    });
  }

  void _pruneTemporaryInks(DateTime now) {
    _temporaryInks.removeWhere(
      (entry) => now.difference(entry.startedAt) >= temporaryMarkerLifetime,
    );
    _temporaryLasers.removeWhere((entry) => entry.isExpiredAt(now));
  }

  /// 笔画命令撤销/重做后的统一处理：先同步通知（按钮/状态立即刷新），
  /// 再重建该图层位图（完成后再次通知更新画面）。
  /// 供命令类（document_commands.dart）调用的公开包装方法。
  ///
  /// 命令类与控制器分属不同文件，无法访问私有成员
  /// （`_restoreLayers`/`_document`/`_afterStrokeUndoRedo`），
  /// 因此提供等价的公开入口，行为完全一致（R5 拆分）。
  void restoreLayersSnapshot(List<Layer> snapshot) => _restoreLayers(snapshot);

  void touchDocument() => _document.touch();

  Future<void> afterStrokeUndoRedo(int layerIndex) =>
      _afterStrokeUndoRedo(layerIndex);

  /// 把由手绘识别转出的形状撤销回原笔画。供命令对象调用。
  void undoRecognizedShape(int layerIndex, Stroke stroke, PageShapeItem shape) {
    _document.shapes.remove(shape);
    _document.layers[layerIndex].strokes.add(stroke);
    _document.touch();
    unawaited(_afterStrokeUndoRedo(layerIndex));
  }

  /// 重新把原笔画替换为已识别形状。供命令对象调用。
  void redoRecognizedShape(int layerIndex, Stroke stroke, PageShapeItem shape) {
    _document.layers[layerIndex].strokes.remove(stroke);
    _document.shapes.add(shape);
    _document.touch();
    unawaited(_afterStrokeUndoRedo(layerIndex));
  }

  Future<void> _afterStrokeUndoRedo(int layerIndex) async {
    if (_disposed) return;
    // 同步通知一次：撤销/重做状态、工具栏按钮立即刷新（低频操作语义）。
    notifyListeners();
    final layerId = _document.layers[layerIndex].id;
    await _invalidateLayer(layerId);
    if (!_disposed) notifyListeners(); // 位图重建完成后再次通知。
  }

  /// 深拷贝当前图层列表（strokes 列表也拷贝，Stroke 对象本身不可变）。
  List<Layer> _snapshotLayers() => [
    for (final l in _document.layers)
      Layer(
        id: l.id,
        name: l.name,
        visible: l.visible,
        opacity: l.opacity,
        strokes: List.of(l.strokes),
      ),
  ];

  /// 用快照列表替换当前文档图层（撤销/重做内部用）。
  void _restoreLayers(List<Layer> snapshot) {
    _document.layers
      ..clear()
      ..addAll(snapshot);
    _document.touch();
    if (_currentLayerIndex >= _document.layers.length) {
      _currentLayerIndex = _document.layers.length - 1;
    }
    _rebuildCacheMap();
    // 同步通知一次：撤销/重做状态、工具栏按钮立即刷新，
    // 不等异步位图重建（重建完成后 _rebuildAll 会再次通知）。
    notifyListeners();
    // 全部图层可能都变了，逐层重建（完成后再次通知更新位图）。
    _rebuildAll();
  }

  Future<void> _rebuildAll() async {
    if (_disposed) return;
    for (final layer in _document.layers) {
      _caches[layer.id]?.dirty = true;
    }
    for (final layer in List.of(_document.layers)) {
      if (_disposed) return;
      await _rebuildLayer(layer);
    }
    if (!_disposed) notifyListeners();
  }

  // ---------------- 撤销 / 重做（命令模式） ----------------

  /// 历史栈上限：防止长时间会话导致内存无限增长。
  /// 超出上限时丢弃最旧的记录（与主流绘图软件行为一致）。
  static const int maxHistoryEntries = 60;

  /// 命令栈（替代整层快照）：
  /// - 高频操作（新增笔画）使用零拷贝逆操作命令 [AddStrokeCommand]；
  /// - 低频操作（图层增删/合并/选区变换等）通过 [SnapshotCommand]
  ///   桥接原有 before/after 快照，行为完全一致。
  final List<DocCommand> _history = [];
  int _historyPosition = 0;

  bool get canUndo => _historyPosition > 0;
  bool get canRedo => _historyPosition < _history.length;

  /// 记录一条命令。
  ///
  /// 若当前处于历史中间位置（即刚刚撤销过若干步），
  /// 则先丢弃被撤销的"重做分支"，再追加新命令——
  /// 这是绘图类软件的标准行为：撤销后画新内容，旧分支不再可重做。
  void _pushCommand(DocCommand command) {
    if (_historyPosition < _history.length) {
      _history.removeRange(_historyPosition, _history.length);
    }
    _history.add(command);
    // 限制历史长度：移除最旧的条目，并校正位置指针。
    if (_history.length > maxHistoryEntries) {
      final overflow = _history.length - maxHistoryEntries;
      _history.removeRange(0, overflow);
      _historyPosition -= overflow;
      if (_historyPosition < 0) _historyPosition = 0;
    }
    _historyPosition = _history.length;
  }

  /// 兼容入口：把快照条目包装为命令（低频操作使用）。
  void _pushHistory(HistoryEntry entry) {
    _pushCommand(SnapshotCommand(this, entry.before, entry.after));
  }

  void undo() {
    if (!canUndo) return;
    _historyPosition--;
    _history[_historyPosition].undo();
  }

  void redo() {
    if (!canRedo) return;
    _history[_historyPosition].redo();
    _historyPosition++;
  }

  // ---------------- 图层操作 ----------------

  /// 新建图层（放在最上层），并自动选中它。
  void addLayer({String? name}) {
    final before = _snapshotLayers();
    final layer = Layer(
      id: 'layer_${DateTime.now().microsecondsSinceEpoch}',
      name: name ?? '图层 ${_document.layers.length + 1}',
    );
    _document.layers.add(layer);
    _document.touch();
    _currentLayerIndex = _document.layers.length - 1;
    _caches[layer.id] = LayerRenderCache();
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    notifyListeners();
  }

  /// 删除指定索引的图层。
  void removeLayer(int index) {
    if (_document.layers.length <= 1) return; // 至少保留一个图层
    final before = _snapshotLayers();
    final removed = _document.layers.removeAt(index);
    _caches.remove(removed.id)?.dispose();
    _document.touch();
    if (_currentLayerIndex >= _document.layers.length) {
      _currentLayerIndex = _document.layers.length - 1;
    }
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    notifyListeners();
  }

  /// 切换图层显隐。
  void toggleLayerVisibility(int index) {
    final before = _snapshotLayers();
    final layer = _document.layers[index];
    layer.visible = !layer.visible;
    _document.touch();
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    notifyListeners();
  }

  /// 设置图层透明度（0~1）。
  void setLayerOpacity(int index, double value) {
    final layer = _document.layers[index];
    if ((layer.opacity - value).abs() < 0.001) return;
    layer.opacity = value.clamp(0.0, 1.0);
    _document.touch();
    notifyListeners();
  }

  /// 上移图层（向更上层移动一格）。
  void moveLayerUp(int index) {
    if (index >= _document.layers.length - 1) return;
    final before = _snapshotLayers();
    final l = _document.layers.removeAt(index);
    _document.layers.insert(index + 1, l);
    _document.touch();
    _currentLayerIndex = index + 1;
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    notifyListeners();
  }

  /// 下移图层（向更下层移动一格）。
  void moveLayerDown(int index) {
    if (index <= 0) return;
    final before = _snapshotLayers();
    final l = _document.layers.removeAt(index);
    _document.layers.insert(index - 1, l);
    _document.touch();
    _currentLayerIndex = index - 1;
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    notifyListeners();
  }

  /// 向下合并图层：把 [index] 层的内容合并到 index-1 层，并删除 [index] 层。
  void mergeLayerDown(int index) {
    if (index <= 0 || index >= _document.layers.length) return;
    final before = _snapshotLayers();
    final upper = _document.layers[index];
    final lower = _document.layers[index - 1];
    // 笔画顺序：底层原有笔画在前，上层笔画追加在后。
    lower.strokes.addAll(upper.strokes);
    _document.layers.removeAt(index);
    _caches.remove(upper.id)?.dispose();
    _document.touch();
    _currentLayerIndex = index - 1;
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _rebuildAll();
  }

  // ---------------- 画布操作 ----------------

  /// 清空当前图层所有内容。
  void clearCurrentLayer() {
    final before = _snapshotLayers();
    if (currentLayer.strokes.isEmpty) return;
    currentLayer.strokes.clear();
    _document.touch();
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _invalidateLayer(currentLayer.id);
  }

  /// 清空整个文档（所有图层）。
  void clearAll() {
    final before = _snapshotLayers();
    var changed = false;
    for (final l in _document.layers) {
      if (l.strokes.isNotEmpty) {
        l.strokes.clear();
        changed = true;
      }
    }
    if (!changed) return;
    _document.touch();
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _rebuildAll();
  }

  // ---------------- 吸管取色 ----------------

  /// 从画布当前位置取色（读取合成位图像素）。
  ///
  /// 实现：把文档整体渲染到离屏图片，再读取该点像素。
  /// 返回 null 表示取色失败（越界或读取异常）。
  Future<Color?> pickColorAt(Offset canvasPoint) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    _paintDocument(canvas);
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(_document.width, _document.height);
      final x = canvasPoint.dx.round().clamp(0, _document.width - 1);
      final y = canvasPoint.dy.round().clamp(0, _document.height - 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      final offset = (y * _document.width + x) * 4;
      return Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    } finally {
      // 无论成功/失败都释放位图，避免泄漏。
      image?.dispose();
      picture.dispose();
    }
  }

  /// 无限画布的实际内容边界（笔画与几何形状），用于导出和局部合成。
  /// 空画布保留一个适中的默认导出区域，避免生成 0×0 文件。
  Rect contentBounds() {
    Rect? result;
    void include(Rect? value) {
      if (value == null) return;
      result = result == null ? value : result!.expandToInclude(value);
    }

    for (final layer in _document.layers) {
      if (!layer.visible) continue;
      for (final stroke in layer.strokes) {
        include(StrokeRenderer.strokeBounds(stroke));
      }
    }
    for (final shape in _document.shapes) {
      include(ShapeRenderer.bounds(shape));
    }
    for (final image in _document.imageItems) {
      include(Rect.fromLTWH(image.x, image.y, image.width, image.height));
    }
    return (result ?? const Rect.fromLTWH(-512, -384, 1024, 768)).inflate(24);
  }

  /// 把整个文档（含透明度）绘制到指定 Canvas 上（供导出/取色复用）。
  void _paintDocument(
    ui.Canvas canvas, {
    Rect? bounds,
    Set<BrushType> excludedTypes = const {},
  }) {
    if (_document.infinite || excludedTypes.isNotEmpty) {
      paintVectorLayers(
        canvas,
        bounds ?? contentBounds(),
        excludedTypes: excludedTypes,
      );
    } else {
      for (final view in paintViews) {
        final image = view.image;
        if (image == null || !view.visible || view.opacity <= 0) continue;
        final paint = Paint()
          ..color = Color.fromRGBO(0, 0, 0, view.opacity)
          ..filterQuality = FilterQuality.high;
        canvas.drawImage(image, Offset.zero, paint);
      }
    }
    final images = List.of(_document.imageItems)
      ..sort((a, b) => a.zOrder.compareTo(b.zOrder));
    for (final item in images) {
      final image = _documentImages[item.id];
      if (image == null) continue;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(item.x, item.y, item.width, item.height),
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    for (final shape in _document.shapes) {
      ShapeRenderer.drawDocumentShape(canvas, shapeForRendering(shape));
    }
  }

  /// 生成用于显示/导出的形状视图。绑定箭头在此按当前目标几何投影端点，
  /// 不会在普通绘制中写回文档，故可确保屏幕与导出一致且不制造隐式历史。
  PageShapeItem shapeForRendering(PageShapeItem shape) {
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

  /// 把整个文档渲染为 PNG 字节（Phase 6 导出功能）。
  ///
  /// [scale] 用于导出分辨率：1.0 = 画布实际大小，2.0 = 放大一倍。
  /// 返回 PNG 编码的字节；失败返回 null。
  Future<Uint8List?> renderToPng({
    double scale = 1.0,
    Set<BrushType> excludedTypes = const {},
  }) async {
    await _ensureDocumentImagesLoaded();
    final bounds = _document.infinite
        ? contentBounds()
        : Rect.fromLTWH(
            0,
            0,
            _document.width.toDouble(),
            _document.height.toDouble(),
          );
    final w = (bounds.width * scale).round();
    final h = (bounds.height * scale).round();
    if (w <= 0 || h <= 0) return null;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // 白色纸面背景（导出图片以白纸为底）。
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);
    _paintDocument(canvas, bounds: bounds, excludedTypes: excludedTypes);
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(w, h);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      // 无论成功/失败都释放位图，避免泄漏。
      image?.dispose();
      picture.dispose();
    }
  }

  // ---------------- 选区与变换（Phase 4） ----------------

  /// 当前选区工具（none = 正常绘制）。
  SelectionTool _selectionTool = SelectionTool.none;
  SelectionTool get selectionTool => _selectionTool;
  set selectionTool(SelectionTool value) {
    _selectionTool = value;
    _selection = const Selection();
    notifyListeners();
  }

  /// 当前选区（多边形 + 命中笔画）。
  Selection _selection = const Selection();
  Selection get selection => _selection;

  /// 选区主色（对齐 Saber select.dart 的 getDominantStrokeColor）：
  /// 按笔画长度加权统计当前选中笔画的颜色，最“长”的颜色胜出，
  /// 用于"取主色/批量改色"时给出代表性颜色，避免被零星小笔画误导。
  Color? get dominantStrokeColor {
    final distribution = <int, double>{};
    for (final index in _selection.selectedStrokeIndices) {
      if (index < 0 || index >= currentLayer.strokes.length) continue;
      final stroke = currentLayer.strokes[index];
      distribution.update(
        stroke.color.toARGB32(),
        (weight) => weight + stroke.points.length,
        ifAbsent: () => stroke.points.length.toDouble(),
      );
    }
    if (distribution.isEmpty) return null;
    final entry = distribution.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return Color(entry.key);
  }

  /// 正在绘制选区过程中的点（未完成）。
  final List<Offset> _selectionDraft = [];

  /// 选区草稿（只读，供渲染层实时预览矩形/套索轮廓）。
  List<Offset> get selectionDraft => _selectionDraft;

  /// 剪贴板：复制/粘贴选中的笔画。
  List<Stroke>? _clipboard;

  /// 变换开始前的图层快照（移动/缩放/旋转期间记录，供撤销恢复）。
  List<Layer>? _transformBefore;

  bool get hasSelection => _selection.polygon.length >= 3;
  bool get hasSelectedStrokes => _selection.selectedStrokeIndices.isNotEmpty;

  /// 开始绘制选区（工具按下时调用）。
  void beginSelection(Offset canvasPoint) {
    _selectionDraft
      ..clear()
      ..add(canvasPoint);
    tickFrame();
  }

  /// 延伸选区（拖动过程中调用）。
  void extendSelection(Offset canvasPoint) {
    if (_selectionTool == SelectionTool.rect) {
      // 矩形选区：只需记录起点与当前点，由绘制层实时画出矩形。
      if (_selectionDraft.isEmpty) _selectionDraft.add(canvasPoint);
      // 保持起点不变，追加当前点（用于渲染）。
      _selectionDraft
        ..removeRange(1, _selectionDraft.length)
        ..add(canvasPoint);
    } else {
      // 套索选区：逐点追加，形成自由多边形。
      _selectionDraft.add(canvasPoint);
    }
    tickFrame(); // 拖动中高频更新：只重绘画布上的选区轮廓。
  }

  /// 结束选区：由草稿生成正式选区，并做笔画命中检测。
  void endSelection() {
    if (_selectionDraft.isEmpty) {
      _selection = const Selection();
      notifyListeners();
      return;
    }

    // 矩形选区：草稿为"起点+当前点"两个点，展开为 4 顶点多边形。
    // 套索选区：草稿为自由点列，至少 3 点才能构成区域。
    if (_selectionTool == SelectionTool.rect && _selectionDraft.length >= 2) {
      final a = _selectionDraft.first;
      final b = _selectionDraft.last;
      final polygon = [a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy)];
      _selection = Selection(
        polygon: polygon,
        selectedStrokeIndices: _hitTestStrokes(polygon),
      );
    } else if (_selectionTool == SelectionTool.lasso &&
        _selectionDraft.length >= 3) {
      final polygon = List.of(_selectionDraft);
      _selection = Selection(
        polygon: polygon,
        selectedStrokeIndices: _hitTestStrokes(polygon),
      );
    } else {
      // 草稿不构成有效选区（矩形只有单点 / 套索少于 3 点）。
      _selection = const Selection();
    }
    _selectionDraft.clear();
    notifyListeners();
  }

  /// 命中检测：返回选区多边形命中的当前图层笔画索引。
  ///
  /// 除了采样点落在内部，也检测笔画线段与套索边界的交叉，避免一条只含两个
  /// 端点的长线“穿过选区却选不中”。
  List<int> _hitTestStrokes(List<Offset> polygon) {
    final strokes = currentLayer.strokes;
    final result = <int>[];
    for (var i = 0; i < strokes.length; i++) {
      final points = strokes[i].points;
      if (points.any((point) => _pointInPolygon(point.offset, polygon)) ||
          _strokeIntersectsPolygon(points, polygon)) {
        result.add(i);
      }
    }
    return result;
  }

  static bool _strokeIntersectsPolygon(
    List<StrokePoint> points,
    List<Offset> polygon,
  ) {
    if (points.length < 2) return false;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1].offset;
      final b = points[i].offset;
      for (var edge = 0; edge < polygon.length; edge++) {
        final c = polygon[edge];
        final d = polygon[(edge + 1) % polygon.length];
        if (_segmentsIntersect(a, b, c, d)) return true;
      }
    }
    return false;
  }

  static bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    double cross(Offset p, Offset q, Offset r) =>
        (q.dx - p.dx) * (r.dy - p.dy) - (q.dy - p.dy) * (r.dx - p.dx);
    final abC = cross(a, b, c);
    final abD = cross(a, b, d);
    final cdA = cross(c, d, a);
    final cdB = cross(c, d, b);
    const epsilon = 1e-8;
    if (abC.abs() < epsilon && abD.abs() < epsilon) {
      final overlapX =
          math.max(math.min(a.dx, b.dx), math.min(c.dx, d.dx)) <=
          math.min(math.max(a.dx, b.dx), math.max(c.dx, d.dx));
      final overlapY =
          math.max(math.min(a.dy, b.dy), math.min(c.dy, d.dy)) <=
          math.min(math.max(a.dy, b.dy), math.max(c.dy, d.dy));
      return overlapX && overlapY;
    }
    return (abC >= 0) != (abD >= 0) && (cdA >= 0) != (cdB >= 0);
  }

  /// 射线法判断点是否在多边形内。
  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      final intersects =
          (a.dy > point.dy) != (b.dy > point.dy) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (intersects) inside = !inside;
    }
    return inside;
  }

  /// 清除选区。
  void clearSelection() {
    if (_selection.polygon.isEmpty && _selectedDocumentImageId == null) return;
    _selection = const Selection();
    _selectedDocumentImageId = null;
    notifyListeners();
  }

  /// 平移选中的笔画（拖拽移动）。
  void moveSelectedStrokes(Offset delta) {
    if (!hasSelectedStrokes) return;
    _ensureTransformBefore();
    _transformSelected((p) => p + delta);
  }

  /// 缩放选中的笔画（围绕选区中心）。
  void scaleSelectedStrokes(double factor) {
    if (!hasSelectedStrokes) return;
    _ensureTransformBefore();
    final c = _selectedStrokeCenter();
    _transformSelected((p) => c + (p - c) * factor);
  }

  /// 旋转选中的笔画（围绕选区中心，角度为弧度）。
  void rotateSelectedStrokes(double radians) {
    if (!hasSelectedStrokes) return;
    _ensureTransformBefore();
    final c = _selectedStrokeCenter();
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    _transformSelected((p) {
      final dx = p.dx - c.dx, dy = p.dy - c.dy;
      return Offset(c.dx + dx * cosA - dy * sinA, c.dy + dx * sinA + dy * cosA);
    });
  }

  /// 已选笔画的实际外接框中心。手势套索可画得很大，因此不能把套索包围盒
  /// 中心误用为变换锚点，否则用户会感到缩放、旋转“漂移”。
  Offset _selectedStrokeCenter() {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final index in _selection.selectedStrokeIndices) {
      final stroke = currentLayer.strokes[index];
      for (final point in stroke.points) {
        minX = math.min(minX, point.x);
        minY = math.min(minY, point.y);
        maxX = math.max(maxX, point.x);
        maxY = math.max(maxY, point.y);
      }
    }
    if (!minX.isFinite) return _selection.center;
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  /// 记录变换前的图层快照（首次变换时调用一次）。
  void _ensureTransformBefore() {
    _transformBefore ??= _snapshotLayers();
  }

  /// 对选中的笔画统一应用坐标变换（保持宽度/颜色不变）。
  ///
  /// 注意：变换不产生新的历史条目（供拖拽过程中反复调用），
  /// 需要撤销时由调用方在拖拽结束后 push 一次历史（见 endTransform）。
  void _transformSelected(Offset Function(Offset) transform) {
    final indices = _selection.selectedStrokeIndices;
    final strokes = currentLayer.strokes;
    for (final i in indices.reversed) {
      final old = strokes[i];
      final newPoints = old.points.map((p) {
        final t = transform(p.offset);
        return StrokePoint(t.dx, t.dy, p.pressure);
      }).toList();
      strokes[i] = Stroke(
        points: newPoints,
        color: old.color,
        width: old.width,
        type: old.type,
        opacity: old.opacity,
      );
    }
    _document.touch();
    _invalidateLayer(currentLayer.id);
    notifyListeners();
  }

  /// 变换结束：把"变换前快照 → 当前状态"记入历史（拖拽/滑块松手后调用一次）。
  void endTransform() {
    final before = _transformBefore;
    if (before == null) return;
    _transformBefore = null;
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
  }

  /// 删除选中的笔画。
  void deleteSelectedStrokes() {
    if (!hasSelectedStrokes) return;
    final before = _snapshotLayers();
    final indices = _selection.selectedStrokeIndices;
    for (final i in indices.reversed) {
      currentLayer.strokes.removeAt(i);
    }
    _document.touch();
    _selection = const Selection();
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _invalidateLayer(currentLayer.id);
    notifyListeners();
  }

  /// 复制选中的笔画到剪贴板（内部副本，不修改图层）。
  void copySelectedStrokes() {
    if (!hasSelectedStrokes) return;
    _clipboard = [
      for (final i in _selection.selectedStrokeIndices)
        _copyStroke(currentLayer.strokes[i]),
    ];
  }

  /// 粘贴剪贴板中的笔画到当前图层（在原位置基础上整体偏移，避免覆盖原件）。
  void pasteClipboard() {
    final clip = _clipboard;
    if (clip == null || clip.isEmpty) return;
    final before = _snapshotLayers();
    // 固定偏移量：粘贴内容出现在原内容的右下方向，肉眼可见且不遮挡。
    const delta = Offset(20, 20);
    for (final stroke in clip) {
      currentLayer.strokes.add(_offsetStroke(stroke, delta));
    }
    _document.touch();
    _selection = const Selection();
    _pushHistory(HistoryEntry(before: before, after: _snapshotLayers()));
    _invalidateLayer(currentLayer.id);
    notifyListeners();
  }

  Stroke _copyStroke(Stroke s) => Stroke(
    points: [for (final p in s.points) StrokePoint(p.x, p.y, p.pressure)],
    color: s.color,
    width: s.width,
    type: s.type,
    opacity: s.opacity,
  );

  /// 把笔画整体平移指定偏移（保留原形状，用于粘贴）。
  Stroke _offsetStroke(Stroke s, Offset delta) {
    return Stroke(
      points: [
        for (final p in s.points)
          StrokePoint(p.x + delta.dx, p.y + delta.dy, p.pressure),
      ],
      color: s.color,
      width: s.width,
      type: s.type,
      opacity: s.opacity,
    );
  }

  // ---------------- 生命周期 ----------------

  /// 释放所有位图资源（页面销毁时必须调用）。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final cache in _caches.values) {
      cache.dispose();
    }
    _caches.clear();
    _temporaryInkTicker?.cancel();
    _temporaryInkTicker = null;
    _temporaryInks.clear();
    _temporaryLasers.clear();
    for (final image in _documentImages.values) {
      image.dispose();
    }
    _documentImages.clear();
    _loadingDocumentImageIds.clear();
    super.dispose();
  }
}
