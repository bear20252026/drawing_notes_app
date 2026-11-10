part of 'home_page.dart';

// 首页 Tab 布局域（行数门禁拆分）：_buildBody / 三个 Tab / 打开笔记本等。
// 从 home_page.dart 移出为 extension（行为零变化），保持主文件 < 500 逻辑行。

extension _HomePageTabs on _HomePageState {
  Widget _buildBody() {
    if (_loading) {
      // U4a：首屏加载换卡片网格骨架（与画布 Tab 网格同参数）。
      return const SkeletonCardGrid();
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(
                color: AppleColor.errorTextOf(Theme.of(context).colorScheme),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _refresh,
              child: Text(AppLocalizations.of(context)?.homeRetry ?? '重试'),
            ),
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
      // 空态统一（审计二-4）：收编到共享 AppleEmptyState。
      final l10n = AppLocalizations.of(context);
      return AppleEmptyState(
        icon: Icons.brush_outlined,
        title: l10n?.homeNoCanvas ?? '还没有画布',
        tip: l10n?.homeEmptyTip ?? '点击右下角按钮新建一个吧',
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (hasCanvas) ...[
            SliverToBoxAdapter(
              child: _CanvasSectionHeader(
                AppLocalizations.of(context)?.homeInfiniteCanvas ?? '无限画布',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.pagePadding,
                8,
                AppDesign.pagePadding,
                0,
              ),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
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
            SliverToBoxAdapter(
              child: _CanvasSectionHeader(
                AppLocalizations.of(context)?.homePagedCanvas ?? '分页画布',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.pagePadding,
                8,
                AppDesign.pagePadding,
                0,
              ),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
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
    final time = formatSmartTime(nb.updatedAt);
    final l10n = AppLocalizations.of(context);
    final locked = nb.isLockedPlaceholder || (nb.encrypted && nb.pages.isEmpty);
    // L-04：锁定与页数副标题接 arb 键（原写死中文）。
    if (locked) return l10n?.nbLockedSubtitle(time) ?? '已加密 · 更新于 $time';
    return l10n?.nbPageCountSubtitle(nb.pages.length, time) ??
        '${nb.pages.length} 页 · 更新于 $time';
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
          // C-06（审计 2026-09-27）：媒体服务同一实例传线。
          mediaCrypto: widget.mediaCrypto,
        ),
      ),
    );
    await _refresh();
  }

  // ---------------- 笔记 Tab（M12：笔记本=笔记）----------------

  Widget _buildNotesTab() {
    if (_notes.isEmpty) {
      // 空态统一（审计二-4）：收编到共享 AppleEmptyState。
      final l10n = AppLocalizations.of(context);
      return AppleEmptyState(
        icon: Icons.edit_note_rounded,
        title: l10n?.homeNoNotes ?? '还没有笔记',
        tip: l10n?.homeEmptyTip ?? '点击右下角按钮新建一个吧',
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
        separatorBuilder: (_, _) => const SizedBox(height: 12),
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
                foregroundColor: Theme.of(context)
                    .colorScheme
                    .onPrimaryContainer,
                child: Icon(
                  isTyped ? Icons.edit_note_rounded : Icons.description_rounded,
                ),
              ),
              title: Text(
                doc.title.isEmpty
                    ? DomainDisplayLabels.docTitle(
                        AppLocalizations.of(context),
                        null,
                      )
                    : doc.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${isTyped ? AppLocalizations.of(context)?.homeKindNote ?? '笔记' : AppLocalizations.of(context)?.homeKindNotebookPage ?? '分页画布页面'}'
                  ' · ${AppLocalizations.of(context)?.homeUpdatedAt(formatSmartTime(doc.updatedAt)) ?? '更新于 ${formatSmartTime(doc.updatedAt)}'}',
                ),
              ),
              // 分页画布页面的删除在其所属分页画布页内管理（含克隆引用语义）；
              // 笔记支持此处直接删除。
              trailing: isTyped
                  ? IconButton(
                      tooltip:
                          AppLocalizations.of(context)?.homeDeleteNote ??
                          '删除笔记',
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
  /// blockdoc→DocPage）。
  ///
  /// 解耦（2026-10-10）：原先此处直接 import doc 的 presentation 层
  /// （DocPage）与 security 的 presentation 层（BlockDocPasswordResetFlow）
  /// 自拼打开链路；现改为**经组合根注入的** [AppRouteServices]
  /// （`app/app_routes.dart` 契约）——notes 不再横向依赖 doc/security 的
  /// presentation 层。解锁拦截（含损坏文档反馈）随之落在实现侧，
  /// 语义与迁移前逐条一致。
  Future<void> _openEntry(AllDoc doc) async {
    if (widget.onOpenDoc != null) {
      widget.onOpenDoc!(doc);
      return;
    }
    if (doc.kind != AllDocKind.blockdoc) return;
    final routes = appRouteServices;
    if (routes == null) {
      _showSnack(_l10nSafe?.shellEditorNotAssembled ?? '编辑器尚未由应用层装配');
      return;
    }
    await routes.openNotePage(
      context,
      DocOpenArgs(
        id: doc.id,
        title: doc.title,
        createdAt: doc.createdAt,
        updatedAt: doc.updatedAt,
      ),
    );
    await _refresh();
  }

  Future<void> _deleteNote(AllDoc doc) async {
    // 策略门禁（专家审计最优先④）：删除操作白名单判定（回收站——可恢复）。
    if (!const PolicyEngine().check('note.delete').isAllowed) {
      _showSnack(
        AppLocalizations.of(context)?.docPolicyDenied('note.delete') ??
            '操作被策略拒绝（note.delete）',
      );
      return;
    }
    final title = doc.title.isEmpty
        ? DomainDisplayLabels.docTitle(AppLocalizations.of(context), null)
        : doc.title;
    final ok = await _confirmDelete(
      AppLocalizations.of(context)?.homeDeleteNote ?? '删除笔记',
      AppLocalizations.of(context)?.homeDeleteNoteConfirm(title) ??
          '确定删除笔记「$title」吗？此操作不可恢复。',
    );
    if (ok != true) return;
    try {
      await _blockDocStore.deleteDocument(doc.id);
      widget.onDataChanged?.call();
      await _refresh();
    } catch (e) {
      _showSnack(_l10nSafe?.homeDeleteFailed ?? '删除失败，请重试');
    }
  }
}
