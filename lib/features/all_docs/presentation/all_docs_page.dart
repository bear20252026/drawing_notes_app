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
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_search.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_sort.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_sidebar.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_doc_row.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/tags_view.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
part 'all_docs_page_widgets.dart';

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
    this.onOpenTrash,
    this.loadTags,
    this.onToggleFavorite,
    this.refreshSignal,
  });

  final Future<AllDocQueryResult> Function() loadDocs;
  final void Function(AllDoc doc) onOpenDoc;
  final void Function(AllDocKind kind)? onNewDoc;

  /// 打开回收站（M12.6，经侧栏第 4 项）。
  final VoidCallback? onOpenTrash;

  /// 标签注册表读取（M12.6 标签 Tab）。
  final Future<List<DocTag>> Function()? loadTags;
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
            onOpenTrash: widget.onOpenTrash,
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
                  allDocs: result.docs,
                  flatDocs: flatDocs,
                  sort: _sort,
                  onSortChanged: (m) => setState(() => _sort = m),
                  onOpenDoc: widget.onOpenDoc,
                  onNewDoc: widget.onNewDoc,
                  onToggleFavorite: _toggleFavorite,
                  onTabChanged: (i) => setState(() => _tabIndex = i),
                  loadTags: widget.loadTags,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
