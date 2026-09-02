part of 'home_page.dart';

// 首页 Tab 布局域（行数门禁拆分）：_buildBody / 三个 Tab / 打开笔记本等。
// 从 home_page.dart 移出为 extension（行为零变化），保持主文件 < 500 逻辑行。

extension _HomePageTabs on _HomePageState {
  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _refresh, child: const Text('重试')),
          ],
        ),
      );
    }
    return TabBarView(children: [_buildDrawingsTab(), _buildNotesTab()]);
  }

  // ---------------- 画布 Tab（W1 归位：无限画布 + 分页画布整本） ----------------

  Widget _buildDrawingsTab() {
    final hasCanvas = _documents.isNotEmpty;
    final hasNotebook = _notebooks.isNotEmpty;
    if (!hasCanvas && !hasNotebook) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('还没有画布，点击右下角按钮新建一个吧'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (hasCanvas) ...[
            const SliverToBoxAdapter(child: _CanvasSectionHeader('无限画布')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.pagePadding,
                8,
                AppDesign.pagePadding,
                0,
              ),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 256,
                      childAspectRatio: 0.82,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _DrawingCard(
                    meta: _documents[i],
                    documentStorage: _docStorage,
                    onTap: () => _openDrawing(_documents[i]),
                    onDelete: () => _deleteDrawing(_documents[i]),
                    onPasswordAction: () =>
                        _showDrawingPasswordSheet(_documents[i]),
                  ),
                  childCount: _documents.length,
                ),
              ),
            ),
          ],
          if (hasNotebook) ...[
            const SliverToBoxAdapter(
              child: _CanvasSectionHeader('分页画布'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.pagePadding,
                8,
                AppDesign.pagePadding,
                0,
              ),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 256,
                      childAspectRatio: 0.82,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _NotebookCard(
                    notebook: _notebooks[i],
                    subtitle: _notebookSubtitle(_notebooks[i]),
                    onTap: () => _openNotebook(_notebooks[i]),
                  ),
                  childCount: _notebooks.length,
                ),
              ),
            ),
          ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ),
    );
  }

  /// 分页画布卡片副标题：锁定（占位/文件密码未解锁）不泄露页数。
  String _notebookSubtitle(Notebook nb) {
    final time = _formatTime(nb.updatedAt);
    final locked =
        nb.isLockedPlaceholder || (nb.encrypted && nb.pages.isEmpty);
    if (locked) return '已加密 · 更新于 $time';
    return '${nb.pages.length} 页 · 更新于 $time';
  }

  /// 打开分页画布（整本）：统一走 shell 的 onOpenDoc（复用完整解锁链路）。
  Future<void> _openNotebook(Notebook nb) async {
    final doc = AllDoc(
      id: nb.id,
      title: nb.title,
      kind: AllDocKind.note,
      folder: '',
      createdAt: nb.createdAt,
      updatedAt: nb.updatedAt,
      notebookId: nb.id,
      locked: nb.isLockedPlaceholder,
    );
    if (widget.onOpenDoc != null) {
      widget.onOpenDoc!(doc);
      return;
    }
    // 无宿主回调时兜底直推（测试/独立装配场景；生产恒走 onOpenDoc）。
    final loaded = await _nbStorage.load(nb.id);
    if (loaded == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotebookViewPage(
          notebook: loaded,
          storage: _nbStorage,
          blockDocStore: _blockDocStore,
          editorPageBuilder: widget.editorPageBuilder,
        ),
      ),
    );
    await _refresh();
  }

  // ---------------- 笔记 Tab（M12：笔记本=笔记）----------------

  Widget _buildNotesTab() {
    if (_notes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_rounded, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('还没有笔记，点击右下角按钮新建一个吧'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppDesign.pagePadding,
          8,
          AppDesign.pagePadding,
          96,
        ),
        itemCount: _notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final doc = _notes[i];
          final isTyped = doc.kind == AllDocKind.blockdoc;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer,
                child: Icon(
                  isTyped ? Icons.edit_note_rounded : Icons.description_rounded,
                ),
              ),
              title: Text(
                doc.title.isEmpty ? '未命名' : doc.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${isTyped ? '笔记' : '分页画布页面'}'
                  ' · 更新于 ${_formatTime(doc.updatedAt)}',
                ),
              ),
              // 分页画布页面的删除在其所属分页画布页内管理（含克隆引用语义）；
              // 笔记支持此处直接删除。
              trailing: isTyped
                  ? IconButton(
                      tooltip: '删除笔记',
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: Theme.of(context).colorScheme.error,
                      onPressed: () => _deleteNote(doc),
                    )
                  : null,
              onTap: () => _openEntry(doc),
            ),
          );
        },
      ),
    );
  }

  /// 统一打开路径（M12.4）：与 All Docs 同一回调（note→NotebookViewPage，
  /// blockdoc→DocPage）。无宿主回调时兜底直推 DocPage（仅笔记）。
  ///
  /// N2：受密未解锁的笔记先解锁（与 app_shell 同口径）。
  Future<void> _openEntry(AllDoc doc) async {
    if (widget.onOpenDoc != null) {
      widget.onOpenDoc!(doc);
      return;
    }
    if (doc.kind != AllDocKind.blockdoc) return;
    if (!await _ensureUnlocked(doc.id)) return;
    // 锁定异常折叠为 null（fail-closed）——独立方法保证空安全提升。
    Future<NoteBlockDoc?> loadGuarded() async {
      try {
        return await _blockDocStore.loadDocument(doc.id);
      } on BlockDocLockedException {
        return null; // 会话 DEK 已被清——不暴露内容
      }
    }

    final d = await loadGuarded();
    if (!mounted || d == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocPage(
          document: d,
          blockDocStore: _blockDocStore,
          controller: DocController(
            onSave: (updated) => _blockDocStore.saveDocument(updated),
          ),
        ),
      ),
    );
    await _refresh();
  }

  /// N2：笔记文件密码解锁拦截。返回 false = 用户取消且会话未解锁。
  Future<bool> _ensureUnlocked(String id) async {
    if (!await _blockDocStore.isBlockDocPasswordProtected(id)) return true;
    if (_blockDocStore.isBlockDocUnlocked(id)) return true;
    if (!mounted) return false;
    final pin = await UnlockFlow.show(
      context,
      title: '该笔记已加密，输入密码',
      flexible: true,
      onVerify: (p) => _blockDocStore.verifyBlockDocPassword(id, p),
      footerLabel: '忘记密码？',
      onFooter: () {
        BlockDocPasswordResetFlow.show(
          context,
          store: _blockDocStore,
          docId: id,
        );
      },
    );
    return pin != null || _blockDocStore.isBlockDocUnlocked(id);
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteNote(AllDoc doc) async {
    // 策略门禁（专家审计最优先④）：删除操作白名单判定（回收站——可恢复）。
    if (!const PolicyEngine().check('note.delete').isAllowed) {
      _showSnack('操作被策略拒绝（note.delete）');
      return;
    }
    final ok = await _confirmDelete(
      '删除笔记',
      '确定删除笔记「${doc.title.isEmpty ? '未命名' : doc.title}」吗？此操作不可恢复。',
    );
    if (ok != true) return;
    try {
      await _blockDocStore.deleteDocument(doc.id);
      widget.onDataChanged?.call();
      await _refresh();
    } catch (e) {
      _showSnack('删除失败，请重试');
    }
  }
}
