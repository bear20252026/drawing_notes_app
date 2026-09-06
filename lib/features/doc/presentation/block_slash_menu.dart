// / 菜单浮层：键入 / 时弹出类型选择面板。
// 支持搜索过滤 + 分组展示。
// 仅依赖 notes 展示层与 domain 模型。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
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
  static const List<SlashItem> options = [
    SlashItem(
      type: NoteBlockType.text,
      label: '段落',
      icon: Icons.text_fields,
      group: SlashItemGroup.basic,
      description: '普通文本',
    ),
    SlashItem(
      type: NoteBlockType.heading,
      label: '标题 1',
      icon: Icons.title,
      group: SlashItemGroup.basic,
      description: '最大标题',
    ),
    SlashItem(
      type: NoteBlockType.heading,
      label: '标题 2',
      icon: Icons.title,
      group: SlashItemGroup.basic,
      description: '二级标题',
    ),
    SlashItem(
      type: NoteBlockType.heading,
      label: '标题 3',
      icon: Icons.title,
      group: SlashItemGroup.basic,
      description: '三级标题',
    ),
    SlashItem(
      type: NoteBlockType.todo,
      label: '待办事项',
      icon: Icons.check_box,
      group: SlashItemGroup.basic,
      description: '勾选框',
    ),
    SlashItem(
      type: NoteBlockType.bullet,
      label: '无序列表',
      icon: Icons.format_list_bulleted,
      group: SlashItemGroup.basic,
      description: '圆点列表',
    ),
    SlashItem(
      type: NoteBlockType.ordered,
      label: '有序列表',
      icon: Icons.format_list_numbered,
      group: SlashItemGroup.basic,
      description: '数字列表',
    ),
    SlashItem(
      type: NoteBlockType.quote,
      label: '引用',
      icon: Icons.format_quote,
      group: SlashItemGroup.quoteCode,
      description: '引用文本',
    ),
    SlashItem(
      type: NoteBlockType.code,
      label: '代码块',
      icon: Icons.code,
      group: SlashItemGroup.quoteCode,
      description: '等宽代码',
    ),
    SlashItem(
      type: NoteBlockType.image,
      label: '图片',
      icon: Icons.image,
      group: SlashItemGroup.media,
      description: '插入图片',
    ),
    SlashItem(
      type: NoteBlockType.link,
      label: '链接',
      icon: Icons.link,
      group: SlashItemGroup.media,
      description: '网页链接',
    ),
    SlashItem(
      type: NoteBlockType.canvas,
      label: '画布',
      icon: Icons.brush,
      group: SlashItemGroup.embed,
      description: '内嵌画布',
    ),
    SlashItem(
      type: NoteBlockType.chart,
      label: '图表',
      icon: Icons.bar_chart,
      group: SlashItemGroup.embed,
      description: '数据图表',
    ),
    SlashItem(
      type: NoteBlockType.table,
      label: '表格',
      icon: Icons.table_chart,
      group: SlashItemGroup.embed,
      description: '数据表格',
    ),
    SlashItem(
      type: NoteBlockType.database,
      label: '数据库',
      icon: Icons.grid_view,
      group: SlashItemGroup.embed,
      description: '数据库视图',
    ),
    SlashItem(
      type: NoteBlockType.toggle,
      label: '切换列表',
      icon: Icons.expand_more,
      group: SlashItemGroup.basic,
      description: '可折叠列表',
    ),
    SlashItem(
      type: NoteBlockType.divider,
      label: '分割线',
      icon: Icons.horizontal_rule,
      group: SlashItemGroup.other,
      description: '分隔线',
    ),
    SlashItem(
      type: NoteBlockType.callout,
      label: '提示',
      icon: Icons.info_outline,
      group: SlashItemGroup.other,
      description: '高亮提示',
    ),
  ];

  @override
  State<BlockSlashMenu> createState() => _BlockSlashMenuState();
}

class _BlockSlashMenuState extends State<BlockSlashMenu> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  int _selectedIndex = 0;

  /// 当前可见项（扁平化，用于索引选择）。
  List<SlashItem> _visibleItems = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _visibleItems = BlockSlashMenu.options;
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
      _visibleItems = filterSlashItems(
        BlockSlashMenu.options,
        _searchController.text,
      );
      _selectedIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupSlashItems(_visibleItems);
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
              child: _visibleItems.isEmpty
                  ? _buildEmptyState(context)
                  : _buildGroupedList(context, groups),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext _) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: const InputDecoration(
          hintText: '搜索类型...',
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          '无匹配项',
          style: TextStyle(
            fontSize: 13,
            color: AppleColor.mutedOf(Theme.of(context).colorScheme),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupedList(
    BuildContext _,
    List<MapEntry<SlashItemGroup, List<SlashItem>>> groups,
  ) {
    // 构建扁平索引映射：每个可见项在 _visibleItems 中的位置。
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _countGroupedItems(groups),
      itemBuilder: (context, index) {
        return _buildGroupedItem(context, groups, index);
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
        final globalIndex = _visibleItems.indexOf(item);
        return _buildItemRow(context, item, globalIndex);
      }
      current += entry.value.length;
    }
    return const SizedBox.shrink();
  }

  Widget _buildGroupHeader(BuildContext context, SlashItemGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          group.title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppleColor.mutedOf(Theme.of(context).colorScheme),
            letterSpacing: 0.5,
          ),
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
                  Text(item.label, style: const TextStyle(fontSize: 14)),
                  if (item.description != null)
                    Text(
                      item.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppleColor.mutedOf(
                          Theme.of(context).colorScheme,
                        ),
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
