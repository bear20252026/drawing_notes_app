// / 菜单浮层：键入 / 时弹出类型选择面板。
// 支持搜索过滤 + 分组展示。
// 仅依赖 notes 展示层与 domain 模型。

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:drawing_notes_app/core/documents/note_block.dart';
import '../../../core/theme/apple_design.dart';

/// / 菜单分组类别。
enum SlashItemGroup {
  basic('基础'),
  quoteCode('引用与代码'),
  media('媒体'),
  embed('嵌入'),
  other('其他');

  const SlashItemGroup(this.title);
  final String title;
}

/// / 菜单中每个类型选项的描述。
class SlashItem {
  const SlashItem({
    required this.type,
    required this.label,
    required this.icon,
    required this.group,
    this.description,
  });

  final NoteBlockType type;
  final String label;
  final IconData icon;
  final SlashItemGroup group;
  final String? description;
}

/// 按关键词过滤 / 菜单项（大小写不敏感，匹配 label 或描述）。
/// 空 query 返回全部。
List<SlashItem> filterSlashItems(List<SlashItem> items, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return items
      .where(
        (item) =>
            item.label.toLowerCase().contains(q) ||
            (item.description?.toLowerCase().contains(q) ?? false),
      )
      .toList();
}

/// 按类别分组 / 菜单项（类别顺序固定，组内保持原始顺序）。
List<MapEntry<SlashItemGroup, List<SlashItem>>> groupSlashItems(
  List<SlashItem> items,
) {
  final orderedGroups = <SlashItemGroup, List<SlashItem>>{};
  for (final group in SlashItemGroup.values) {
    orderedGroups[group] = [];
  }
  for (final item in items) {
    orderedGroups[item.group]!.add(item);
  }
  return orderedGroups.entries.where((e) => e.value.isNotEmpty).toList();
}

/// / 菜单浮层组件。
///
/// 在文本块内键入 `/` 时弹出，展示可切换的块类型列表。
/// 支持搜索过滤、分组展示、键盘上下选择 + Enter 确认，鼠标点击选择。
class BlockSlashMenu extends StatefulWidget {
  const BlockSlashMenu({
    super.key,
    required this.onSelected,
    required this.onDismiss,
  });

  /// 选中某个类型后的回调。
  final void Function(NoteBlockType type) onSelected;

  /// 取消/关闭菜单的回调。
  final VoidCallback onDismiss;

