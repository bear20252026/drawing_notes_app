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
  ///
  /// U6 窄屏自适应：390dp 下右侧 7 个 action 会把 title 区压到 ~22px，
  /// 固定内容（保存状态 + 类型 Chip）放不下会溢出。按 title 区实际可用
  /// 宽度分级隐藏——<140px 只留标题，140~220px 加保存状态，≥220px 全显。
  /// （历史上 8 图标时 title 区为 0px 宽，内容整体不可见；0 宽容器不报
  /// 溢出，390dp 门禁测不出来——删一个图标后才第一次触发溢出报告。）
  ///
  /// R3 顶栏减负：<600dp 时图层/属性/全屏/深色阅读 4 个低频开关收进
  /// 主菜单顶部成组（带状态文案），顶栏只留撤销/重做/主菜单——390dp
  /// title 区从 22px 恢复到 ~200px，长标题可读。桌面宽屏零变化。
  AppBar _buildAppBar() {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return AppBar(
      title: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final isNote = _isNotebookMode;
          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final showStatus = w >= 140;
              final showChip = w >= 220;
              return Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _renameCanvas,
                      borderRadius: BorderRadius.circular(AppleRadius.xs),
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
                            // Flexible：极窄时图标随标题一起收缩，避免二级溢出。
                            Flexible(
                              child: Icon(
                                Icons.edit_rounded,
                                size: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (showStatus) ...[
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
                  ],
                  if (showChip) ...[
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
                ],
              );
            },
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
        // R3：窄屏收进主菜单（见 _buildMainMenuItems 顶部组）。
        if (!narrow) ...[
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
        ],
        // U6：快捷键帮助 AppBar 图标删除（与主菜单项重复），仅保留主菜单入口。
        // 右上角汉堡菜单（对齐 Excalidraw main-menu）
        PopupMenuButton<_MainMenuItem>(
          tooltip: AppLocalizations.of(context)?.editorMenu ?? '主菜单',
          icon: const Icon(Icons.menu),
          onSelected: _onMainMenuSelected,
          itemBuilder: (_) => _buildMainMenuItems(showPanelToggles: narrow),
        ),
      ],
    );
  }

  /// 主菜单项列表（纯数据驱动）。
  ///
  /// [showPanelToggles]：窄屏（R3）时为 true——图层/属性/全屏/深色阅读
  /// 4 个低频开关在主菜单顶部成组出现（顶栏已隐藏对应 action）。
  List<PopupMenuEntry<_MainMenuItem>> _buildMainMenuItems({
    bool showPanelToggles = false,
  }) {
    final l = AppLocalizations.of(context);
    return [
      if (showPanelToggles) ...[
        _mainMenuItem(
          _MainMenuItem.layers,
          icon: _layersVisible ? Icons.layers : Icons.layers_outlined,
          label: _layersVisible ? '隐藏图层' : '显示图层',
        ),
        _mainMenuItem(
          _MainMenuItem.inspector,
          icon: _inspectorVisible ? Icons.tune : Icons.tune_outlined,
          label: _inspectorVisible ? '隐藏属性' : '显示属性',
        ),
        _mainMenuItem(
          _MainMenuItem.fullscreen,
          icon: _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          label: _fullscreen ? '退出全屏' : '全屏模式',
        ),
        _mainMenuItem(
          _MainMenuItem.reading,
          icon: _readingInverted
              ? Icons.invert_colors_on_outlined
              : Icons.invert_colors_off_outlined,
          label: _readingInverted ? '关闭深色阅读' : '深色阅读（仅显示）',
        ),
        const PopupMenuDivider(),
      ],
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
