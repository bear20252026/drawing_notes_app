part of 'editor_page.dart';

// 编辑器自动保存/导出域（O1 拆分）：定时自动保存与各格式导出
// 包装方法从 editor_page.dart 移出为 extension；行为零变化。

/// 编辑器自动保存/导出域（拆分自 editor_page.dart）。
extension _EditorPagePersistence on _EditorPageState {
  /// setState 的 lint 友好包装（extension 无法直接调用受保护成员）。
  void notify() {
    // ignore: invalid_use_of_protected_member
    setState(() {});
  }

  void _scheduleAutosave() {
    _viewModel.scheduleAutosave();
  }

  /// 保存当前画作：独立画布 → 工程文件 + 缩略图；笔记本页面 → 由上级回调落盘。
  ///
  /// 只负责“执行落盘”，失败时把异常向上抛出（交给 SaveScheduler 的重试/退避/
  /// 放弃策略处理）；防抖、串行化（飞行中补写）、退出兜底、通知合并在
  /// [SaveScheduler]（P0-3b）统一编排，此处不再内联“正在保存/补写”标记。
  Future<void> _persistArtwork() async {
    // 笔记本页面模式：onChanged 已由 NotebookViewPage 负责保存。
    if (widget.session != null) return;
    final storage = widget.docStorage;
    final doc = _controller.document;
    if (storage == null) return;
    // 「保存中」状态由 SaveScheduler.savingState 统一驱动（v1.17.20），
    // 覆盖手动保存与退出兜底路径，此处不再手工置位。
    // StorageService 在调用时立即编码不可变快照；后续笔画不会改写此版本。
    await storage.save(doc);
    // 文档 JSON 是数据完整性的第一优先级。关闭中控制器可能已释放，
    // 因此只跳过可再生的缩略图，不跳过正文保存。
    if (!_closingEditor) {
      // 缩略图长边限 1024（内存治理 2026-09-07）：首页网格最多 ~256px
      // 显示，1024 已留足余量；无限画布内容包围盒 × 0.2 仍可能达数千
      // 像素（~48MB 瞬时分配），画画期间每 5s 自动保存都会重放一次。
      final png = await _controller.renderToPng(scale: 0.2, maxLongEdge: 1024);
      if (png != null) await storage.saveThumbnail(doc.id, png);
    } else {
      // v1.17.20 退出路径缩略图后台补渲：退出只等文档 JSON 落盘（快），
      // 缩略图由后台队列按快照独立渲染，不再阻塞 pop。
      ThumbnailBackfill.submit(doc, storage);
    }
    if (mounted && !_closingEditor) {
      _canvasLastSavedAt = DateTime.now();
      notify();
    }
  }

