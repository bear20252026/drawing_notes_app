part of 'notebook_view_page.dart';

// 笔记页页面管理域（O1 拆分）：创建页、模板文字、收藏/打开/删除
// 页面方法从 notebook_view_page.dart 移出为 extension；行为零变化。

/// 笔记页页面管理域（拆分自 notebook_view_page.dart）。
extension _NotebookPageManage on _NotebookViewPageState {
  /// 打开放映页（跨 feature 跳转回调，S4b 接口化）：
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
          session: NotebookPageEditorSession(page),
          notebookAccessor: widget.storage,
          onChanged: onChanged,
          openPresentation: (context) => _openPresentation(context, page),
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
      content: NotebookPageTemplateStrategy.createContent(
        template: request.template,
        documentId: StorageService.newId(),
        documentTitle: '未命名页面',
        createdAt: DateTime.now(),
        nextTextItemId: () => NotebookStorage.newId('txt'),
      ),
      template: request.template,
    );
    _applyState(() => _notebook.pages.add(page));
    await _save();
    if (!mounted) return;
    await _openEditor(page: page, onChanged: _save);
    _applyState(() {}); // 返回后刷新
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
        page: srcPage,
        onChanged: () => widget.storage.save(srcNotebook),
      );
      _applyState(() {});
      return;
    }

    _applyState(() => page.lastOpenedAt = DateTime.now());
    await _save();
    if (!mounted) return;
    await _openEditor(page: page, onChanged: _save);
    _applyState(() {});
  }

  /// M4：将已有 NotebookPage 打开为块文档编辑器。
  ///
  /// 若该页面对应的块文档已存在则直接加载；否则用 [migrateNotebookPage]
  /// 从 NotebookPage 迁移一份 NoteBlockDoc 并缓存。
  /// 通过 onSave 回调将编辑后的文档持久化到 NoteBlockDocStore。
  Future<void> _openBlockDocFromPage(NotebookPage page) async {
    final store = blockDocStore;
    // 尝试加载已有块文档
    var doc = await store.loadDocument(page.id);
    if (doc == null) {
      // 不存在则从 NotebookPage 迁移并缓存
      doc = migrateNotebookPage(page);
      await store.saveDocument(doc);
    }
    if (!mounted) return;
    final noteDoc = doc; // 此时 doc 已被提升为非空
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocPage(
          document: noteDoc,
          blockDocStore: store,
          controller: DocController(
            onSave: (updatedDoc) async {
              await store.saveDocument(updatedDoc);
              // M12.5 根修：回写笔记本页（title/updatedAt）——块文档副本
              // 与源页保持同源一致，两处列表显示不再分叉。
              page.title = updatedDoc.title;
              page.updatedAt = updatedDoc.updatedAt;
              await widget.storage.save(_notebook);
            },
          ),
        ),
      ),
    );
  }

  /// M4：把 NotebookPage 的文本项迁移为 NoteBlockDoc。
  @visibleForTesting
  NoteBlockDoc migrateNotebookPage(NotebookPage page) {
    final blocks = <NoteBlock>[];
    // 标题作为 heading 块（level 1）
    if (page.title.isNotEmpty) {
      blocks.add(
        NoteBlock.headingBlock(
          NoteBlockDocStore.newId(),
          level: 1,
          text: page.title,
        ),
      );
    }
    // textItems 映射为 text blocks
    for (final item in page.textItems) {
      final text = item.text.trim();
      if (text.isEmpty) continue;
      blocks.add(NoteBlock.textBlock(NoteBlockDocStore.newId(), text: text));
    }
    // 若无文本内容，给一个空段落以便编辑
    if (blocks.isEmpty) {
      blocks.add(NoteBlock.textBlock(NoteBlockDocStore.newId(), text: ''));
    }
    return NoteBlockDoc(
      id: page.id,
      title: page.title,
      body: blocks,
      createdAt: page.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// 从其他笔记本引入页面（创建克隆引用，借鉴 Trilium 笔记克隆）。
  Future<void> _importPage() async {
    final notebooks = await widget.storage.listAll();
    if (!mounted) return;
    final others = notebooks.where((nb) => nb.id != _notebook.id).toList();
    if (others.isEmpty) {
      _showSnack('暂没有其他分页画布可引入');
      return;
    }
    // 第一步：选择源笔记本。
    final srcNb = await showDialog<Notebook>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择源分页画布'),
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
      _showSnack('该分页画布还没有页面');
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
          document: NotebookPageTemplateStrategy.createDocument(
            id: StorageService.newId(),
            title: '未命名页面',
          ), // 占位，实际内容从源实时加载
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
      case _NotebookMenuItem.bindUsb:
        _startBindUsb();
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
    // M12.5 根修：联动清理迁移副本（若曾以块文档方式打开过该页），
    // 避免已删除页面在首页/全部文档残留为幽灵条目。
    try {
      await blockDocStore.deleteDocument(page.id);
    } catch (_) {
      // 副本不存在或清理失败不阻断页面删除主流程。
    }
  }
}
