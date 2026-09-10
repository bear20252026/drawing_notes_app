part of 'editor_page.dart';

// 编辑器命令注册域（O1 拆分）：统一命令注册表（快捷键面板自动
// 生成）从 editor_page.dart 移出为 extension；行为零变化。

/// 编辑器命令注册域（拆分自 editor_page.dart）。
extension _EditorPageCommands on _EditorPageState {
  void _registerCommands() {
    // i18n（E1 批 3）：命令标签按 locale 解析；keyword 保留 zh 混排输入辅助。
    final l10n = AppLocalizations.of(context);
    _commands
      ..register(
        EditorCommand(
          id: 'undo',
          label: l10n?.cmdUndo ?? '撤销',
          category: EditorCommandCategory.edit,
          keywords: const ['history', '返回'],
          shortcut: 'Ctrl/Cmd+Z',
          isAvailable: () => _controller.canUndo,
          run: _controller.undo,
        ),
      )
      ..register(
        EditorCommand(
          id: 'redo',
          label: l10n?.cmdRedo ?? '重做',
          category: EditorCommandCategory.edit,
          keywords: const ['history', '恢复'],
          shortcut: 'Ctrl/Cmd+Y 或 Ctrl/Cmd+Shift+Z',
          isAvailable: () => _controller.canRedo,
          run: _controller.redo,
        ),
      )
      ..register(
        EditorCommand(
          id: 'copy',
          label: l10n?.cmdCopySelection ?? '复制选中对象',
          category: EditorCommandCategory.edit,
          keywords: const ['clipboard', '复制'],
          shortcut: 'Ctrl/Cmd+C',
          isAvailable: () => _hasObjectSelection,
          run: _copySelectedElement,
        ),
      )
      ..register(
        EditorCommand(
          id: 'paste',
          label: l10n?.cmdPasteClipboard ?? '从剪贴板粘贴',
          category: EditorCommandCategory.edit,
          keywords: const ['clipboard', '粘贴', '文本', '图片'],
          shortcut: 'Ctrl/Cmd+V',
          run: _pasteFromClipboard,
        ),
      )
      ..register(
        EditorCommand(
          id: 'duplicate',
          label: l10n?.cmdDuplicateSelection ?? '复制并粘贴选中对象',
          category: EditorCommandCategory.edit,
          keywords: const ['duplicate', '副本'],
          shortcut: 'Ctrl/Cmd+D',
          isAvailable: () => _hasObjectSelection,
          run: () {
            _copySelectedElement();
            _pasteCopiedElement();
          },
        ),
      )
      ..register(
        EditorCommand(
          id: 'deleteSelection',
          label: l10n?.cmdDeleteSelection ?? '删除选中对象',
          category: EditorCommandCategory.edit,
          keywords: const ['delete', 'remove', '删除'],
          shortcut: 'Delete',
          isAvailable: () => _hasObjectSelection,
          run: _deleteSelectedItem,
        ),
      )
      ..register(
        EditorCommand(
          id: 'bold',
          label: l10n?.cmdBold ?? '加粗选中文字',
          category: EditorCommandCategory.format,
          keywords: const ['text', 'font', '粗体'],
          shortcut: 'Ctrl/Cmd+B',
          isAvailable: () => _selectedTextItem != null,
          run: _toggleSelectedTextBold,
        ),
      )
      ..register(
        EditorCommand(
          id: 'italic',
          label: l10n?.cmdItalic ?? '斜体选中文字',
          category: EditorCommandCategory.format,
          keywords: const ['text', 'font', '斜体'],
          shortcut: 'Ctrl/Cmd+I',
          isAvailable: () => _selectedTextItem != null,
          run: _toggleSelectedTextItalic,
        ),
      )
      ..register(
        EditorCommand(
          id: 'underline',
          label: l10n?.cmdUnderline ?? '下划线选中文字',
          category: EditorCommandCategory.format,
          keywords: const ['text', 'font', '下划线'],
          shortcut: 'Ctrl/Cmd+U',
          isAvailable: () => _selectedTextItem != null,
          run: () {
            final item = _selectedTextItem;
            if (item == null) return;
            _applyState(() => item.underline = !item.underline);
            _notifyChanged();
          },
        ),
      )
      ..register(
        EditorCommand(
          id: 'strikethrough',
          label: l10n?.cmdStrikethrough ?? '删除线选中文字',
          category: EditorCommandCategory.format,
          keywords: const ['text', 'font', '删除线'],
          shortcut: 'Ctrl/Cmd+Shift+X',
          isAvailable: () => _selectedTextItem != null,
          run: () {
            final item = _selectedTextItem;
            if (item == null) return;
            _applyState(() => item.strikethrough = !item.strikethrough);
            _notifyChanged();
          },
        ),
      )
      ..register(
        EditorCommand(
          id: 'alignText',
          label: l10n?.cmdCycleAlign ?? '循环切换文本对齐',
          category: EditorCommandCategory.format,
          keywords: const ['text', 'alignment', '对齐'],
          shortcut: 'Ctrl/Cmd+E',
          isAvailable: () => _selectedTextItem != null,
          run: _cycleSelectedTextAlign,
        ),
      )
      ..register(
        EditorCommand(
          id: 'fitCanvas',
          label: l10n?.cmdFitCanvas ?? '适应画布',
          category: EditorCommandCategory.view,
          keywords: const ['zoom', 'fit', '缩放'],
          shortcut: 'Shift+1',
          run: _fitToScreen,
        ),
      )
      ..register(
        EditorCommand(
          id: 'toggleGrid',
          label: l10n?.cmdToggleGrid ?? '显示或隐藏网格',
          category: EditorCommandCategory.view,
          keywords: const ['grid', '网格'],
          run: () => _applyState(() => _gridVisible = !_gridVisible),
        ),
      )
      ..register(
        EditorCommand(
          id: 'toggleGridSnap',
          label: l10n?.cmdToggleSnap ?? '切换网格吸附',
          category: EditorCommandCategory.view,
          keywords: const ['grid', 'snap', '吸附'],
          run: () => _applyState(() => _snapToGrid = !_snapToGrid),
        ),
      )
      ..register(
        EditorCommand(
          id: 'exportPng',
          label: '导出 PNG',
          category: EditorCommandCategory.export,
          keywords: const ['export', 'image', '图片'],
          run: _exportPng,
        ),
      )
      ..register(
        EditorCommand(
          id: 'exportPdf',
          label: '导出 PDF',
          category: EditorCommandCategory.export,
          keywords: const ['export', 'document', '文档'],
          run: _exportPdf,
        ),
      )
      ..register(
        EditorCommand(
          id: 'exportSvg',
          label: '导出 SVG',
          category: EditorCommandCategory.export,
          keywords: const ['export', 'vector', '矢量'],
          run: _exportSvg,
        ),
      )
      ..register(
        EditorCommand(
          id: 'exportWord',
          label: l10n?.cmdExportWord ?? '导出 Word 兼容文档',
          category: EditorCommandCategory.export,
          keywords: const ['export', 'word', 'rtf', '文档'],
          isAvailable: () => _isNotebookMode,
          run: _exportWordCompatibleRtf,
        ),
      );
  }
}
