// M9-3 全部文档工作台：AllDocsPage 主页面。
//
// 纯展示层：
// - 构造注入 loadDocs / onOpenDoc / onNewDoc，
// - 内部 FutureBuilder 加载数据，
// - 左侧 AllDocsSidebar + 主内容区（工具条 / Tab / 分组文档列表）。
// 不 import 任何存储/服务实现。

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_sidebar.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_doc_row.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

/// 全部文档工作台主页面。
///
/// ### 构造注入
/// - [loadDocs]：异步加载 [AllDocQueryResult] 的数据源。
/// - [onOpenDoc]：点击文档行时调用。
/// - [onNewDoc]：新建文档回调（画板/笔记/块文档）。
///
/// ### 布局
/// - 左：[AllDocsSidebar] 工作区面板
/// - 右：工具条 + Tab + 分组文档列表
class AllDocsPage extends StatefulWidget {
  const AllDocsPage({
    super.key,
    required this.loadDocs,
    required this.onOpenDoc,
    this.onNewDoc,
  });

  final Future<AllDocQueryResult> Function() loadDocs;
  final void Function(AllDoc doc) onOpenDoc;
  final void Function(AllDocKind kind)? onNewDoc;

  @override
  State<AllDocsPage> createState() => _AllDocsPageState();
}

class _AllDocsPageState extends State<AllDocsPage> {
  // Tab 索引：0=文档，1=精选，2=标签。
  int _tabIndex = 0;

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
            onSearchChanged: (_) {
              // 搜索：lead 接入实际查询后实现。
            },
            onNavSelected: (_) {
              // 导航切换：lead 接入 app_shell 后实现。
            },
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
              future: widget.loadDocs(),
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
                final result = snapshot.data;
                if (result == null || result.docs.isEmpty) {
                  return _EmptyState(theme: theme);
                }
                return _MainContent(
                  theme: theme,
                  tabIndex: _tabIndex,
                  sections: result.sections,
                  onOpenDoc: widget.onOpenDoc,
                  onNewDoc: widget.onNewDoc,
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
    this.onNewDoc,
  });

  final ThemeData theme;
  final int tabIndex;
  final List<AllDocSection> sections;
  final void Function(AllDoc doc) onOpenDoc;
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
        _DocsToolbar(theme: theme, onNewDoc: onNewDoc),
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
            child: _GroupedDocList(
              theme: theme,
              tabIndex: tabIndex,
              sections: sections,
              onOpenDoc: onOpenDoc,
            ),
          ),
        ),
      ],
    );
  }
}

/// 顶工具条：面包屑 + 新建 + 视图切换 + 显示 + 新建文档下拉。
class _DocsToolbar extends StatelessWidget {
  _DocsToolbar({required this.theme, this.onNewDoc});

  final ThemeData theme;
  final void Function(AllDocKind kind)? onNewDoc;

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
          const SizedBox(width: 12),
          // + 按钮
          _IconChip(icon: Icons.add_rounded, onPressed: () {}),
          const Spacer(),
          // 视图切换（列表）
          _IconChip(
            icon: Icons.view_list_rounded,
            onPressed: () {},
            tooltip: '列表视图',
          ),
          const SizedBox(width: 6),
          // 视图切换（看板）
          _IconChip(
            icon: Icons.view_kanban_rounded,
            onPressed: () {},
            tooltip: '看板视图',
          ),
          const SizedBox(width: 10),
          // 「显示」按钮
          OutlinedButton.icon(
            onPressed: () {},
            icon: Icon(Icons.tune_rounded, size: 16, color: subtle),
            label: Text(
              '显示',
              style: TextStyle(fontSize: 12.5, color: onSurface),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              side: BorderSide(color: theme.dividerColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 10),
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
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
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
        PopupMenuItem(
          value: AllDocKind.canvas,
          child: Row(
            children: [
              Icon(Icons.crop_portrait_rounded,
                  size: 18, color: AppleColor.actionBlue),
              SizedBox(width: 10),
              Text('新建画板'),
            ],
          ),
        ),
        PopupMenuItem(
          value: AllDocKind.note,
          child: Row(
            children: [
              Icon(Icons.sticky_note_2_rounded,
                  size: 18, color: AppleColor.noteGreen),
              SizedBox(width: 10),
              Text('新建笔记'),
            ],
          ),
        ),
        PopupMenuItem(
          value: AllDocKind.blockdoc,
          child: Row(
            children: [
              Icon(Icons.dashboard_rounded,
                  size: 18, color: AppleColor.blockPurple),
              SizedBox(width: 10),
              Text('新建块文档'),
            ],
          ),
        ),
      ],
    ).then((kind) {
      if (kind != null) onNewDoc?.call(kind);
    });
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: subtle),
        ),
      ),
    );
  }
}

/// Tab 栏：文档 / 精选 / 标签。
class _DocsTabBar extends StatelessWidget {
  const _DocsTabBar({
    required this.theme,
    required this.tabIndex,
    required this.onTabChanged,
  });

  final ThemeData theme;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  static const _tabs = ['文档', '精选', '标签'];

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

/// 分组文档列表。
///
/// - Tab 0（文档）：按 sections 渲染组头 + AllDocRow。
/// - Tab 1（精选）：仅渲染 isFavorite 文档，不分组。
/// - Tab 2（标签）：空态（暂无标签维度）。
class _GroupedDocList extends StatelessWidget {
  const _GroupedDocList({
    required this.theme,
    required this.tabIndex,
    required this.sections,
    required this.onOpenDoc,
  });

  final ThemeData theme;
  final int tabIndex;
  final List<AllDocSection> sections;
  final void Function(AllDoc doc) onOpenDoc;

  @override
  Widget build(BuildContext context) {
    if (tabIndex == 1) {
      // 精选：仅 favorite
      final favorites =
          sections.expand((s) => s.docs).where((d) => d.isFavorite).toList();
      if (favorites.isEmpty) {
        return _TabEmptyState(
          theme: theme,
          text: '暂无精选文档',
          tip: '点击文档行星标可添加到精选',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: favorites.length,
        separatorBuilder: (context, index) =>
            Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.08)),
        itemBuilder: (context, i) => AllDocRow(
          doc: favorites[i],
          onOpenDoc: () => onOpenDoc(favorites[i]),
        ),
      );
    }

    if (tabIndex == 2) {
      // 标签：空态
      return _TabEmptyState(
        theme: theme,
        text: '暂无标签',
        tip: '使用文件夹与精选整理文档',
      );
    }

    // 文档：分组
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
                    onToggleFavorite: () {},
                    onMenu: () {},
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
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: subtle,
              ),
            ),
          ),
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.add_rounded, size: 16, color: subtle),
            ),
          ),
        ],
      ),
    );
  }
}

/// 页面级空态。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final subtle = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dashboard_outlined, size: 56, color: subtle),
          const SizedBox(height: 12),
          Text(
            '暂无文档',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '点击右上角「新建文档」创建你的第一份文档',
            style: TextStyle(fontSize: 12.5, color: subtle),
          ),
        ],
      ),
    );
  }
}

/// Tab 级空态（精选/标签）。
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
