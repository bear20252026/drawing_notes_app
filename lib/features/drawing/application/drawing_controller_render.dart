part of 'drawing_controller.dart';

// 渲染/导出域（O1 拆分）：视口坐标变换、矢量图层绘制、取色、
// 内容边界与 PNG 导出方法从 drawing_controller.dart 移出为
// extension；行为零变化。

/// 渲染/导出域（拆分自 drawing_controller.dart）。
extension DrawingControllerRenderOps on DrawingController {
  Offset viewToCanvas(Offset viewPoint) =>
      _viewport.viewToCanvas(viewPoint, canvasCenter: _canvasCenter);

  Offset canvasToView(Offset canvasPoint) =>
      _viewport.canvasToView(canvasPoint, canvasCenter: _canvasCenter);

  Future<Color?> pickColorAt(Offset canvasPoint) async {
    // 取色探针分辨率封顶（内存审计 2026-09-06）：此前每次取色都把整张
    // 文档按原始尺寸渲染（A4 ≈ 35MB 位图 + 35MB rawRgba 副本），吸管在
    // 画布上连续移动时 200ms 节流也架不住反复的 70MB 峰值。取色只需
    // 颜色不需清晰度，按 1024 长边等比缩放后采样。
    const maxProbeLongEdge = 1024.0;
    final docW = _document.width.toDouble();
    final docH = _document.height.toDouble();
    final probeScale = docW <= 0 || docH <= 0
        ? 1.0
        : math.min(1.0, maxProbeLongEdge / math.max(docW, docH));
    final probeW = math.max(1, (docW * probeScale).round());
    final probeH = math.max(1, (docH * probeScale).round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // Picture.toImage 按 1:1 光栅化不做缩放（与 LayerCompositor 同一教训
    // 2026-09-07）：必须先缩放画布，文档坐标的内容才会等比落进小探针位图；
    // 否则只截下页面左上角、采样坐标也与内容错位，吸管在分页画布上取色
    // 全错。
    canvas.scale(probeScale);
    _paintDocument(canvas);
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(probeW, probeH);
      final x = (canvasPoint.dx * probeScale).round().clamp(0, probeW - 1);
      final y = (canvasPoint.dy * probeScale).round().clamp(0, probeH - 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      // Q-1 拆分（2026-08-16）：取色纯计算委托 ColorSamplingService。
      return ColorSamplingService.colorFromRgbaBytes(bytes, probeW, x, y);
    } finally {
      // 无论成功/失败都释放位图，避免泄漏。
      image?.dispose();
      picture.dispose();
    }
  }

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

  void _paintDocument(
    ui.Canvas canvas, {
    Rect? bounds,
    Set<BrushType> excludedTypes = const {},
  }) {
    _paintLayers(canvas, bounds: bounds, excludedTypes: excludedTypes);
    _paintDocumentImages(canvas);
    _paintDocumentShapes(canvas);
  }

  /// 图层腿（矢量 or 已合成位图），`_paintDocument` 与导出腿共用。
  void _paintLayers(
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
      return;
    }
    for (final view in paintViews) {
      final image = view.image;
      if (image == null || !view.visible || view.opacity <= 0) continue;
      final paint = Paint()
        ..color = Color.fromRGBO(0, 0, 0, view.opacity)
        ..filterQuality = FilterQuality.high;
      // 图层位图可能按长边封顶光栅化（LayerCompositor，内存治理）：
      // 以位图实际尺寸为 src、文档尺寸为 dst 统一缩放绘制。
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(
          0,
          0,
          _document.width.toDouble(),
          _document.height.toDouble(),
        ),
        paint,
      );
    }
  }

  /// 图片按 zOrder 的绘制序（U2 同款短路：递增 zOrder 是常态，只有真的乱序
  /// 才拷贝排序，免去 `List.of` 分配与 O(n log n)）。
  List<DocumentImageItem> _imagesByZOrder() {
    final imageItems = _document.imageItems;
    for (var i = 1; i < imageItems.length; i++) {
      if (imageItems[i - 1].zOrder.compareTo(imageItems[i].zOrder) > 0) {
        return List.of(imageItems)
          ..sort((a, b) => a.zOrder.compareTo(b.zOrder));
      }
    }
    return imageItems;
  }

  void _drawDocumentImage(
    ui.Canvas canvas,
    DocumentImageItem item,
    ui.Image image,
  ) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(item.x, item.y, item.width, item.height),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  void _paintDocumentImages(ui.Canvas canvas) {
    for (final item in _imagesByZOrder()) {
      final image = documentImage(item);
      if (image == null) continue;
      _drawDocumentImage(canvas, item, image);
    }
  }

  /// 导出腿的图片绘制：逐张「解码→记录绘制→立即释放」，**不经过 LRU 缓存**。
  ///
  /// 修的是台账 2026-10-05（AW 第 5 条）那条静默缺图：`ensureLoaded` 只保证
  /// 「每张都尝试解码过」，整组字节超预算时后载入的淘汰先载入的，而渲染腿对
  /// 未驻留的图片直接 `continue` ⇒ 页面图片总量一大，导出产物就缺图，用户
  /// 全程无感知。逐张解码把「全部同时在场」降成「一次一张」，完整性不再依赖
  /// 预算装得下整组；解码尺寸按 [outputScale] 换算成该图在**输出光栅**里占的
  /// 长边再取档位（只升不降），导出多大就解多大。
  ///
  /// 已驻留的图片直接复用现成位图（不释放——它归缓存管）：导出不得为了走一遍
  /// 一次性解码把交互缓存里已有的结果再解一遍，反之也不得用 `imageFor` 探测，
  /// 那 miss 会当场发起整组并发解码，内存界就没了。
  Future<void> _paintDocumentImagesForExport(
    ui.Canvas canvas, {
    required double outputScale,
  }) async {
    for (final item in _imagesByZOrder()) {
      final ui.Image? image;
      final bool transient;
      if (_documentImageCache.isCached(item.id)) {
        final resident = documentImage(item);
        if (resident == null) continue;
        image = resident;
        transient = false;
      } else {
        image = await _documentImageCache.decodeForExport(
          item,
          maxLongEdge: ImageDecodeCap.exportTierFor(
            math.max(item.width, item.height) * outputScale,
          ),
        );
        if (image == null) continue;
        transient = true;
      }
      try {
        _drawDocumentImage(canvas, item, image);
      } finally {
        if (transient) image.dispose();
      }
    }
  }

  void _paintDocumentShapes(ui.Canvas canvas) {
    for (final shape in _document.shapes) {
      ShapeRenderer.drawDocumentShape(canvas, shapeForRendering(shape));
    }
  }

  /// 导出用的完整绘制腿：图层 → 图片（逐张解码）→ 形状，顺序与 `_paintDocument` 一致。
  Future<void> _paintDocumentForExport(
    ui.Canvas canvas, {
    Rect? bounds,
    Set<BrushType> excludedTypes = const {},
    required double outputScale,
  }) async {
    _paintLayers(canvas, bounds: bounds, excludedTypes: excludedTypes);
    await _paintDocumentImagesForExport(canvas, outputScale: outputScale);
    _paintDocumentShapes(canvas);
  }

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

  Future<Uint8List?> renderToPng({
    double scale = 1.0,
    Set<BrushType> excludedTypes = const {},
    int maxLongEdge = 4096,

    /// 渲染区域覆盖（v1.17.20 分页导出）：null = 按文档/内容包围盒；
    /// 传子矩形时只渲染该区域（世界坐标）。
    ui.Rect? renderBounds,
  }) async {
    final bounds =
        renderBounds ??
        (_document.infinite
            ? contentBounds()
            : Rect.fromLTWH(
                0,
                0,
                _document.width.toDouble(),
                _document.height.toDouble(),
              ));
    var w = (bounds.width * scale).round();
    var h = (bounds.height * scale).round();
    if (w <= 0 || h <= 0) return null;

    // 输出尺寸钳制（内存审计 2026-09-06，"瞬间 1GB"尖峰根因）：无限画布
    // 的 bounds 来自内容包围盒——一个误触落点在很远处（如 50000,50000）
    // 就会让包围盒爆炸，scale 0.2 的缩略图也会尝试 toImage(10000,10000)
    // （400MB），scale 1.0 的导出更是 10GB 级分配尝试。钳制：单边 ≤ 上限
    // 且总像素 ≤ 上限²，超限同比例缩小（内容几何不变，只降输出分辨率）。
    // [maxLongEdge] 供调用方按用途收紧（内存治理 2026-09-07）：自动保存
    // 缩略图只需首页网格显示，用 1024 上限后，画画期间每 5s 一次的缩略图
    // 再光栅化从最多 ~48MB 瞬时分配降到 ~3MB。
    final maxDim = maxLongEdge.clamp(64, 4096);
    final maxPixels = maxDim * maxDim;
    var effectiveScale = scale;
    final longestSide = math.max(w, h);
    if (longestSide > maxDim) {
      effectiveScale = scale * (maxDim / longestSide);
    }
    w = (bounds.width * effectiveScale).round().clamp(1, maxDim);
    h = (bounds.height * effectiveScale).round().clamp(1, maxDim);
    if (w * h > maxPixels) {
      final shrink = math.sqrt(maxPixels / (w * h));
      w = (w * shrink).round().clamp(1, maxDim);
      h = (h * shrink).round().clamp(1, maxDim);
    }
    effectiveScale = w / bounds.width;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // 白色纸面背景（导出图片以白纸为底）。
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = AppleColor.surfaceWhite,
    );
    canvas.scale(effectiveScale);
    canvas.translate(-bounds.left, -bounds.top);
    // 导出腿自带逐张解码（见 [_paintDocumentImagesForExport]）：这里不再
    // `ensureLoaded` 预热整组——预热完也不保证同时驻留，反而会把先解码的挤掉，
    // 最后由渲染腿静默 `continue` 成「产物缺图」。
    await _paintDocumentForExport(
      canvas,
      bounds: bounds,
      excludedTypes: excludedTypes,
      outputScale: effectiveScale,
    );
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
}
