part of 'notebook_view_page.dart';

// 笔记页页面管理域（O1 拆分）：创建页、模板文字、收藏/打开/删除
// 页面方法从 notebook_view_page.dart 移出为 extension；行为零变化。

/// 笔记页页面管理域（拆分自 notebook_view_page.dart）。
extension _NotebookPageManage on _NotebookViewPageState {
  /// 打开放映页（跨 feature 跳转契约回调，S4b 接口化）：
  /// 由本页（notes 侧）实现跳转，drawing 侧只经回调调用，不依赖本 UI。
  Future<void> _openPresentation(BuildContext context, NotebookPage page) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PresentationPage(
          textItems: page.textItems,
          imageItems: page.imageItems,
          shapes: page.shapes,
        ),
      ),
    );
  }

  Future<void> _openEditor({
    required Notebook notebook,
    required NotebookPage page,
    required VoidCallback onChanged,
  }) {
    final builder = widget.editorPageBuilder;
    if (builder == null) {
      _showSnack('编辑器尚未由应用层装配');
      return Future<void>.value();
    }
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => builder(
          notebook: notebook,
          page: page,
          notebookAccessor: widget.storage,
          onChanged: onChanged,
          openPresentation: _openPresentation,
        ),
      ),
    );
  }

  Future<void> _createPage() async {
    final request = await showDialog<_NewPageRequest>(
      context: context,
      builder: (ctx) => const _CreatePageDialog(),
    );
    if (request == null || request.title.trim().isEmpty) return;

    final page = NotebookPage(
      id: NotebookStorage.newId('pg'),
      title: request.title.trim(),
      document: _newDocument(template: request.template),
      template: request.template,
      textItems: _templateTextItems(request.template),
    );
    _applyState(() => _notebook.pages.add(page));
    await _save();
    if (!mounted) return;
    await _openEditor(notebook: _notebook, page: page, onChanged: _save);
    _applyState(() {}); // 返回后刷新
  }

  /// 生成新页面的默认画布文档。
  ///
  /// 必须返回真实文档（非 null）：页面保存/进入编辑器都依赖 [NotebookPage.document]，
  /// 若为 null 会导致保存时抛空指针异常、无法跳转（曾出现过的严重缺陷）。
  DrawingDocument _newDocument({PageTemplate template = PageTemplate.blank}) {
    // 使用与独立画作一致的默认尺寸（A4 比例 210:297 近似）。
    // “无限白板”不在此处承诺为真实无限画布；当前渲染器仍是固定坐标纸面。
    return DrawingDocument(
      id: StorageService.newId(),
      title: '未命名页面',
      width: 2480,
      height: 3508,
      paperType: template.paperType,
    );
  }

  List<PageTextItem> _templateTextItems(PageTemplate template) {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    PageTextItem item(
      String id,
      double x,
      double y,
      String text, {
      double size = 24,
      bool bold = false,
    }) => PageTextItem(
      id: id,
      x: x,
      y: y,
      text: text,
      fontSize: size,
      bold: bold,
    );

    switch (template) {
      case PageTemplate.meeting:
        return [
          item(
            NotebookStorage.newId('txt'),
            110,
            90,
            '会议主题',
            size: 38,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            170,
            '日期：$date    参与者：',
            size: 22,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            310,
            '议题',
            size: 28,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            1060,
            '决策',
            size: 28,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            1810,
            '行动项（负责人 / 截止日）',
            size: 28,
            bold: true,
          ),
        ];
      case PageTemplate.cornell:
        return [
          item(
            NotebookStorage.newId('txt'),
            110,
            90,
            '主题 / 课程',
            size: 34,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            220,
            '线索与问题',
            size: 24,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            720,
            220,
            '笔记',
            size: 24,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            2920,
            '总结',
            size: 24,
            bold: true,
          ),
        ];
      case PageTemplate.planner:
        return [
          item(
            NotebookStorage.newId('txt'),
            110,
            90,
            '本周计划',
            size: 38,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            240,
            '最重要的三件事',
            size: 26,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            1280,
            '日程与待办',
            size: 26,
            bold: true,
          ),
          item(
            NotebookStorage.newId('txt'),
            110,
            2450,
            '复盘与下周准备',
            size: 26,
            bold: true,
          ),
        ];
      case PageTemplate.blank:
      case PageTemplate.lined:
      case PageTemplate.grid:
      case PageTemplate.dot:
      case PageTemplate.whiteboard:
        return const [];
    }
  }

  Future<void> _toggleFavorite(NotebookPage page) async {
    _applyState(() => page.favorite = !page.favorite);
    await _save();
  }

  /// 打开已有页面。
  ///
  /// 克隆引用页面（[NotebookPage.cloneOf] 非空）：实时加载源笔记本的源页面，
  /// 以源页面打开编辑器，修改写回源页面——一处修改，所有克隆端同步生效
  /// （借鉴 Trilium 笔记克隆，非复制粘贴）。
  Future<void> _openPage(NotebookPage page) async {
    final ref = page.cloneOf;
    if (ref != null) {
      final srcNotebook = await widget.storage.load(ref.notebookId);
      if (srcNotebook == null || !mounted) return;
      final srcPage = srcNotebook.pages
          .where((p) => p.id == ref.pageId)
          .firstOrNull;
      if (srcPage == null) {
        _showSnack('引用的源页面不存在（可能已被删除）');
        return;
      }
      await _openEditor(
        notebook: srcNotebook,
        page: srcPage,
        onChanged: () => widget.storage.save(srcNotebook),
      );
      _applyState(() {});
      return;
    }

    _applyState(() => page.lastOpenedAt = DateTime.now());
    await _save();
    if (!mounted) return;
    await _openEditor(notebook: _notebook, page: page, onChanged: _save);
    _applyState(() {});
  }

  /// 从其他笔记本引入页面（创建克隆引用，借鉴 Trilium 笔记克隆）。
  Future<void> _importPage() async {
    final notebooks = await widget.storage.listAll();
    if (!mounted) return;
    final others = notebooks.where((nb) => nb.id != _notebook.id).toList();
    if (others.isEmpty) {
      _showSnack('暂没有其他笔记本可引入');
      return;
    }
    // 第一步：选择源笔记本。
    final srcNb = await showDialog<Notebook>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择源笔记本'),
        children: [
          for (final nb in others)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(nb),
              child: Text(nb.title),
            ),
        ],
      ),
    );
    if (srcNb == null || !mounted) return;
    if (srcNb.pages.isEmpty) {
      _showSnack('该笔记本还没有页面');
      return;
    }
    // 第二步：选择页面。
    final srcPage = await showDialog<NotebookPage>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要引入的页面'),
        children: [
          for (final p in srcNb.pages)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p),
              child: Text(p.title),
            ),
        ],
      ),
    );
    if (srcPage == null || !mounted) return;

    // 创建克隆引用条目（不复制内容）。
    _applyState(() {
      _notebook.pages.add(
        NotebookPage(
          id: NotebookStorage.newId('pg'),
          title: '↪ ${srcPage.title}',
          document: _newDocument(), // 占位，实际内容从源实时加载
          cloneOf: CloneRef(notebookId: srcNb.id, pageId: srcPage.id),
        ),
      );
    });
    await _save();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onNotebookMenuSelected(_NotebookMenuItem item) {
    switch (item) {
      case _NotebookMenuItem.importPage:
        _importPage();
      case _NotebookMenuItem.importText:
        _importText();
      case _NotebookMenuItem.importPdf:
        _importPdf();
      case _NotebookMenuItem.security:
        _setPassword();
      case _NotebookMenuItem.organize:
        _macroMovePages();
    }
  }

  /// 删除页面（二次确认）。
  Future<void> _deletePage(NotebookPage page) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除页面'),
        content: Text('确定删除页面「${page.title}」吗？其中的手写与文字内容将一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _applyState(() => _notebook.pages.removeWhere((p) => p.id == page.id));
    await _save();
  }
}
