import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Paint, FilterQuality, Rect;

import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/application/doc_command_context.dart';
import 'package:drawing_notes_app/features/drawing/application/document_image_cache.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_edit_history.dart';
import 'package:drawing_notes_app/features/drawing/application/document_object_editing_session.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_selection_session.dart';
import 'package:drawing_notes_app/features/drawing/application/stroke_input_session.dart';
import 'package:drawing_notes_app/features/drawing/application/color_sampling_service.dart';
import 'package:drawing_notes_app/features/drawing/application/layer_render_cache_coordinator.dart';
import 'package:drawing_notes_app/features/drawing/application/layer_editing_session.dart';
import 'package:drawing_notes_app/features/drawing/application/object_eraser_session.dart';
import 'package:drawing_notes_app/features/drawing/application/document_transaction.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_viewport.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/application/temporary_ink_session.dart';
import 'package:drawing_notes_app/features/drawing/rendering/ink_layer_painter.dart';
import 'package:drawing_notes_app/features/drawing/rendering/layer_compositor.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_renderer.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_renderer.dart';

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
part 'drawing_controller_objects.dart';
part 'drawing_controller_selection.dart';
part 'drawing_controller_render.dart';
part 'drawing_controller_history.dart';

class DrawingController extends ChangeNotifier
    implements
        DocCommandContext,
        DocumentObjectEditingHost,
        LayerEditingHost,
        StrokeSelectionEditingHost,
        StrokeSelectionInteractionHost,
        StrokeInputHost {
  DrawingController(this._document) {
    _temporaryInkSession = TemporaryInkSession(onFrameTick: tickFrame);
    _strokeInputSession = StrokeInputSession(this);
    _documentImageCache = DocumentImageCache(
      onImageAvailable: tickFrame,
      isOwnerDisposed: () => _disposed,
    );
    _renderCacheCoordinator = LayerRenderCacheCoordinator(
      document: _document,
      onRenderUpdated: _applyNotify,
      isOwnerDisposed: () => _disposed,
    );
    _documentObjectEditingSession = DocumentObjectEditingSession(this);
    _layerEditingSession = LayerEditingSession(this);
    _strokeSelectionEditingSession = StrokeSelectionEditingSession(this);
    _strokeSelectionInteractionSession = StrokeSelectionInteractionSession(
      this,
    );
  }

  final DrawingDocument _document;

  @override
  DrawingDocument get document => _document;

  late final DocumentImageCache _documentImageCache;

  /// 取得文档图片的已解码位图；首次访问会异步加载并在完成后刷新画布。
  ///
  /// 解码缓存只保存运行时资源，JSON 仍只持久化离线文件路径，因此关闭重开后
  /// 仍可按需恢复且不会把大图二进制写入工程文件。
  ui.Image? documentImage(DocumentImageItem item) =>
      _documentImageCache.imageFor(item);

  /// 使单个文档图片的缓存位图失效（裁剪重写文件后调用，画布下次绘制
  /// 按需重新解码新内容）。
  void invalidateDocumentImage(String imageId) =>
      _documentImageCache.invalidate(imageId);

  /// 已销毁标记：dispose 后拒绝一切变更与通知（防止异步回调越界）。

  /// 受保护成员 notifyListeners 的转发包装（供 extension 使用）。
  void _applyNotify() => notifyListeners();

  /// 对象编辑会话使用的通知、历史、选区与缓存协作入口。
  @override
  void notifyChanged() => _applyNotify();

  @override
  void pushCommand(DocCommand command) => _pushCommand(command);

  @override
  Future<void> invalidateLayer(String layerId, {Rect? region}) =>
      _invalidateLayer(layerId, region: region);

  @override
  void rebuildCacheMap() => _rebuildCacheMap();

  @override
  Future<void> rebuildAll() => _rebuildAll();

  @override
  void setCurrentLayerIndexForRestore(int value) {
    _currentLayerIndex = value;
  }

  @override
  void setCurrentLayerIndexForLayerEdit(int value) {
    _currentLayerIndex = value;
  }

  @override
  void pushLayerSnapshot(List<Layer> before, List<Layer> after) {
    _pushHistory(HistoryEntry(before: before, after: after));
  }

  @override
  void addLayerCache(Layer layer) => _addLayerCache(layer);

  @override
  void removeLayerCache(String layerId) => _removeLayerCache(layerId);

  @override
  DrawingSelectionSession get selectionSession => _selectionSession;

  @override
  void requestFrame() => tickFrame();

  @override
  BrushType get strokeTool => _tool;

  @override
  Color get strokeColor => _color;

  @override
  double get strokeSize => currentSize;

  @override
  void addTemporaryMarker(Stroke stroke) =>
      _temporaryInkSession.addMarker(stroke);

  @override
  void addTemporaryLaser(Stroke stroke, DateTime startedAt) =>
      _temporaryInkSession.addLaser(stroke, startedAt);

  @override
  Future<void> commitRecognizedShape(Stroke stroke, PageShapeItem shape) async {
    _document.shapes.add(shape);
    _document.touch();
    _pushCommand(
      ReplaceStrokeWithShapeCommand(this, _currentLayerIndex, stroke, shape),
    );
    await _invalidateLayer(currentLayer.id);
    notifyListeners();
  }

  @override
  Future<void> commitPersistentStroke(Stroke stroke) async {
    currentLayer.strokes.add(stroke);
    _document.touch();
    _pushCommand(AddStrokeCommand(this, _currentLayerIndex, stroke));
    final region = StrokeRenderer.strokeBounds(stroke);
    await _invalidateLayer(currentLayer.id, region: region);
    notifyListeners();
  }

  @override
  Selection get strokeSelection => _selectionSession.selection;

  @override
  void replaceStrokeSelection(Selection value) {
    _selectionSession.selection = value;
    _selectionSession.invalidateCenter();
  }

  @override
  void clearStrokeSelection() => _selectionSession.clearSelection();

  /// 图片、形状及混合对象的选择和手势中间态由独立会话持有。
  late final DocumentObjectEditingSession _documentObjectEditingSession;

  /// 图层增删、排序、合并和清空的快照编排由独立会话持有。
  late final LayerEditingSession _layerEditingSession;

  /// 已选笔画的变换、剪贴板和快照提交由独立会话持有。
  late final StrokeSelectionEditingSession _strokeSelectionEditingSession;

  /// 矩形/套索草稿完成与笔画命中由独立会话持有。
  late final StrokeSelectionInteractionSession
  _strokeSelectionInteractionSession;
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
  @override
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
  @override
  int get currentLayerIndex => _currentLayerIndex;
  set currentLayerIndex(int value) {
    if (value >= 0 && value < _document.layers.length) {
      _currentLayerIndex = value;
      notifyListeners();
    }
  }

  @override
  Layer get currentLayer => _document.layers[_currentLayerIndex];

  // ---------------- 视口变换 ----------------

  final DrawingViewport _viewport = DrawingViewport();

  /// 画布缩放比例（1.0 = 实际大小）。
  double get viewScale => _viewport.scale;
  set viewScale(double value) => _viewport.scale = value;

  /// 画布在视口中的平移偏移（画布中心相对视口中心的位移）。
  Offset get viewOffset => _viewport.offset;
  set viewOffset(Offset value) => _viewport.offset = value;

  /// 画布旋转角度（弧度，Phase 7 双指旋转用）。
  double get viewRotation => _viewport.rotation;
  set viewRotation(double value) => _viewport.rotation = value;

  /// 画布文档中心（缩放/旋转的基准点）。
  Offset get _canvasCenter => _document.size.center(Offset.zero);

  /// 把视图坐标（像素）转换为画布逻辑坐标。
  ///
  /// 变换模型（与 CanvasPainter 严格互逆）：
  ///   view = R(rot) · (scale · (p - center)) + center + offset
  ///   逆：p = R(-rot) · (view - center - offset) / scale + center

  /// 把画布坐标转换为视图坐标。

  // ---------------- 图层渲染缓存 ----------------

  late final LayerRenderCacheCoordinator _renderCacheCoordinator;

  /// 重建缓存索引（图层增删后调用）。
  ///
  /// 注意：被移除的缓存必须释放位图，否则 ui.Image 泄漏。
  void _rebuildCacheMap() => _renderCacheCoordinator.rebuildCacheMap();

  /// 注册新建图层的空缓存。
  void _addLayerCache(Layer layer) => _renderCacheCoordinator.addLayer(layer);

  /// 删除图层时释放其关联位图缓存。
  void _removeLayerCache(String layerId) =>
      _renderCacheCoordinator.removeLayer(layerId);

  /// 标记图层内容/属性变化，触发异步重建缓存。
  ///
  /// [region] 非空时执行增量脏矩形重建：只重绘该区域内的笔画，
  /// 区域外内容保持不变（性能优化，避免整层反复光栅化）。
  Future<void> _invalidateLayer(String layerId, {Rect? region}) =>
      _renderCacheCoordinator.invalidateLayer(layerId, region: region);

  /// 为绘制提供图层位图视图列表（自底向上）。
  List<LayerPaintView> get paintViews => _renderCacheCoordinator.paintViews;

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
      // M12 修复：橡皮擦（BlendMode.clear）必须作用于"仅本图层内容"。
      // 此前 opacity=1 时直接在主画布上绘制，clear 会把主画布连同
      // 纸面背景一起清穿，露出底层黑色（表现为"橡皮擦画出黑色线条"）。
      // 统一 saveLayer 隔离后，clear 只清除本图层墨迹，露出纸面。
      //
      // U2 优化（2026-09-02，P1-8）：saveLayer 是每层每帧一次的全屏
      // 离屏合成，只在确有必要（半透明层或含橡皮擦）时建立；普通不
      // 透明纯书写层的 srcOver 直接落在主画布上，视觉完全等价。
      final needsIsolation =
          layer.opacity < 1 ||
          strokes.any((stroke) => stroke.type == BrushType.eraser);
      if (needsIsolation) {
        canvas.saveLayer(
          bounds,
          Paint()..color = Color.fromRGBO(0, 0, 0, layer.opacity),
        );
      }
      InkLayerPainter.paintStrokes(canvas, bounds, strokes);
      if (needsIsolation) {
        canvas.restore();
      }
    }
  }

  // ---------------- 笔画绘制 ----------------

  /// 原始笔画的活动状态、采样和提交分支由独立会话持有。
  late final StrokeInputSession _strokeInputSession;

  /// 当前正在绘制中的笔画（未提交到图层，仅用于实时预览）。
  Stroke? get activeStroke => _strokeInputSession.activeStroke;

  /// 临时高亮与激光尾迹的运行时生命周期管理器。
  late final TemporaryInkSession _temporaryInkSession;

  /// 临时荧光笔开关。开启后笔画仅短暂显示，不写入页面数据、历史或导出。
  @override
  bool get temporaryMarkerEnabled =>
      _temporaryInkSession.temporaryMarkerEnabled;
  set temporaryMarkerEnabled(bool value) {
    if (_temporaryInkSession.temporaryMarkerEnabled == value) return;
    _temporaryInkSession.temporaryMarkerEnabled = value;
    notifyListeners();
  }

  /// 尚在淡出期的临时高亮笔，供画布在矢量图层之上直接绘制。
  List<({Stroke stroke, double opacity})> get temporaryMarkerStrokes =>
      _temporaryInkSession.markerStrokes;

  /// 激光尾迹的可见片段。首点索引随时间前移，实现从起笔端逐段消退。
  List<({Stroke stroke, int firstPointIndex, double opacity})>
  get temporaryLaserStrokes => _temporaryInkSession.laserStrokes;

  /// 是否正在绘制。
  bool get isDrawing => _strokeInputSession.isDrawing;

  /// 整笔橡皮擦的运行时手势会话与形状擦除设置。
  final ObjectEraserSession _objectEraserSession = ObjectEraserSession();

  /// 被擦除的标准形状（问题3）：整笔/透明模式的擦除开关。
  ///
  /// 两个开关分别控制整笔模式（[EraserMode.stroke]）与透明模式
  /// （[EraserMode.pixel]）是否擦除标准形状。
  bool get eraserCanEraseShapesStroke =>
      _objectEraserSession.canEraseShapesStroke;
  bool get eraserCanEraseShapesPixel =>
      _objectEraserSession.canEraseShapesPixel;
  set eraserCanEraseShapesStroke(bool value) {
    if (_objectEraserSession.canEraseShapesStroke == value) return;
    _objectEraserSession.canEraseShapesStroke = value;
    notifyListeners();
  }

  set eraserCanEraseShapesPixel(bool value) {
    if (_objectEraserSession.canEraseShapesPixel == value) return;
    _objectEraserSession.canEraseShapesPixel = value;
    notifyListeners();
  }

  /// 开始对象橡皮擦手势。调用方只在 [EraserMode.stroke] 下调用。
  void beginObjectErase() => _objectEraserSession.begin();

  /// 擦除以 [canvasPoint] 为中心、以橡皮擦半径命中的整条笔画。
  ///
  /// 会话负责对象命中与增量记录；控制器负责文档时间戳、受影响图层缓存
  /// 刷新和 UI 通知，确保连续手势仍只在结束时产生一条撤销记录。
  bool eraseStrokesAt(Offset canvasPoint) {
    final step = _objectEraserSession.eraseAt(
      _document,
      canvasPoint,
      eraserSize: _eraserSize,
      mode: _eraserMode,
    );
    if (!step.changed) return false;
    _document.touch();
    for (final layerIndex in step.changedLayerIndices) {
      unawaited(_invalidateLayer(_document.layers[layerIndex].id));
    }
    notifyListeners();
    return true;
  }

  /// 提交一个对象橡皮擦手势的统一撤销记录（增量命令，零整层拷贝）。
  void endObjectErase() {
    final result = _objectEraserSession.consumeResult();
    if (result == null) return;
    _pushCommand(
      EraseStrokesCommand(
        this,
        result.removedStrokes,
        removedShapes: result.removedShapes,
      ),
    );
    notifyListeners();
  }

  /// 取消对象橡皮擦手势；如已经移除对象则还原（按增量记录插回）。
  void cancelObjectErase() {
    final result = _objectEraserSession.consumeResult();
    if (result == null) return;
    EraseStrokesCommand(
      this,
      result.removedStrokes,
      removedShapes: result.removedShapes,
    ).undo();
  }

  /// 开始一笔：创建活动笔画。
  void startStroke(Offset canvasPoint, {double pressure = 1.0}) =>
      _strokeInputSession.startStroke(canvasPoint, pressure: pressure);

  /// 延伸当前笔画（追加采样点）。
  void extendStroke(Offset canvasPoint, {double pressure = 1.0}) =>
      _strokeInputSession.extendStroke(canvasPoint, pressure: pressure);

  /// 取消当前未提交笔画。
  ///
  /// 用于双指缩放或掌托策略判定为误触时的安全回退。取消动作不会修改图层、
  /// 历史栈、保存点或文档时间戳，只刷新活动笔画预览。
  void cancelActiveStroke() => _strokeInputSession.cancelActiveStroke();

  /// 结束一笔：提交到当前图层并记录撤销历史。
  Future<void> endStroke() => _strokeInputSession.endStroke();

  /// 笔画命令撤销/重做后的统一处理：先同步通知（按钮/状态立即刷新），
  /// 再重建该图层位图（完成后再次通知更新画面）。
  /// 供命令类（document_commands.dart）调用的公开包装方法。
  ///
  /// 命令类与控制器分属不同文件，无法访问私有成员
  /// （`_restoreLayers`/`_document`/`_afterStrokeUndoRedo`），
  /// 因此提供等价的公开入口，行为完全一致（R5 拆分）。
  @override
  void restoreLayersSnapshot(List<Layer> snapshot) => _restoreLayers(snapshot);

  @override
  void touchDocument() {
    _editHistory.markDirty();
    _document.touch();
  }

  /// 是否有未保存的修改（借鉴 Saber EditorHistory 的保存状态跟踪，
  /// 见 docs/AUDIT_READ_5_PROJECTS_2026-08-15.md）。
  ///
  /// 任何内容变更（命令入栈/触摸文档）都会置脏；自动保存成功后调用
  /// [markSaved] 清除。可用于标题栏未保存标记与退出前提示。
  bool get isDirty => _editHistory.isDirty;

  /// 标记当前状态为"已保存"（自动保存成功后调用）。
  void markSaved() => _editHistory.markSaved();

  @override
  Future<void> afterStrokeUndoRedo(int layerIndex) =>
      _afterStrokeUndoRedo(layerIndex);

  /// 把由手绘识别转出的形状撤销回原笔画。供命令对象调用。
  @override
  void undoRecognizedShape(int layerIndex, Stroke stroke, PageShapeItem shape) {
    _document.shapes.remove(shape);
    _document.layers[layerIndex].strokes.add(stroke);
    _document.touch();
    unawaited(_afterStrokeUndoRedo(layerIndex));
  }

  /// 重新把原笔画替换为已识别形状。供命令对象调用。
  @override
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

  Future<void> _rebuildAll() => _renderCacheCoordinator.rebuildAll();

  // ---------------- 撤销 / 重做（命令模式） ----------------

  /// 历史栈上限：防止长时间会话导致内存无限增长。
  /// 超出上限时丢弃最旧的记录（与主流绘图软件行为一致）。
  static const int maxHistoryEntries = 60;

  /// 命令栈、重做游标和保存状态由独立协作者维护。
  late final DocumentEditHistory _editHistory = DocumentEditHistory(
    maxEntries: maxHistoryEntries,
  );

  bool get canUndo => _editHistory.canUndo;
  bool get canRedo => _editHistory.canRedo;

  /// 记录一条命令。
  ///
  /// 若当前处于历史中间位置（即刚刚撤销过若干步），
  /// 则先丢弃被撤销的"重做分支"，再追加新命令——
  /// 这是绘图类软件的标准行为：撤销后画新内容，旧分支不再可重做。

  // ---------------- 吸管取色 ----------------

  /// 从画布当前位置取色（读取合成位图像素）。
  ///
  /// 实现：把文档整体渲染到离屏图片，再读取该点像素。
  /// 返回 null 表示取色失败（越界或读取异常）。

  /// 无限画布的实际内容边界（笔画与几何形状），用于导出和局部合成。
  /// 空画布保留一个适中的默认导出区域，避免生成 0×0 文件。

  /// 把整个文档（含透明度）绘制到指定 Canvas 上（供导出/取色复用）。

  /// 生成用于显示/导出的形状视图。绑定箭头在此按当前目标几何投影端点，
  /// 不会在普通绘制中写回文档，故可确保屏幕与导出一致且不制造隐式历史。

  /// 把整个文档渲染为 PNG 字节（Phase 6 导出功能）。
  ///
  /// [scale] 用于导出分辨率：1.0 = 画布实际大小，2.0 = 放大一倍。
  /// 返回 PNG 编码的字节；失败返回 null。

  // ---------------- 选区与变换（Phase 4） ----------------

  /// 选区工具、草稿、变换缓存和剪贴板的运行时会话。
  final DrawingSelectionSession _selectionSession = DrawingSelectionSession();

  /// 当前选区工具（none = 正常绘制）。
  SelectionTool get selectionTool => _selectionSession.tool;
  set selectionTool(SelectionTool value) {
    _selectionSession.setTool(value);
    notifyListeners();
  }

  /// 当前选区（多边形 + 命中笔画）。
  Selection get selection => _selectionSession.selection;

  /// 选区主色（对齐 Saber select.dart 的 getDominantStrokeColor）：
  /// 按笔画长度加权统计当前选中笔画的颜色，最“长”的颜色胜出，
  /// 用于"取主色/批量改色"时给出代表性颜色，避免被零星小笔画误导。
  Color? get dominantStrokeColor {
    final distribution = <int, double>{};
    for (final index in _selectionSession.selection.selectedStrokeIndices) {
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

  /// 选区草稿（只读，供渲染层实时预览矩形/套索轮廓）。
  List<Offset> get selectionDraft => _selectionSession.draft;

  bool get hasSelection => _selectionSession.hasSelection;
  bool get hasSelectedStrokes => _selectionSession.hasSelectedStrokes;

  /// 开始绘制选区（工具按下时调用）。

  // ---------------- 生命周期 ----------------

  /// App 后台/最小化时释放所有图层离屏位图（P1 修复 2026-09-06 外部专家
  /// 审计 #1）。只释放位图、保留缓存索引，返回前台懒重建，显著降低空载常驻。
  void releaseLayerBitmapsForBackground() {
    _renderCacheCoordinator.releaseForBackground();
  }

  /// 回前台后重建图层位图（懒重建：仅在必要时重光栅化）。
  Future<void> rebuildLayerBitmaps() => _renderCacheCoordinator.rebuildAll();

  /// 释放所有位图资源（页面销毁时必须调用）。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _renderCacheCoordinator.dispose();
    _temporaryInkSession.dispose();
    _documentImageCache.dispose();
    super.dispose();
  }
}
