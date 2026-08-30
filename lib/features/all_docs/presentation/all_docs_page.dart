// M9-3 全部文档工作台：AllDocsPage 主页面。
//
// 纯展示层：
// - 构造注入 loadDocs / onOpenDoc / onNewDoc / onToggleFavorite，
// - 内部 FutureBuilder 加载数据并缓存，搜索与收藏切换均为本地状态重算，
// - 左侧 AllDocsSidebar + 主内容区（工具条 / Tab / 分组文档列表）。
// 不 import 任何存储/服务实现。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_search.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_sort.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_sidebar.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_doc_row.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

/// 全部文档工作台主页面。
///
/// ### 构造注入
/// - [loadDocs]：异步加载 [AllDocQueryResult] 的数据源。
/// - [onOpenDoc]：点击文档行时调用。
/// - [onNewDoc]：新建文档回调（画板/笔记/块文档）。
/// - [onToggleFavorite]：切换收藏回调（持久化由壳层负责；UI 乐观更新）。
///
/// ### 布局
/// - 左：[AllDocsSidebar] 工作区面板（搜索 + 导航）
/// - 右：工具条 + Tab + 分组文档列表
class AllDocsPage extends StatefulWidget {
  const AllDocsPage({
    super.key,
    required this.loadDocs,
    required this.onOpenDoc,
    this.onNewDoc,
    this.onToggleFavorite,
    this.refreshSignal,
  });

  final Future<AllDocQueryResult> Function() loadDocs;
  final void Function(AllDoc doc) onOpenDoc;
  final void Function(AllDocKind kind)? onNewDoc;
  final void Function(AllDoc doc)? onToggleFavorite;

  /// 数据版本通知（shell 在文档新增/修改后自增）：触发列表重载。
  final ValueListenable<int>? refreshSignal;

  @override
  State<AllDocsPage> createState() => _AllDocsPageState();
}

class _AllDocsPageState extends State<AllDocsPage> {
  @override
  void initState() {
    super.initState();
    _future ??= widget.loadDocs();
    widget.refreshSignal?.addListener(_onDataVersionChanged);
  }

