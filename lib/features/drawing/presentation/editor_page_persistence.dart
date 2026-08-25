part of 'editor_page.dart';

// 编辑器自动保存/导出域（O1 拆分）：定时自动保存与各格式导出
// 包装方法从 editor_page.dart 移出为 extension；行为零变化。

/// 编辑器自动保存/导出域（拆分自 editor_page.dart）。
extension _EditorPagePersistence on _EditorPageState {
  void _scheduleAutosave() {
    _viewModel.scheduleAutosave();
  }

  /// 执行自动保存：独立画作 → 工程文件 + 缩略图；笔记本页面 → 由上级回调落盘。
  Future<void> _doAutosave() async {
    // 笔记本页面模式：onChanged 已由 NotebookViewPage 负责保存。
    if (widget.page != null) return;
    final storage = widget.docStorage;
    final doc = _controller.document;
    if (storage == null) return;
    if (_autosaving) {
      _autosaveQueued = true;
      return _autosaveCompletion?.future ?? Future<void>.value();
    }

    _autosaving = true;
    final completion = Completer<void>();
    _autosaveCompletion = completion;
    try {
      do {
        _autosaveQueued = false;
        // StorageService 在调用时立即编码不可变快照；后续笔画不会改写此版本。
        await storage.save(doc);
        // 文档 JSON 是数据完整性的第一优先级。关闭中控制器可能已释放，
        // 因此只跳过可再生的缩略图，不跳过正文保存。
        if (!_closingEditor) {
          final png = await _controller.renderToPng(scale: 0.2);
          if (png != null) await storage.saveThumbnail(doc.id, png);
        }
      } while (_autosaveQueued);
      // 保存成功：清除未保存标记（借鉴 Saber markLastChangeAsSaved）。
      _controller.markSaved();
      completion.complete();
    } catch (e, stackTrace) {
      debugPrint('自动保存失败: $e\n$stackTrace');
      // 将失败记录到日志但不向防抖 Timer 抛出未处理异常；后续一次内容变更
      // 仍可重新触发保存，避免单次 I/O 故障永久阻断该文档。
      completion.complete();
    } finally {
      _autosaving = false;
      if (identical(_autosaveCompletion, completion)) {
        _autosaveCompletion = null;
      }
    }
  }

  /// 导出当前画布为 PNG（用户选择保存位置）。
  /// 复制 PNG 到剪贴板（委托给 [EditorExporter]，逻辑见 editor_exporter.dart）。
  Future<void> _copyPngToClipboard() => _exporter.copyPngToClipboard();

  /// 导出当前画布为 PNG（委托给 [EditorExporter]）。
  Future<void> _exportPng() => _exporter.exportPng();

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 导出当前画布为 PDF（委托给 [EditorExporter]，含 notebook 分支）。
  Future<void> _exportPdf() => _exporter.exportPdf();

  /// 导出画布为 SVG（委托给 [EditorExporter]；片段生成见 svg_exporter.dart）。
  Future<void> _exportSvg() => _exporter.exportSvg();

  /// 导出 Word 兼容文档（委托给 [EditorExporter]）。
  Future<void> _exportWordCompatibleRtf() => _exporter.exportWordCompatibleRtf();

  /// 导出页面文字为 Markdown/TXT（委托给 [EditorExporter]）。
  Future<void> _exportText() => _exporter.exportText();

  /// 视图缓存的键：笔记本页面按页面 id，独立画布按文档 id。
  String get _viewCacheKey => widget.page != null
      ? 'page:${widget.page!.id}'
      : 'doc:${_controller.document.id}';

  /// 正常返回编辑器前强制写入并等待落盘，防止 800ms 防抖尚未触发就退出。
  Future<bool> _flushBeforePop() async {
    await _viewModel.saveNow();
    return true;
  }

  /// 首次布局时把画布适配到视口（居中显示、按比例缩放）。
  ///
  /// 若该文档/笔记页在 LRU 视图缓存中有记录，则恢复上次的缩放与平移
  /// （重开笔记回到上次位置），否则首次进入时居中适配。
  void _initViewport(Size viewportSize) {
    if (_viewportInitialized) return;
    _viewportInitialized = true;

    final cached = ViewTransformCache.restore(_viewCacheKey);
    if (cached != null) {
      _controller.setViewport(
        scale: cached.scale,
        translation: cached.offset,
      );
      setState(() {});
      return;
    }

    final bounds = _controller.documentBounds;
    if (bounds == null || bounds.isEmpty) {
      setState(() {});
      return;
    }
    final vpW = viewportSize.width;
    final vpH = viewportSize.height;
    final docW = bounds.width;
    final docH = bounds.height;
    final scaleX = vpW / docW;
    final scaleY = vpH / docH;
    final targetScale = (scaleX < 1 || scaleY < 1)
        ? (math.min(scaleX, scaleY) * 0.9).clamp(0.1, 1.0)
        : 1.0;
    final scaledCenter = Offset(
      (docW * targetScale) / 2 - bounds.center.dx * targetScale,
      (docH * targetScale) / 2 - bounds.center.dy * targetScale,
    );
    _controller.setViewport(
      scale: targetScale,
      translation: scaledCenter,
    );
    setState(() {});
  }
}
