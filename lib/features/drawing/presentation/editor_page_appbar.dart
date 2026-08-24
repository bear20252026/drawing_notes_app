part of 'editor_page.dart';

/// AppBar 构建域（拆分自 editor_page.dart build 方法）。
extension _EditorPageAppBar on _EditorPageState {
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final isNote = _isNotebookMode;
          return Row(
            children: [
              Expanded(
                child: Text(
                  _controller.document.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
        // 撤销/重做
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

        // 图层/属性面板切换
        IconButton(
          tooltip: _layersVisible ? '隐藏图层' : '显示图层',
          icon: Icon(
            _layersVisible ? Icons.layers : Icons.layers_outlined,
          ),
          isSelected: _layersVisible,
          onPressed: () =>
              setState(() => _layersVisible = !_layersVisible),
        ),
        IconButton(
          tooltip: _inspectorVisible ? '隐藏属性' : '显示属性',
          icon: Icon(
            _inspectorVisible ? Icons.tune : Icons.tune_outlined,
          ),
          isSelected: _inspectorVisible,
          onPressed: () =>
              setState(() => _inspectorVisible = !_inspectorVisible),
        ),

        // 全屏/阅读反相
        IconButton(
          tooltip: _fullscreen ? '退出全屏' : '全屏模式',
          icon: Icon(
            _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          ),
          onPressed: () => setState(() => _fullscreen = !_fullscreen),
        ),
        IconButton(
          tooltip: _readingInverted ? '关闭深色阅读' : '深色阅读（仅显示）',
          icon: Icon(
            _readingInverted
                ? Icons.invert_colors_on_outlined
                : Icons.invert_colors_off_outlined,
          ),
          isSelected: _readingInverted,
          onPressed: () =>
              setState(() => _readingInverted = !_readingInverted),
        ),

        // 快捷键帮助
        IconButton(
          tooltip: AppLocalizations.of(context)?.editorShortcutsHelp ?? '快捷键帮助',
          icon: const Icon(Icons.help_outline),
          onPressed: _showShortcutHelp,
        ),

        // 主菜单
        _buildMainMenuButton(context),
      ],
      // 窄屏溢出处理：AppBar actions 超出时自动收入溢出菜单
      flexibleSpace: null,
    );
  }

  PopupMenuButton<_MainMenuItem> _buildMainMenuButton(BuildContext context) {
    return PopupMenuButton<_MainMenuItem>(
      tooltip: AppLocalizations.of(context)?.editorMenu ?? '主菜单',
      icon: const Icon(Icons.menu),
      onSelected: _onMainMenuSelected,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _MainMenuItem.clearCanvas,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_sweep_outlined),
            title: Text(AppLocalizations.of(context)?.editorClearCanvas ?? '清空画布'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _MainMenuItem.copyPng,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.content_copy),
            title: Text(AppLocalizations.of(context)?.editorCopyPng ?? '复制 PNG 到剪贴板'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.exportPng,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.image_outlined),
            title: Text(AppLocalizations.of(context)?.editorExportPng ?? '导出 PNG'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.exportSelectionPng,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.crop_free),
            title: Text('导出选区 PNG'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.exportSvg,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.ios_share),
            title: Text(AppLocalizations.of(context)?.editorExportSvg ?? '导出 SVG'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.exportPdf,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text(AppLocalizations.of(context)?.editorExportPdf ?? '导出 PDF'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.exportJson,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.data_object),
            title: Text(AppLocalizations.of(context)?.editorExportJson ?? '导出 JSON'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.exportPptx,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.slideshow_outlined),
            title: Text(AppLocalizations.of(context)?.editorExportPptx ?? '导出 PPTX'),
          ),
        ),
        if (_isNotebookMode)
          PopupMenuItem(
            value: _MainMenuItem.exportWord,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.article_outlined),
              title: Text(AppLocalizations.of(context)?.editorExportWord ?? '导出 Word 兼容文档'),
            ),
          ),
        PopupMenuItem(
          value: _MainMenuItem.exportText,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.description_outlined),
            title: Text('导出文本'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _MainMenuItem.commandPalette,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.keyboard_command_key),
            title: Text('命令面板'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.chart,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.bar_chart),
            title: Text('图表（粘贴数据）'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.presentation,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.slideshow),
            title: Text('幻灯片演示'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.stats,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.query_stats),
            title: Text('统计'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.library,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.library_books_outlined),
            title: Text('形状库（图书馆）'),
          ),
        ),
        PopupMenuItem(
          value: _MainMenuItem.shortcuts,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.keyboard),
            title: Text('快捷键帮助'),
          ),
        ),
        // 切换无限画布（问题8）：仅独立画布可用。
        if (!_isNotebookMode)
          PopupMenuItem(
            value: _MainMenuItem.toggleInfinite,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _controller.document.infinite
                    ? Icons.all_out
                    : Icons.crop_free,
              ),
              title: Text(
                _controller.document.infinite
                    ? '切换为固定纸张'
                    : '切换为无限画布',
              ),
            ),
          ),
      ],
    );
  }
}
