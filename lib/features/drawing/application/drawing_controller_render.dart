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
        : math.min(
            1.0,
            maxProbeLongEdge / math.max(docW, docH),
          );
    final probeW = math.max(1, (docW * probeScale).round());
    final probeH = math.max(1, (docH * probeScale).round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    _paintDocument(canvas);
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(probeW, probeH);
      final x = (canvasPoint.dx * probeScale)
          .round()
          .clamp(0, probeW - 1);
      final y = (canvasPoint.dy * probeScale)
          .round()
          .clamp(0, probeH - 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      // Q-1 拆分（2026-08-16）：取色纯计算委托 ColorSamplingService。
      return ColorSamplingService.colorFromRgbaBytes(
        bytes,
        probeW,
        x,
        y,
      );
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
        // 图层位图可能按长边封顶光栅化（LayerCompositor，内存治理）：
        // 以位图实际尺寸为 src、文档尺寸为 dst 统一缩放绘制。
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
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
    final images = List.of(_document.imageItems)
      ..sort((a, b) => a.zOrder.compareTo(b.zOrder));
    for (final item in images) {
      final image = documentImage(item);
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
    var w = (bounds.width * scale).round();
    var h = (bounds.height * scale).round();
    if (w <= 0 || h <= 0) return null;

    // 输出尺寸钳制（内存审计 2026-09-06，"瞬间 1GB"尖峰根因）：无限画布
    // 的 bounds 来自内容包围盒——一个误触落点在很远处（如 50000,50000）
    // 就会让包围盒爆炸，scale 0.2 的缩略图也会尝试 toImage(10000,10000)
    // （400MB），scale 1.0 的导出更是 10GB 级分配尝试。钳制：单边 ≤ 4096
    // 且总像素 ≤ 4096²，超限同比例缩小（内容几何不变，只降输出分辨率）。
    const maxDim = 4096;
    const maxPixels = maxDim * maxDim;
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
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.scale(effectiveScale);
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
}
