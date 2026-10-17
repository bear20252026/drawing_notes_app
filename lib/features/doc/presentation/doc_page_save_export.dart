part of 'doc_page.dart';

// 保存与导出域（O1 拆分自 doc_page.dart）：脏通知、调度保存、状态标签、
// Markdown/HTML/PDF 导出与策略门。public API 与字段留在本体。行为零变化。

/// 保存/状态/导出域私有助手（拆分自 doc_page.dart）。
extension _DocPageSaveExport on _DocPageState {
  /// 编辑变为脏：显示"未保存"并交由 SaveScheduler 防抖自动保存。
  void _onEditorDirty() {
    _pendingChanges = true;
    if (mounted && _saveStatus != _SaveStatus.unsaved) {
      pageSetState(() => _saveStatus = _SaveStatus.unsaved);
    }
    _saveScheduler.markDirty();
  }

  /// 手动保存：立即落盘（保存中 → 已保存 由调度器回调驱动）。
  Future<void> _saveNow() async {
    if (mounted) pageSetState(() => _saveStatus = _SaveStatus.saving);
    await _saveScheduler.saveNow();
  }

  String _statusLabel() {
    final l10n = AppLocalizations.of(context);
    switch (_saveStatus) {
      case _SaveStatus.unsaved:
        return l10n?.docUnsaved ?? '未保存';
      case _SaveStatus.saving:
        return l10n?.docSaving ?? '保存中…';
      case _SaveStatus.saved:
        final t = _lastSavedAt;
        if (t == null) return l10n?.docSaved ?? '已保存';
        final time = formatClock(t);
        return l10n?.docSavedAt(time) ?? '已保存 $time';
    }
  }

  /// 通用导出：转换后经 [writeExportFile] 落盘，Snack 提示路径。
  Future<void> _export({
    required String extension,
    required String Function(NoteBlockDoc doc) convert,
    required String label,
  }) async {
    try {
      final doc = _editorKey.currentState?.currentDoc ?? _doc;
      final path = await writeExportFile(
        baseName: _docName(doc),
        extension: extension,
        content: convert(doc),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.docExportedTo(label, path) ??
                '已导出 $label：$path',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.docExportFailed ?? '导出失败，请重试',
          ),
        ),
      );
    }
  }

  /// 导出门禁（P1-M1）：md/html/pdf 均需白名单放行，fail-closed。
  ///
  /// 审计 2026-10-16 §21 新登记第 1 条：**原来这句是死分支**。[PolicyEngine
  /// .enforceCheck] 在 deny 时先抛 [PolicyDeniedException]，永远不返回
  /// `isAllowed == false`，所以 `if (!result.isAllowed)` 那段提示从没能执行过——
  /// 真被拒时异常从同步的 `_exportAllowed` 逃到菜单按钮上（用户看到的不是
  /// 「操作被策略拒绝」，是一次未捕获异常）。改成捕获，提示仍取既有 arb 键。
  bool _exportAllowed(String operation) {
    try {
      const PolicyEngine().enforceCheck(operation);
      return true;
    } on PolicyDeniedException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.docPolicyDenied(e.operation) ??
                  '操作被策略拒绝（$operation）',
            ),
          ),
        );
      }
      return false;
    }
  }

  /// 导出 Markdown / HTML / PDF（AFFiNE Export 对齐）。
  Future<void> _exportMarkdown() {
    if (!_exportAllowed('note.export.markdown')) return Future.value();
    return _export(
      extension: 'md',
      convert: noteBlockDocToMarkdown,
      label: 'Markdown',
    );
  }

  Future<void> _exportHtml() {
    if (!_exportAllowed('note.export.html')) return Future.value();
    return _export(
      extension: 'html',
      convert: noteBlockDocToHtml,
      label: 'HTML',
    );
  }

  Future<void> _exportPdf() {
    if (!_exportAllowed('note.export.pdf')) return Future.value();
    return _exportPdfBytes();
  }

  Future<void> _exportPdfBytes() async {
    final l10n = AppLocalizations.of(context);
    try {
      final doc = _editorKey.currentState?.currentDoc ?? _doc;
      final bytes = await noteBlockDocToPdf(
        doc,
        emptyDocLabel: l10n?.emptyDocPlaceholder ?? '（空文档）',
      );
      final path = await writeExportFileBytes(
        baseName: _docName(doc),
        extension: 'pdf',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.docExportedTo('PDF', path) ??
                '已导出 PDF：$path',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.docExportFailed ?? '导出失败，请重试',
          ),
        ),
      );
    }
  }

  void _persist(NoteBlockDoc doc) {
    // P0-H1：仅同步快照到页面状态；「已保存」状态与落盘一律由
    // SaveScheduler（await 写盘后的 onSaved）单一驱动，消除假已保存。
    pageSetState(() {
      _doc = doc;
    });
  }
}
