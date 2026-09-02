// AFFiNE 式移动端单栏视图（2026-08-31，方案 A）。
//
// 布局参考：AFFiNE (MIT) packages/frontend/core/src/mobile/views/all-docs/
// （header = 顶部 tab 切换 + 右侧操作菜单；单栏列表；侧栏功能拆进 header）。
// 版权声明见 THIRD_PARTY_NOTICES.md（AFFiNE MIT 条目）。
//
// 设计要点（对齐 AFFiNE mobile 精髓）：
// - 移动端信息架构重新设计，非桌面缩小版：侧栏 248px 不进窄屏，
//   其功能（搜索/导航 Tab/回收站/最近文档）拆进顶部 header 与菜单。
// - 视图分家、业务共享：列表渲染直接复用 _GroupedDocList/_SortedDocList/
//   TagsView，与桌面同一数据流（_future/_cached/_query/_sort）。

part of 'all_docs_page.dart';

/// `_AllDocsPageState` 的移动端视图扩展。
///
/// extension-on-State 拆分模式（沿用 doc_editor part 先例）：
/// 同库 extension 可访问私有成员，无需公开任何状态。
extension _AllDocsPageMobile on _AllDocsPageState {
  /// 移动端单栏主体：顶部 header（Tab + 搜索 + 排序 + 更多）+ 列表。
  Widget buildMobileBody(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppleColor.surfaceDark : AppleColor.surfaceWhite;
    return SafeArea(
      bottom: false,
      child: FutureBuilder<AllDocQueryResult>(
        future: _future!,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                '加载失败，请下拉刷新重试',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            );
          }
          final result = _cached ?? snapshot.data;
          if (result == null) return const SizedBox.shrink();
          _cached = result;
          final sections = filterSections(result.sections, _query);
          final flatDocs = flattenSorted(sections, _sort);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MobileHeader(
                theme: theme,
                tabIndex: _tabIndex,
                onTabChanged: (i) => allDocsSetState(() => _tabIndex = i),
                searchOpen: _mobileSearchOpen,
                onToggleSearch: _toggleMobileSearch,
                sort: _sort,
                onSortChanged: (m) => allDocsSetState(() => _sort = m),
                onOpenTrash: widget.onOpenTrash,
                onOpenRecent: () => showMobileRecentDocs(context),
              ),
              // 搜索框（AFFiNE mobile：点击 header 搜索图标展开）。
              if (_mobileSearchOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    controller: _mobileSearchController,
                    autofocus: true,
                    onChanged: (q) => _searchDebouncer.run(
                      () => allDocsSetState(() => _query = q),
                    ),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '快速搜索',
                      isDense: true,
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _mobileSearchController.clear();
                                // 清空必须即时（flush 取消挂起的防抖）。
                                _searchDebouncer.flush(
                                  () => allDocsSetState(() => _query = ''),
                                );
                              },
                            ),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              // 标签 Tab：独立视图（M12.6，与桌面一致）。
              if (_tabIndex == 2)
                Expanded(
                  child: TagsView(docs: result.docs, loadTags: widget.loadTags),
                )
              else
                // 文档列表：与桌面完全相同的渲染组件（业务共享）。
                Expanded(
                  child: Container(
                    color: surface,
                    child: flatDocs != null
                        ? _SortedDocList(
                            theme: theme,
                            docs: flatDocs,
                            onOpenDoc: widget.onOpenDoc,
                            onToggleFavorite: _toggleFavorite,
                          )
                        : _GroupedDocList(
                            theme: theme,
                            tabIndex: _tabIndex,
                            sections: sections,
                            allDocs: result.docs,
                            onOpenDoc: widget.onOpenDoc,
                            onToggleFavorite: _toggleFavorite,
                            onNewDoc: widget.onNewDoc,
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 搜索框开合：关闭时清空搜索词并同步控制器。
  void _toggleMobileSearch() {
    allDocsSetState(() {
      _mobileSearchOpen = !_mobileSearchOpen;
      if (!_mobileSearchOpen) {
        _mobileSearchController.clear();
        _query = '';
      }
    });
  }

  /// 「最近文档」bottom sheet（对应桌面侧栏的文档树——功能不消失，换容器）。
  void showMobileRecentDocs(BuildContext context) {
    final cached = _cached;
    final docs = cached == null
        ? const <AllDoc>[]
        : (List.of(cached.docs)
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
            .take(30)
            .toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  '最近文档',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    '暂无文档',
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                )
              else
                for (final doc in docs)
                  ListTile(
                    leading: Icon(
                      visualForKind(doc.kind).icon,
                      size: 20,
                      color: visualForKind(doc.kind).color,
                    ),
                    dense: true,
                    title: Text(
                      doc.title.isEmpty ? '未命名' : doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    // N2：文件密码锁标（本会话未解锁）
                    trailing: doc.locked
                        ? Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.35,
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      widget.onOpenDoc(doc);
                    },
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// 移动端顶部 header：Tab 切换 + 搜索 + 排序 + 更多（AFFiNE all-docs header）。
class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.theme,
    required this.tabIndex,
    required this.onTabChanged,
    required this.searchOpen,
    required this.onToggleSearch,
    required this.sort,
    required this.onSortChanged,
    required this.onOpenTrash,
    required this.onOpenRecent,
  });

  final ThemeData theme;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final bool searchOpen;
  final VoidCallback onToggleSearch;
  final AllDocSort sort;
  final ValueChanged<AllDocSort> onSortChanged;
  final VoidCallback? onOpenTrash;
  final VoidCallback onOpenRecent;

  static const _tabs = ['文档', '收藏夹', '标签'];

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppleColor.surfaceDark : AppleColor.surfaceWhite;
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.55);
    final accent = theme.colorScheme.primary;

    return Container(
      height: 48,
      color: surface,
      child: Row(
        children: [
          const SizedBox(width: 8),
          // 顶部 Tab（与桌面 _DocsTabBar 同款样式，紧凑化）。
          ...List.generate(_tabs.length, (i) {
            final selected = i == tabIndex;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTabChanged(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _tabs[i],
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected ? accent : muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        height: 2,
                        width: 16,
                        decoration: BoxDecoration(
                          color: selected ? accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // 搜索开合（激活态高亮）。
          IconButton(
            tooltip: '搜索',
            icon: Icon(
              Icons.search_rounded,
              size: 21,
              color: searchOpen ? accent : muted,
            ),
            onPressed: onToggleSearch,
          ),
          // 排序（与桌面同 4 选项）。
          PopupMenuButton<AllDocSort>(
            tooltip: '排序',
            onSelected: onSortChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: AllDocSort.timeGrouped,
                child: Text('按时间分组'),
              ),
              PopupMenuItem(
                value: AllDocSort.updatedAtDesc,
                child: Text('按更新时间'),
              ),
              PopupMenuItem(
                value: AllDocSort.createdAtDesc,
                child: Text('按创建时间'),
              ),
              PopupMenuItem(value: AllDocSort.titleAsc, child: Text('按标题')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.sort_rounded,
                size: 21,
                color: sort == AllDocSort.timeGrouped ? muted : accent,
              ),
            ),
          ),
          // 更多：回收站 + 最近文档（桌面侧栏功能不消失，换容器）。
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (key) {
              if (key == 'trash') {
                onOpenTrash?.call();
              } else if (key == 'recent') {
                onOpenRecent();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'recent',
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('最近文档'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'trash',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('回收站'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(Icons.more_horiz_rounded, size: 21, color: muted),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// 移动端新建文档 bottom sheet（AFFiNE mobile create 动作语义；
/// 选项与桌面「新建文档 ▾」一致：笔记为主，画布为辅）。
void showMobileNewDocSheet(
  BuildContext context,
  void Function(AllDocKind kind)? onNewDoc,
) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.edit_note_rounded,
                color: AppleColor.noteGreen,
              ),
              title: const Text('新建笔记'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onNewDoc?.call(AllDocKind.blockdoc);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.auto_stories_rounded,
                color: AppleColor.actionBlue,
              ),
              title: const Text('新建分页画布'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onNewDoc?.call(AllDocKind.note);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.crop_portrait_rounded,
                color: AppleColor.actionBlue,
              ),
              title: const Text('新建画布'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onNewDoc?.call(AllDocKind.canvas);
              },
            ),
          ],
        ),
      );
    },
  );
}
