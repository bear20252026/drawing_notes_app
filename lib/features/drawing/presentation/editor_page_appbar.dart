part of 'editor_page.dart';

// 编辑器顶栏/主菜单域（O1 拆分）：AppBar 与汉堡菜单从 editor_page.dart
// 移出为 extension；行为零变化。

/// 顶栏主菜单的单个小项工厂（DRY：统一头像/文本、紧凑排版）。
PopupMenuItem<_MainMenuItem> _mainMenuItem(
  _MainMenuItem value, {
  required IconData icon,
  required String label,
}) => PopupMenuItem<_MainMenuItem>(
  value: value,
  child: ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(label),
  ),
);

/// 编辑器顶栏/主菜单域（拆分自 editor_page.dart）。
extension _EditorPageAppBar on _EditorPageState {
  /// 顶栏：题目 + 撤销/重做 + 画布空间/侧栏/全屏/深色/帮助 + 主菜单。
  AppBar _buildAppBar() {
    return AppBar(
      title: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final isNote = _isNotebookMode;
          return Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _renameCanvas,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _controller.document.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.edit_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 保存状态（未保存 / 保存中… / 已保存 HH:mm）
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  _canvasStatusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _canvasStatusColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  isNote ? Icons.article_outlined : Icons.all_out,
                  size: 16,
                ),
                label: Text(isNote ? '分页笔记' : '无限画布'),
              ),
            ],
          );
        },
      ),
      actions: [
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => IconButton(
            tooltip: AppLocalizations.of(context)?.editorUndo ?? '撤销',
            icon: const Icon(Icons.undo),
            onPressed: _commands.find('undo')?.available ?? false
                ? () => _commands.run('undo')
                : null,
          ),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => IconButton(
            tooltip: AppLocalizations.of(context)?.editorRedo ?? '重做',
            icon: const Icon(Icons.redo),
            onPressed: _commands.find('redo')?.available ?? false
                ? () => _commands.run('redo')
                : null,
          ),
        ),

        // 画布空间与侧栏控制：将低频管理面板改为按需展开。
        IconButton(
          tooltip: _layersVisible ? '隐藏图层' : '显示图层',
          icon: Icon(_layersVisible ? Icons.layers : Icons.layers_outlined),
          isSelected: _layersVisible,
          onPressed: _toggleLayers,
        ),
        IconButton(
          tooltip: _inspectorVisible ? '隐藏属性' : '显示属性',
          icon: Icon(_inspectorVisible ? Icons.tune : Icons.tune_outlined),
          isSelected: _inspectorVisible,
          onPressed: _toggleInspector,
        ),
        IconButton(
          tooltip: _fullscreen ? '退出全屏' : '全屏模式',
          icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
          onPressed: _toggleFullscreen,
        ),
        IconButton(
          tooltip: _readingInverted ? '关闭深色阅读' : '深色阅读（仅显示）',
          icon: Icon(
            _readingInverted
                ? Icons.invert_colors_on_outlined
                : Icons.invert_colors_off_outlined,
          ),
          isSelected: _readingInverted,
          onPressed: _toggleReadingInverted,
        ),
        // 快捷键帮助面板（借鉴 Notes 快捷键文档化）
        IconButton(
          tooltip: AppLocalizations.of(context)?.editorShortcutsHelp ?? '快捷键帮助',
          icon: const Icon(Icons.help_outline),
          onPressed: _showShortcutHelp,
        ),
        // 右上角汉堡菜单（对齐 Excalidraw main-menu）
        PopupMenuButton<_MainMenuItem>(
          tooltip: AppLocalizations.of(context)?.editorMenu ?? '主菜单',
          icon: const Icon(Icons.menu),
          onSelected: _onMainMenuSelected,
          itemBuilder: (_) => _buildMainMenuItems(),
        ),
      ],
    );
  }

  /// 主菜单项列表（纯数据驱动）。
  List<PopupMenuEntry<_MainMenuItem>> _buildMainMenuItems() {
    final l = AppLocalizations.of(context);
    return [
      _mainMenuItem(
        _MainMenuItem.clearCanvas,
        icon: Icons.delete_sweep_outlined,
        label: l?.editorClearCanvas ?? '清空画布',
      ),
      const PopupMenuDivider(),
      _mainMenuItem(
        _MainMenuItem.copyPng,
        icon: Icons.content_copy,
        label: l?.editorCopyPng ?? '复制 PNG 到剪贴板',
      ),
      _mainMenuItem(
        _MainMenuItem.exportPng,
        icon: Icons.image_outlined,
        label: l?.editorExportPng ?? '导出 PNG',
      ),
      _mainMenuItem(
        _MainMenuItem.exportSvg,
        icon: Icons.ios_share,
        label: l?.editorExportSvg ?? '导出 SVG',
      ),
      _mainMenuItem(
        _MainMenuItem.exportPdf,
        icon: Icons.picture_as_pdf_outlined,
        label: l?.editorExportPdf ?? '导出 PDF',
      ),
      _mainMenuItem(
        _MainMenuItem.exportJson,
        icon: Icons.data_object,
        label: l?.editorExportJson ?? '导出 JSON',
      ),
      _mainMenuItem(
        _MainMenuItem.exportPptx,
        icon: Icons.slideshow_outlined,
        label: l?.editorExportPptx ?? '导出 PPTX',
      ),
      if (_isNotebookMode)
        _mainMenuItem(
          _MainMenuItem.exportWord,
          icon: Icons.article_outlined,
          label: l?.editorExportWord ?? '导出 Word 兼容文档',
        ),
      _mainMenuItem(
        _MainMenuItem.exportText,
        icon: Icons.description_outlined,
        label: '导出文本',
      ),
      const PopupMenuDivider(),
      _mainMenuItem(
        _MainMenuItem.commandPalette,
        icon: Icons.keyboard_command_key,
        label: '命令面板',
      ),
      _mainMenuItem(
        _MainMenuItem.chart,
        icon: Icons.bar_chart,
        label: '图表（粘贴数据）',
      ),
      _mainMenuItem(
        _MainMenuItem.presentation,
        icon: Icons.slideshow,
        label: '幻灯片演示',
      ),
      _mainMenuItem(_MainMenuItem.stats, icon: Icons.query_stats, label: '统计'),
      _mainMenuItem(
        _MainMenuItem.library,
        icon: Icons.library_books_outlined,
        label: '形状库（图书馆）',
      ),
      _mainMenuItem(
        _MainMenuItem.shortcuts,
        icon: Icons.keyboard,
        label: '快捷键帮助',
      ),
      // 切换无限画布（问题8）：仅独立画布可用。
      if (!_isNotebookMode)
        _mainMenuItem(
          _MainMenuItem.toggleInfinite,
          icon: _controller.document.infinite ? Icons.all_out : Icons.crop_free,
          label: _controller.document.infinite ? '切换为固定纸张' : '切换为无限画布',
        ),
    ];
  }
}
