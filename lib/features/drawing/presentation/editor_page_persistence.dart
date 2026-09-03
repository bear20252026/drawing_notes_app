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
    if (mounted) {
      _canvasSaving = true;
      notify();
    }
    // StorageService 在调用时立即编码不可变快照；后续笔画不会改写此版本。
    await storage.save(doc);
    // 文档 JSON 是数据完整性的第一优先级。关闭中控制器可能已释放，
    // 因此只跳过可再生的缩略图，不跳过正文保存。
    if (!_closingEditor) {
      final png = await _controller.renderToPng(scale: 0.2);
      if (png != null) await storage.saveThumbnail(doc.id, png);
    }
    if (mounted && !_closingEditor) {
      _canvasSaving = false;
      _canvasLastSavedAt = DateTime.now();
      notify();
    }
  }

  /// 重命名画布：更新标题并走自动保存调度（M12 命名持久化）。
  Future<void> _renameCanvas() async {
    final current = _controller.document.title;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: current);
        return AlertDialog(
          title: const Text('重命名画布'),
          content: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    );
    if (selection == null) return; // 用户取消
    if (!mounted) return;
    await _exporter.exportPdfWithOptions(
      paper: selection.paper,
      quality: selection.quality,
      range: selection.range,
    );
  }

  /// 导出画布为 SVG（委托给 [EditorExporter]；片段生成见 svg_exporter.dart）。
  Future<void> _exportSvg() => _exporter.exportSvg();

  /// 导出 Word 兼容文档（委托给 [EditorExporter]）。
  Future<void> _exportWordCompatibleRtf() =>
      _exporter.exportWordCompatibleRtf();

  /// 导出页面文字为 Markdown/TXT（委托给 [EditorExporter]）。
  Future<void> _exportText() => _exporter.exportText();
}