  /// 重命名画布：更新标题并走自动保存调度（M12 命名持久化）。
  Future<void> _renameCanvas() async {
    final current = _controller.document.title;
    // controller 提到 builder 外创建、finally 统一释放（builder 内创建会
    // 随每次重建泄漏一个）。对话框返回（pop 即完成）后退出动画仍在跑，
    // 动画期间 TextField 重建会触碰 controller；捕获路由完全退出的时机，
    // 动画结束再释放。
    final controller = TextEditingController(text: current);
    var routeExited = Future<void>.value();
    String? name;
    try {
      name = await GlassDialog.show<String>(
        context: context,
        builder: (ctx) {
          routeExited = ModalRoute.of(ctx)!.completed;
          return AlertDialog(
            title: Text(
              AppLocalizations.of(context)?.renameCanvasTitle ?? '重命名画布',
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
            actions: AppleDialog.actions([
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.of(context)?.cancel ?? '取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                child: Text(
                  AppLocalizations.of(context)?.commonConfirm ?? '确定',
                ),
              ),
            ]),
          );
        },
      );
      await routeExited;
    } finally {
      controller.dispose();
    }
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == current) return;
    _controller.document.title = trimmed;
    _controller.notifyChanged();
    _scheduleAutosave();
  }

  /// 导出当前画布为 PNG（用户选择保存位置）。
  /// 复制 PNG 到剪贴板（委托给 [EditorExporter]，逻辑见 editor_exporter.dart）。
  Future<void> _copyPngToClipboard() => _exporter.copyPngToClipboard();

  /// 导出当前画布为 PNG（委托给 [EditorExporter]）。
  Future<void> _exportPng() => _exporter.exportPng();

  void _showSnack(String message) {
    if (!mounted) return;
    AppSnack.show(context, message);
  }

  /// 导出当前画布为 PDF（M12.5 二级面板）：先弹纸张/范围/质量面板，
  /// 确认后走 [EditorExporter.exportPdfWithOptions]（含 notebook 分支）。
  /// 旧直导逻辑保留在 exporter.exportPdf（命令面板兼容与回退）。
  Future<void> _exportPdf() async {
    final sessions = widget.allSessionsProvider?.call() ?? const [];
    final selection = await showPdfExportPanel(
      context,
      hasMultiplePages: widget.session != null && sessions.length > 1,
      pageCount: sessions.length,
      // v1.17.20：独立画布（含无限画布）才显示「布局」档位。
      showLayout: widget.session == null,
    );
    if (selection == null) return; // 用户取消
    if (!mounted) return;
    // v1.17.22：分页导出 = 切片预览确认 + 逐页进度（模态）；单页/笔记本
    // 走既有路径零变化。
    final isTiled =
        widget.session == null && selection.layout == PdfLayout.tiled;
    if (!isTiled) {
      await _exporter.exportPdfWithOptions(
        paper: selection.paper,
        quality: selection.quality,
        range: selection.range,
        layout: selection.layout,
      );
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<int>(0);
    var total = 0;
    unawaited(
      GlassDialog.show<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (context, done, _) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: AppleSpacing.md),
                Text(
                  done == 0
                      ? (AppLocalizations.of(context)?.pdfExporting ??
                            '正在导出 PDF…')
                      : (done >= total && total > 0
                            ? (AppLocalizations.of(
                                    context,
                                  )?.pdfExportComposing ??
                                  '正在合成 PDF…')
                            : (AppLocalizations.of(
                                    context,
                                  )?.pdfExportRenderingPage(done, total) ??
                                  '正在渲染第 $done / $total 页')),
                  style: AppleType.controlStyle(
                    Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await _exporter.exportPdfWithOptions(
        paper: selection.paper,
        quality: selection.quality,
        range: selection.range,
        layout: selection.layout,
        columnMajor: selection.columnMajor,
        footer: selection.footer,
        onProgress: (done, t) {
          total = t;
          progress.value = done;
        },
        confirmTiles: _confirmTileLayout,
      );
    } finally {
      if (navigator.canPop()) navigator.pop();
      progress.dispose();
    }
  }

  /// 分页导出前切片预览（v1.17.22）：网格化展示每页覆盖的世界区域与
  /// 页序号，用户确认后才进入逐页渲染。返回 false = 取消导出。
  Future<bool> _confirmTileLayout(List<ui.Rect> tiles) async {
    if (!mounted) return false;
    final choice = await GlassDialog.show<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)?.pdfTilePreviewTitle ?? '确认分页方式',
        ),
        content: SizedBox(
          width: 300,
          height: 340,
          child: CustomPaint(painter: PdfTilePreviewPainter(tiles: tiles)),
        ),
        actions: AppleDialog.actions([
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context)?.cancel ?? '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              AppLocalizations.of(
                    context,
                  )?.pdfTilePreviewConfirm(tiles.length) ??
                  '导出 ${tiles.length} 页',
            ),
          ),
        ]),
      ),
    );
    return choice ?? false;
  }

  /// 导出画布为 SVG（委托给 [EditorExporter]；片段生成见 svg_exporter.dart）。
  Future<void> _exportSvg() => _exporter.exportSvg();

  /// 导出 Word 兼容文档（委托给 [EditorExporter]）。
  Future<void> _exportWordCompatibleRtf() =>
      _exporter.exportWordCompatibleRtf();

  /// 导出页面文字为 Markdown/TXT（委托给 [EditorExporter]）。
  Future<void> _exportText() => _exporter.exportText();
}
