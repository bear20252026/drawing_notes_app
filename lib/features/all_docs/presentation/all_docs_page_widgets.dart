part of 'all_docs_page.dart';

// 列表区/工具条/空态等展示组件（自 all_docs_page.dart 拆出）。

/// 主内容区：工具条 + Tab + 列表。
class _MainContent extends StatelessWidget {
  const _MainContent({
    required this.theme,
    required this.tabIndex,
    required this.sections,
    required this.allDocs,
    required this.loadTags,
    required this.onOpenDoc,
    required this.onTabChanged,
    required this.onToggleFavorite,
    this.flatDocs,
    this.sort = AllDocSort.timeGrouped,
    this.onSortChanged,
    this.onNewDoc,
  });

  final ThemeData theme;
  final int tabIndex;

  /// 标签注册表读取（M12.6 标签 Tab）。
  final Future<List<DocTag>> Function()? loadTags;

  /// 全量文档（标签视图统计/过滤用）。
  final List<AllDoc> allDocs;
  final List<AllDocSection> sections;

  /// 排序模式非 timeGrouped 时的扁平列表（null = 保持分组渲染）。
  final List<AllDoc>? flatDocs;
  final AllDocSort sort;
  final ValueChanged<AllDocSort>? onSortChanged;
  final void Function(AllDoc doc) onOpenDoc;
  final void Function(AllDoc doc) onToggleFavorite;
  final void Function(AllDocKind kind)? onNewDoc;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppleColor.surfaceDark : AppleColor.surfaceWhite;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶工具条
        _DocsToolbar(
          theme: theme,
          onNewDoc: onNewDoc,
          sort: sort,
          onSortChanged: onSortChanged,
        ),
        // Tab 栏
        _DocsTabBar(
          theme: theme,
          tabIndex: tabIndex,
          onTabChanged: onTabChanged,
        ),
        const Divider(height: 1, thickness: 1),
        // 标签 Tab：独立视图（M12.6）
        if (tabIndex == 2)
          Expanded(
            child: TagsView(docs: allDocs, loadTags: loadTags),
          )
        else
          // 分组文档列表
          Expanded(
            child: Container(
              color: surface,
              child: flatDocs != null
                  ? _SortedDocList(
                      theme: theme,
                      docs: flatDocs!,
                      onOpenDoc: onOpenDoc,
                      onToggleFavorite: onToggleFavorite,
                    )
                  : _GroupedDocList(
                      theme: theme,
                      tabIndex: tabIndex,
                      sections: sections,
                      allDocs: allDocs,
                      onOpenDoc: onOpenDoc,
                      onToggleFavorite: onToggleFavorite,
                      onNewDoc: onNewDoc,
                    ),
            ),
          ),
      ],
    );
  }
}

/// 顶工具条：面包屑 + 新建 + 视图切换 + 显示 + 新建文档下拉。
class _DocsToolbar extends StatelessWidget {
  _DocsToolbar({
    required this.theme,
    this.onNewDoc,
    this.sort = AllDocSort.timeGrouped,
    this.onSortChanged,
  });

  final ThemeData theme;
  final void Function(AllDocKind)? onNewDoc;
  final AllDocSort sort;
  final ValueChanged<AllDocSort>? onSortChanged;

  final _newDocButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppleColor.surfaceDark : AppleColor.surfaceWhite;
    final onSurface = theme.colorScheme.onSurface;
    final subtle = AppleColor.mutedOf(theme.colorScheme);

