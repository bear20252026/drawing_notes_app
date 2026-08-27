import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Paint, FilterQuality, Rect;

import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/features/drawing/application/doc_command_context.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/selection_geometry_service.dart';
import 'package:drawing_notes_app/features/drawing/application/color_sampling_service.dart';
import 'package:drawing_notes_app/features/drawing/application/image_transform_service.dart';
import 'package:drawing_notes_app/features/drawing/application/document_transaction.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/application/temporary_markers.dart';
import 'package:drawing_notes_app/core/rendering/ink_layer_painter.dart';
import 'package:drawing_notes_app/core/rendering/layer_compositor.dart';
import 'package:drawing_notes_app/core/rendering/stroke_geometry_cache.dart';
import 'package:drawing_notes_app/core/rendering/shape_recognizer.dart';
import 'package:drawing_notes_app/core/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/core/rendering/shape_renderer.dart';
import 'package:drawing_notes_app/core/rendering/stroke_renderer.dart';

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

class DrawingController extends ChangeNotifier implements DocCommandContext {
  DrawingController(this._document) {
    _rebuildCacheMap();
  }

  final DrawingDocument _document;

  @override
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

  /// 已销毁标记：dispose 后拒绝一切变更与通知（防止异步回调越界）。

  /// 受保护成员 notifyListeners 的转发包装（供 extension 使用）。
  void _applyNotify() => notifyListeners();

  // ---- 通用几何工具（供选区/对象选择共享，静态方法）----
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
    // Q-1 拆分（2026-08-16）：相交判定委托 SelectionGeometryService。
    return SelectionGeometryService.segmentsIntersect(a, b, c, d);
  }

  /// 选中的文档形状/图片持久 ID 集合（统一对象选择）。
  final Set<String> _selectedDocumentShapeIds = <String>{};
  final Set<String> _selectedDocumentImageIds = <String>{};
  String? _selectedDocumentImageId;
  DocumentImageItem? _documentImageTransformBefore;
  String? _selectedDocumentShapeId;
  List<PageShapeItem>? _documentShapesTransformBefore;
  DocumentObjectsSnapshot? _documentObjectsTransformBefore;
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

  /// 把画布坐标转换为视图坐标。

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

  final List<TemporaryInk> _temporaryInks = <TemporaryInk>[];
  final List<TemporaryLaserInk> _temporaryLasers = <TemporaryLaserInk>[];
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
  bool get _eraserCanEraseShapes => _eraserMode == EraserMode.stroke
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
    if (changed &&
        (_objectEraseRemoved.isNotEmpty || _objectEraseShapes.isNotEmpty)) {
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
    // Q-1 拆分（2026-08-16）：点-线段距离委托 SelectionGeometryService。
    return SelectionGeometryService.distanceToSegment(point, a, b);
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
    _temporaryInks.add(TemporaryInk(stroke, DateTime.now()));
    _ensureTemporaryInkTicker();
  }

  void _addTemporaryLaser(Stroke stroke, DateTime startedAt) {
    _temporaryLasers.add(TemporaryLaserInk(stroke, startedAt));
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
  @override
  void restoreLayersSnapshot(List<Layer> snapshot) => _restoreLayers(snapshot);

  @override
  void touchDocument() {
    _isDirty = true;
    _document.touch();
  }

  /// 是否有未保存的修改（借鉴 Saber EditorHistory 的保存状态跟踪，
  /// 见 docs/AUDIT_READ_5_PROJECTS_2026-08-15.md）。
  ///
  /// 任何内容变更（命令入栈/触摸文档）都会置脏；自动保存成功后调用
  /// [markSaved] 清除。可用于标题栏未保存标记与退出前提示。
  bool _isDirty = false;

  /// 是否存在未保存的修改。
  bool get isDirty => _isDirty;

  /// 标记当前状态为"已保存"（自动保存成功后调用）。
  void markSaved() => _isDirty = false;

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

  /// 当前选区工具（none = 正常绘制）。
  SelectionTool _selectionTool = SelectionTool.none;
  SelectionTool get selectionTool => _selectionTool;
  set selectionTool(SelectionTool value) {
    _selectionTool = value;
    _selection = const Selection();
    _selectionCenterDirty = true;
    notifyListeners();
  }

  /// 当前选区（多边形 + 命中笔画）。
  Selection _selection = const Selection();
  Selection get selection => _selection;

  /// 选区中心缓存（P-1 修复 2026-08-15）：_selectedStrokeCenter 的
  /// O(N×M) 计算缓存，选区变化时置 dirty 失效（scale/rotate 围绕中心
  /// 变换中心不变——滑块连续拖动复用缓存免每次重算）。
  Offset? _selectionCenterCache;
  bool _selectionCenterDirty = true;

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
