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
      // Q-1 拆分（2026-08-16）：取色纯计算委托 ColorSamplingService。
      return ColorSamplingService.colorFromRgbaBytes(
        bytes,
        _document.width,
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
        canvas.drawImage(image, Offset.zero, paint);
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
}