    return Container(
      height: 52,
      color: surface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // 面包屑
          Text(
            AppLocalizations.of(context)?.shellAllDocs ?? '全部文档',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: subtle),
          const Spacer(),
          // 排序（M11：AFFiNE 排序语义）
          PopupMenuButton<AllDocSort>(
            tooltip: AppLocalizations.of(context)?.docsSort ?? '排序',
            onSelected: onSortChanged,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: AllDocSort.timeGrouped,
                child: Text(
                  AppLocalizations.of(context)?.docsSortGroupTime ?? '按时间分组',
                ),
              ),
              PopupMenuItem(
                value: AllDocSort.updatedAtDesc,
                child: Text(
                  AppLocalizations.of(context)?.docsSortUpdated ?? '按更新时间',
                ),
              ),
              PopupMenuItem(
                value: AllDocSort.createdAtDesc,
                child: Text(
                  AppLocalizations.of(context)?.docsSortCreated ?? '按创建时间',
                ),
              ),
              PopupMenuItem(
                value: AllDocSort.titleAsc,
                child: Text(
                  AppLocalizations.of(context)?.docsSortTitle ?? '按标题',
                ),
              ),
            ],
            child: Icon(
              Icons.sort_rounded,
              size: 20,
              color: sort == AllDocSort.timeGrouped ? subtle : onSurface,
            ),
          ),
          const SizedBox(width: 12),
          // 「新建文档 ▾」下拉
          ApplePrimaryButton(
            key: _newDocButtonKey,
            label: AppLocalizations.of(context)?.docsNewDoc ?? '新建文档',
            icon: Icons.add_rounded,
            onPressed: () => _showNewDocMenu(context),
          ),
        ],
      ),
    );
  }

  void _showNewDocMenu(BuildContext context) {
    final button =
        _newDocButtonKey.currentContext!.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final offset = button.localToGlobal(Offset.zero, ancestor: overlay);
    showMenu<AllDocKind>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        0,
      ),
      items: [
        // 打字为主（AFFiNE Page 语义）：笔记 = 直接打字的块文档。
        PopupMenuItem(
          value: AllDocKind.blockdoc,
          child: Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 18,
                color: AppleColor.noteGreen,
              ),
              SizedBox(width: 10),
              Text(AppLocalizations.of(context)?.docsNewNote ?? '新建笔记'),
            ],
          ),
        ),
        // N1 命名统一：画布两类型并列（无限画布=画布；旧笔记本=分页画布），
        // 分页画布新建入口恢复（M12 曾移除）。
        PopupMenuItem(
          value: AllDocKind.note,
          child: Row(
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 18,
                color: AppleColor.actionBlue,
              ),
              SizedBox(width: 10),
              Text(
                AppLocalizations.of(context)?.docsNewPagedCanvas ?? '新建分页画布',
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: AllDocKind.canvas,
          child: Row(
            children: [
              Icon(
                Icons.crop_portrait_rounded,
                size: 18,
                color: AppleColor.actionBlue,
              ),
              SizedBox(width: 10),
              Text(AppLocalizations.of(context)?.docsNewCanvas ?? '新建画布'),
            ],
          ),
        ),
      ],
    ).then((kind) {
      if (kind != null) onNewDoc?.call(kind);
    });
  }
}

/// Tab 栏：文档 / 收藏夹 / 标签。
class _DocsTabBar extends StatelessWidget {
  const _DocsTabBar({
    required this.theme,
    required this.tabIndex,
    required this.onTabChanged,
  });

  final ThemeData theme;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppleColor.surfaceDark : AppleColor.surfaceWhite;
    final subtle = AppleColor.mutedOf(theme.colorScheme);
    final accent = theme.colorScheme.primary;
    final tabs = [
      AppLocalizations.of(context)?.docsTabDocs ?? '文档',
      AppLocalizations.of(context)?.docsTabFavorites ?? '收藏夹',
      AppLocalizations.of(context)?.docTags ?? '标签',
    ];