  /// 全部可选类型（按 AFFiNE 常用顺序，含分组）。
  ///
  /// L-01（审计 2026-09-27）：工厂构造接 AppLocalizations——label/description
  /// 直接产出当前语言文案，搜索过滤与展示同源；替代旧的「const 中文 +
  /// 按中文串反查 key」方案（v1.17.37 补附件项时即漏配映射，en 下穿帮）。
  /// l10n 缺失（部分测试装配）时中文兜底。
  static List<SlashItem> optionsOf(AppLocalizations? l10n) {
    String text(String zh, String Function(AppLocalizations) key) =>
        l10n == null ? zh : key(l10n);
    return [
      SlashItem(
        type: NoteBlockType.text,
        label: text('段落', (l) => l.sgItemParagraph),
        icon: Icons.text_fields,
        group: SlashItemGroup.basic,
        description: text('普通文本', (l) => l.sgItemParagraphDesc),
      ),
      SlashItem(
        type: NoteBlockType.heading,
        label: text('标题 1', (l) => l.sgItemH1),
        icon: Icons.title,
        group: SlashItemGroup.basic,
        description: text('最大标题', (l) => l.sgItemH1Desc),
      ),
      SlashItem(
        type: NoteBlockType.heading,
        label: text('标题 2', (l) => l.sgItemH2),
        icon: Icons.title,
        group: SlashItemGroup.basic,
        description: text('二级标题', (l) => l.sgItemH2Desc),
      ),
      SlashItem(
        type: NoteBlockType.heading,
        label: text('标题 3', (l) => l.sgItemH3),
        icon: Icons.title,
        group: SlashItemGroup.basic,
        description: text('三级标题', (l) => l.sgItemH3Desc),
      ),
      SlashItem(
        type: NoteBlockType.todo,
        label: text('待办事项', (l) => l.sgItemTodo),
        icon: Icons.check_box,
        group: SlashItemGroup.basic,
        description: text('勾选框', (l) => l.sgItemTodoDesc),
      ),
      SlashItem(
        type: NoteBlockType.bullet,
        label: text('无序列表', (l) => l.sgItemBullet),
        icon: Icons.format_list_bulleted,
        group: SlashItemGroup.basic,
        description: text('圆点列表', (l) => l.sgItemBulletDesc),
      ),
      SlashItem(
        type: NoteBlockType.ordered,
        label: text('有序列表', (l) => l.sgItemOrdered),
        icon: Icons.format_list_numbered,
        group: SlashItemGroup.basic,
        description: text('数字列表', (l) => l.sgItemOrderedDesc),
      ),
      SlashItem(
        type: NoteBlockType.quote,
        label: text('引用', (l) => l.sgItemQuote),
        icon: Icons.format_quote,
        group: SlashItemGroup.quoteCode,
        description: text('引用文本', (l) => l.sgItemQuoteDesc),
      ),
      SlashItem(
        type: NoteBlockType.code,
        label: text('代码块', (l) => l.sgItemCode),
        icon: Icons.code,
        group: SlashItemGroup.quoteCode,
        description: text('等宽代码', (l) => l.sgItemCodeDesc),
      ),
      SlashItem(
        type: NoteBlockType.image,
        label: text('图片', (l) => l.sgItemImage),
        icon: Icons.image,
        group: SlashItemGroup.media,
        description: text('插入图片', (l) => l.sgItemImageDesc),
      ),
      SlashItem(
        type: NoteBlockType.link,
        label: text('链接', (l) => l.sgItemLink),
        icon: Icons.link,
        group: SlashItemGroup.media,
        description: text('网页链接', (l) => l.sgItemLinkDesc),
      ),
      SlashItem(
        type: NoteBlockType.canvas,
        label: text('画布', (l) => l.sgItemCanvas),
        icon: Icons.brush,
        group: SlashItemGroup.embed,
        description: text('内嵌画布', (l) => l.sgItemCanvasDesc),
      ),
      SlashItem(
        type: NoteBlockType.chart,
        label: text('图表', (l) => l.sgItemChart),
        icon: Icons.bar_chart,
        group: SlashItemGroup.embed,
        description: text('数据图表', (l) => l.sgItemChartDesc),
      ),
      SlashItem(
        type: NoteBlockType.table,
        label: text('表格', (l) => l.sgItemTable),
        icon: Icons.table_chart,
        group: SlashItemGroup.embed,
        description: text('数据表格', (l) => l.sgItemTableDesc),
      ),
      SlashItem(
        type: NoteBlockType.database,
        label: text('数据库', (l) => l.sgItemDatabase),
        icon: Icons.grid_view,
        group: SlashItemGroup.embed,
        description: text('数据库视图', (l) => l.sgItemDatabaseDesc),
      ),
      // T-12（审计 2026-09-27）：附件入口补全——插入链路（_changeBlockType
      // → updateType → 渲染/工具栏分支）此前已齐备，唯独斜杠菜单漏了本项
      // （原测试只断言子集未发现；全等断言上线即抓到）。
      SlashItem(
        type: NoteBlockType.attachment,
        label: text('附件', (l) => l.sgItemAttachment),
        icon: Icons.attach_file,
        group: SlashItemGroup.embed,
        description: text('添加文件附件', (l) => l.sgItemAttachmentDesc),
      ),
      SlashItem(
        type: NoteBlockType.toggle,
        label: text('切换列表', (l) => l.sgItemToggle),
        icon: Icons.expand_more,
        group: SlashItemGroup.basic,
        description: text('可折叠列表', (l) => l.sgItemToggleDesc),
      ),
      SlashItem(
        type: NoteBlockType.divider,
        label: text('分割线', (l) => l.sgItemDivider),
        icon: Icons.horizontal_rule,
        group: SlashItemGroup.other,
        description: text('分隔线', (l) => l.sgItemDividerDesc),
      ),
      SlashItem(
        type: NoteBlockType.callout,
        label: text('提示', (l) => l.sgItemCallout),
        icon: Icons.info_outline,
        group: SlashItemGroup.other,
        description: text('高亮提示', (l) => l.sgItemCalloutDesc),
      ),
    ];
  }

  @override
  State<BlockSlashMenu> createState() => _BlockSlashMenuState();
}