  void _onDataVersionChanged() {
    if (!mounted) return;
    setState(() {
      _cached = null;
      _future = widget.loadDocs();
    });
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onDataVersionChanged);
    super.dispose();
  }

  // Tab 索引：0=文档，1=精选，2=标签。侧栏导航项与 Tab 一一对应。
  int _tabIndex = 0;

  /// 搜索词（快速搜索框）。
  String _query = '';

  /// 排序模式（M11：默认时间分组；其余模式渲染扁平列表）。
  AllDocSort _sort = AllDocSort.timeGrouped;

  /// 已加载的结果缓存（收藏切换时在其上做乐观更新）。
  AllDocQueryResult? _cached;

  /// 当前加载任务（数据版本变化时由 [_onDataVersionChanged] 重启）。
  Future<AllDocQueryResult>? _future;

  /// 收藏切换：更新缓存中的 isFavorite（乐观 UI），并通知壳层持久化。
  Future<void> _toggleFavorite(AllDoc doc) async {
    final cached = _cached;
    if (cached == null) return;
    final newFavorite = !doc.isFavorite;
    AllDocQueryResult next = cached;
    next = AllDocQueryResult(
      docs: _mapDocs(cached.docs, doc.dedupKey, newFavorite),
      sections: [
        for (final s in cached.sections)
          AllDocSection(
            group: s.group,
            label: s.label,
            docs: _mapDocs(s.docs, doc.dedupKey, newFavorite),
          ),
      ],
    );
    setState(() => _cached = next);
    widget.onToggleFavorite?.call(doc);
  }

  List<AllDoc> _mapDocs(List<AllDoc> docs, String dedupKey, bool favorite) =>
      docs
          .map(
            (d) =>
                d.dedupKey == dedupKey ? d.copyWith(isFavorite: favorite) : d,
          )
          .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canvas = isDark ? AppleColor.canvansDark : AppleColor.parchment;

    return Scaffold(
      backgroundColor: canvas,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧工作区面板
          AllDocsSidebar(
            searchQuery: _query,
            onSearchChanged: (q) => setState(() => _query = q),
            selectedNavIndex: _tabIndex,
            onNavSelected: (i) => setState(() {
              // 侧栏前三项与 Tab 一一对应：全部文档/收藏夹/标签。
              _tabIndex = i.clamp(0, 2);
            }),
            // 文档树（M11.3）：最近文档，点击直接打开。
            recentDocs: _cached == null
                ? const []
                : (List.of(_cached!.docs)
                        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
                      .take(30)
                      .toList(growable: false),
            onOpenDoc: widget.onOpenDoc,
          ),
          // 垂直分隔线
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: theme.dividerColor.withValues(alpha: 0.15),
          ),
          // 主内容区
          Expanded(
            child: FutureBuilder<AllDocQueryResult>(
              future: _future!,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      '加载失败：${snapshot.error}',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  );
                }
                final result = _cached ?? snapshot.data;
                if (result == null) return const SizedBox.shrink();
                _cached = result;
                final sections = filterSections(result.sections, _query);
                final flatDocs = flattenSorted(sections, _sort);
                // 注意：空文档时也必须渲染工具条（否则全新安装没有任何
                // 创建入口——M11 修复"打开后点不动"的主因）。
                return _MainContent(
                  theme: theme,
                  tabIndex: _tabIndex,
                  sections: sections,
                  flatDocs: flatDocs,
                  sort: _sort,
                  onSortChanged: (m) => setState(() => _sort = m),
                  onOpenDoc: widget.onOpenDoc,
                  onNewDoc: widget.onNewDoc,
                  onToggleFavorite: _toggleFavorite,
                  onTabChanged: (i) => setState(() => _tabIndex = i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 主内容区：工具条 + Tab + 列表。
class _MainContent extends StatelessWidget {
  const _MainContent({
    required this.theme,
    required this.tabIndex,
    required this.sections,
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
    final subtle = onSurface.withValues(alpha: 0.4);

    return Container(
      height: 52,
      color: surface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // 面包屑
          Text(
            '全部文档',
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
            label: '新建文档',
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
      items: const [
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
              Text('新建笔记（打字）'),
            ],
          ),
        ),
        // M12：笔记本=笔记（同一模块），不再单设「新建笔记本」入口
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
              Text('新建画板'),
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

  static const _tabs = ['文档', '收藏夹', '标签'];

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? AppleColor.surfaceDark : AppleColor.surfaceWhite;
    final onSurface = theme.colorScheme.onSurface;
    final subtle = onSurface.withValues(alpha: 0.45);
    final accent = theme.colorScheme.primary;

    return Container(
      height: 42,
      color: surface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final selected = i == tabIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 18),
            child: InkWell(
              onTap: () => onTabChanged(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Text(
                    _tabs[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? accent : subtle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 2,
                    width: 18,
                    decoration: BoxDecoration(
                      color: selected ? accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
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
      return _TabEmptyState(theme: theme, text: '没有匹配的文档', tip: '试试其他关键词或排序方式');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: docs.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.08)),
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
    required this.onOpenDoc,
    required this.onToggleFavorite,
    this.onNewDoc,
  });

  final ThemeData theme;
  final int tabIndex;
  final List<AllDocSection> sections;
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
          text: '暂无收藏文档',
          tip: '点击文档行星标可添加到收藏夹',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: favorites.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: theme.dividerColor.withValues(alpha: 0.08),
        ),
        itemBuilder: (context, i) => AllDocRow(
          doc: favorites[i],
          onOpenDoc: () => onOpenDoc(favorites[i]),
          onToggleFavorite: () => onToggleFavorite(favorites[i]),
        ),
      );
    }

    if (tabIndex == 2) {
      // 标签：空态
      return _TabEmptyState(theme: theme, text: '暂无标签', tip: '使用文件夹与收藏夹整理文档');
    }

    // 文档：分组（或全空时的创建引导）
    if (sections.expand((s) => s.docs).isEmpty) {
      return _EmptyState(
        theme: theme,
        onNewBlockDoc: () => onNewDoc?.call(AllDocKind.blockdoc),
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
                  Divider(
                    height: 1,
                    color: theme.dividerColor.withValues(alpha: 0.08),
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
    final onSurface = theme.colorScheme.onSurface;
    final subtle = onSurface.withValues(alpha: 0.4);
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

/// 页面级空态：含创建入口（打字笔记为主，画板为辅——AFFiNE 语义）。
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.theme,
    this.onNewBlockDoc,
    this.onNewCanvas,
  });

  final ThemeData theme;
  final VoidCallback? onNewBlockDoc;
  final VoidCallback? onNewCanvas;

  @override
  Widget build(BuildContext context) {
    final subtle = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note_rounded, size: 56, color: subtle),
          const SizedBox(height: 12),
          Text(
            '记下第一笔',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '笔记直接打字，画板用来写写画画',
            style: TextStyle(fontSize: 12.5, color: subtle),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: onNewBlockDoc,
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('新建笔记（打字）'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onNewCanvas,
                icon: const Icon(Icons.crop_portrait_rounded, size: 18),
                label: const Text('新建画板'),
              ),
            ],
          ),
        ],
      ),
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
    final subtle = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: subtle),
          const SizedBox(height: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(tip, style: TextStyle(fontSize: 12, color: subtle)),
        ],
      ),
    );
  }
}