    return Container(
      // U4a：42→48——Tab 点击目标达触控标准（InkWell 撑满容器高）。
      height: 48,
      color: surface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = i == tabIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 18),
            child: InkWell(
              onTap: () => onTabChanged(i),
              child: SizedBox(
                height: 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tabs[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? accent : subtle,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 2,
                      width: 18,
                      decoration: BoxDecoration(
                        color: selected ? accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppleRadius.xs),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 排序模式下的扁平文档列表（无分组头）。
class _SortedDocList extends StatelessWidget {
  const _SortedDocList({
    required this.theme,
    required this.docs,
    required this.onOpenDoc,
    required this.onToggleFavorite,
  });

  final ThemeData theme;
  final List<AllDoc> docs;
  final void Function(AllDoc doc) onOpenDoc;
  final void Function(AllDoc doc) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return _TabEmptyState(
        theme: theme,
        text: AppLocalizations.of(context)?.docsEmptyNoMatch ?? '没有匹配的文档',
        tip:
            AppLocalizations.of(context)?.docsEmptyNoMatchTip ?? '试试其他关键词或排序方式',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: docs.length,
      // 原先是 `theme.dividerColor.withValues(alpha: 0.08)`——而
      // dividerColor 本身已经是 8% 发丝线，再乘一次只剩 0.64%，
      // 等于**没有分隔线**。改用 AppleHairline，并从**文字起始处**
      // 起线（indent = 16 padding + 36 图标 + 12 间距 = 64）：
      // 拉通到屏幕边缘的发丝线会把每行切成格子，从文字处起只做
      // 分组提示，层级更轻（shadcn 的信息层级做法）。
      separatorBuilder: (context, index) =>
          AppleHairline.listDivider(context, indent: AllDocRow.textIndent),
      itemBuilder: (context, i) => AllDocRow(
        doc: docs[i],
        onOpenDoc: () => onOpenDoc(docs[i]),
        onToggleFavorite: () => onToggleFavorite(docs[i]),
      ),
    );
  }
}

/// 分组文档列表。
///
/// - Tab 0（文档）：按 sections 渲染组头 + AllDocRow。
/// - Tab 1（收藏夹）：仅渲染 isFavorite 文档，不分组。
/// - Tab 2（标签）：空态（暂无标签维度）。
class _GroupedDocList extends StatelessWidget {
  const _GroupedDocList({
    required this.theme,
    required this.tabIndex,
    required this.sections,
    required this.allDocs,
    required this.onOpenDoc,
    required this.onToggleFavorite,
    this.onNewDoc,
  });

  final ThemeData theme;
  final int tabIndex;
  final List<AllDocSection> sections;
  final List<AllDoc> allDocs;
  final void Function(AllDoc doc) onOpenDoc;
  final void Function(AllDoc doc) onToggleFavorite;
  final void Function(AllDocKind kind)? onNewDoc;

  @override
  Widget build(BuildContext context) {
    if (tabIndex == 1) {
      // 收藏夹：仅 favorite
      final favorites = sections
          .expand((s) => s.docs)
          .where((d) => d.isFavorite)
          .toList();
      if (favorites.isEmpty) {
        return _TabEmptyState(
          theme: theme,
          text: AppLocalizations.of(context)?.docsEmptyNoFavorites ?? '暂无收藏文档',
          tip:
              AppLocalizations.of(context)?.docsEmptyNoFavoritesTip ??
              '点击文档行星标可添加到收藏夹',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: favorites.length,
        separatorBuilder: (context, index) =>
            AppleHairline.listDivider(context, indent: AllDocRow.textIndent),
        itemBuilder: (context, i) => AllDocRow(
          doc: favorites[i],
          onOpenDoc: () => onOpenDoc(favorites[i]),
          onToggleFavorite: () => onToggleFavorite(favorites[i]),
        ),
      );
    }

    // 文档：分组（或全空时的创建引导）
    if (sections.expand((s) => s.docs).isEmpty) {
      return _EmptyState(
        theme: theme,
        onNewBlockDoc: () => onNewDoc?.call(AllDocKind.blockdoc),
        onNewNotebook: () => onNewDoc?.call(AllDocKind.note),
        onNewCanvas: () => onNewDoc?.call(AllDocKind.canvas),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sections.length,
      itemBuilder: (context, si) {
        final section = sections[si];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 组头
            _SectionHeader(theme: theme, label: section.label),
            ...section.docs.map(
              (doc) => Column(
                children: [
                  AllDocRow(
                    doc: doc,
                    onOpenDoc: () => onOpenDoc(doc),
                    onToggleFavorite: () => onToggleFavorite(doc),
                  ),
                  AppleHairline.listDivider(
                    context,
                    indent: AllDocRow.textIndent,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    final subtle = AppleColor.mutedOf(theme.colorScheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: subtle,
        ),
      ),
    );
  }
}

/// 页面级空态：含创建入口（笔记为主，画布为辅——AFFiNE 语义）。
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.theme,
    this.onNewBlockDoc,
    this.onNewNotebook,
    this.onNewCanvas,
  });

  final ThemeData theme;
  final VoidCallback? onNewBlockDoc;
  final VoidCallback? onNewNotebook;
  final VoidCallback? onNewCanvas;

  @override
  Widget build(BuildContext context) {
    // 空态统一（审计二-4）：外观收编到共享 AppleEmptyState 单一来源。
    return AppleEmptyState(
      icon: Icons.edit_note_rounded,
      title: AppLocalizations.of(context)?.docsEmptyFirstNote ?? '记下第一笔',
      tip:
          AppLocalizations.of(context)?.docsEmptyFirstNoteTip ??
          '笔记用来打字，画布用来写写画画',
      // 三入口（笔记/分页画布/画布）：Wrap 排布——390dp 窄屏自适应换行。
      actions: [
        FilledButton.icon(
          onPressed: onNewBlockDoc,
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          label: Text(AppLocalizations.of(context)?.docsNewNote ?? '新建笔记'),
        ),
        OutlinedButton.icon(
          onPressed: onNewNotebook,
          icon: const Icon(Icons.auto_stories_rounded, size: 18),
          label: Text(
            AppLocalizations.of(context)?.docsNewPagedCanvas ?? '新建分页画布',
          ),
        ),
        OutlinedButton.icon(
          onPressed: onNewCanvas,
          icon: const Icon(Icons.crop_portrait_rounded, size: 18),
          label: Text(AppLocalizations.of(context)?.docsNewCanvas ?? '新建画布'),
        ),
      ],
    );
  }
}

/// Tab 级空态（收藏夹/标签）。
class _TabEmptyState extends StatelessWidget {
  const _TabEmptyState({
    required this.theme,
    required this.text,
    required this.tip,
  });

  final ThemeData theme;
  final String text;
  final String tip;

  @override
  Widget build(BuildContext context) {
    // 空态统一（审计二-4）：收编到共享 AppleEmptyState。
    return AppleEmptyState(icon: Icons.inbox_outlined, title: text, tip: tip);
  }
}