class _BlockSlashMenuState extends State<BlockSlashMenu> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  int _selectedIndex = 0;

  /// 全部菜单项（按当前 locale 产出，locale 切换即时生效）。
  List<SlashItem> get _allItems =>
      BlockSlashMenu.optionsOf(AppLocalizations.of(context));

  /// 当前可见项（按搜索词过滤，扁平化，用于索引选择）。
  List<SlashItem> get _visibleItems =>
      filterSlashItems(_allItems, _searchController.text);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _selectedIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems;
    final groups = groupSlashItems(visibleItems);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(AppleRadius.sm),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 360),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSearchField(context),
            const Divider(height: 1),
            Flexible(
              child: visibleItems.isEmpty
                  ? _buildEmptyState(context)
                  : _buildGroupedList(context, groups, visibleItems),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText:
              AppLocalizations.of(context)?.sgSearchHint ?? '搜索类型…',
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        style: AppleType.controlStyle(
          Theme.of(context).colorScheme.onSurface,
        ).copyWith(fontWeight: FontWeight.w400),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          AppLocalizations.of(context)?.slashNoMatch ?? '无匹配项',
          style: AppleType.controlStyle(
            AppleColor.mutedOf(Theme.of(context).colorScheme),
          ).copyWith(fontWeight: FontWeight.w400),
        ),
      ),
    );
  }

  Widget _buildGroupedList(
    BuildContext _,
    List<MapEntry<SlashItemGroup, List<SlashItem>>> groups,
    List<SlashItem> visibleItems,
  ) {
    // 构建扁平索引映射：每个可见项在可见列表中的位置。
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _countGroupedItems(groups),
      itemBuilder: (context, index) {
        return _buildGroupedItem(context, groups, visibleItems, index);
      },
    );
  }

  int _countGroupedItems(
    List<MapEntry<SlashItemGroup, List<SlashItem>>> groups,
  ) {
    // 每个组：1 个标题 + 组内项数
    var count = 0;
    for (final entry in groups) {
      count += 1 + entry.value.length;
    }
    return count;
  }

  Widget _buildGroupedItem(
    BuildContext context,
    List<MapEntry<SlashItemGroup, List<SlashItem>>> groups,
    List<SlashItem> visibleItems,
    int flatIndex,
  ) {
    var current = 0;
    for (final entry in groups) {
      // 组标题
      if (flatIndex == current) {
        return _buildGroupHeader(context, entry.key);
      }
      current++;
      // 组内项
      if (flatIndex < current + entry.value.length) {
        final itemIndexInGroup = flatIndex - current;
        final item = entry.value[itemIndexInGroup];
        final globalIndex = visibleItems.indexOf(item);
        return _buildItemRow(context, item, globalIndex);
      }
      current += entry.value.length;
    }
    return const SizedBox.shrink();
  }

  Widget _buildGroupHeader(BuildContext context, SlashItemGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _slashGroupTitleOf(context, group) ?? group.title,
          style: AppleType.captionStyle(
            AppleColor.mutedOf(Theme.of(context).colorScheme),
          ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, SlashItem item, int globalIndex) {
    final isSelected = globalIndex == _selectedIndex;
    return InkWell(
      onTap: () => _selectItem(item),
      onHover: (_) => setState(() => _selectedIndex = globalIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        child: Row(
          children: [
            Icon(item.icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: AppleType.controlStyle(
                      Theme.of(context).colorScheme.onSurface,
                    ).copyWith(fontWeight: FontWeight.w400),
                  ),
                  if (item.description != null)
                    Text(
                      item.description!,
                      style: AppleType.captionStyle(
                        AppleColor.mutedOf(Theme.of(context).colorScheme),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 处理键盘导航（上下选择 / Enter 确认 / Escape 关闭）。
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_visibleItems.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % _visibleItems.length;
        });
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_visibleItems.isNotEmpty) {
        setState(() {
          _selectedIndex =
              (_selectedIndex - 1 + _visibleItems.length) %
              _visibleItems.length;
        });
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_visibleItems.isNotEmpty) {
        _selectItem(_visibleItems[_selectedIndex]);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _selectItem(SlashItem item) {
    widget.onSelected(item.type);
  }
}

/// i18n（E1）：/ 菜单分组头按 locale 解析（enum 的 title 为 zh 兜底）。
String? _slashGroupTitleOf(BuildContext context, SlashItemGroup group) {
  final l10n = AppLocalizations.of(context);
  switch (group) {
    case SlashItemGroup.basic:
      return l10n?.sgBasic ?? '基础';
    case SlashItemGroup.quoteCode:
      return l10n?.sgQuoteCode ?? '引用与代码';
    case SlashItemGroup.media:
      return l10n?.sgMedia ?? '媒体';
    case SlashItemGroup.embed:
      return l10n?.sgEmbed ?? '嵌入';
    case SlashItemGroup.other:
      return l10n?.sgOther ?? '其他';
  }
}
