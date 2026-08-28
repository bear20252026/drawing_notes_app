// 由 Claude 团队生成 | Drawing Notes App
// / 菜单浮层：键入 / 时弹出类型选择面板。
// 仅依赖 notes 展示层与 domain 模型。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';

/// / 菜单中每个类型选项的描述。
class SlashMenuOption {
  const SlashMenuOption({
    required this.type,
    required this.label,
    required this.icon,
    this.description,
  });

  final NoteBlockType type;
  final String label;
  final IconData icon;
  final String? description;
}

/// / 菜单浮层组件。
///
/// 在文本块内键入 `/` 时弹出，展示可切换的块类型列表。
/// 支持键盘上下选择 + Enter 确认，鼠标点击选择。
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

  /// 全部可选类型（按 AFFiNE 常用顺序）。
  static const List<SlashMenuOption> options = [
    SlashMenuOption(type: NoteBlockType.text, label: '段落', icon: Icons.text_fields, description: '普通文本'),
    SlashMenuOption(type: NoteBlockType.heading, label: '标题 1', icon: Icons.title, description: '最大标题'),
    SlashMenuOption(type: NoteBlockType.heading, label: '标题 2', icon: Icons.title, description: '二级标题'),
    SlashMenuOption(type: NoteBlockType.heading, label: '标题 3', icon: Icons.title, description: '三级标题'),
    SlashMenuOption(type: NoteBlockType.todo, label: '待办事项', icon: Icons.check_box, description: '勾选框'),
    SlashMenuOption(type: NoteBlockType.bullet, label: '无序列表', icon: Icons.format_list_bulleted, description: '圆点列表'),
    SlashMenuOption(type: NoteBlockType.ordered, label: '有序列表', icon: Icons.format_list_numbered, description: '数字列表'),
    SlashMenuOption(type: NoteBlockType.quote, label: '引用', icon: Icons.format_quote, description: '引用文本'),
    SlashMenuOption(type: NoteBlockType.code, label: '代码块', icon: Icons.code, description: '等宽代码'),
    SlashMenuOption(type: NoteBlockType.divider, label: '分割线', icon: Icons.horizontal_rule, description: '分隔线'),
    SlashMenuOption(type: NoteBlockType.callout, label: '提示', icon: Icons.info_outline, description: '高亮提示'),
    SlashMenuOption(type: NoteBlockType.table, label: '表格', icon: Icons.table_chart, description: '数据表格'),
  ];

  @override
  State<BlockSlashMenu> createState() => _BlockSlashMenuState();
}

class _BlockSlashMenuState extends State<BlockSlashMenu> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 320),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: BlockSlashMenu.options.length,
          itemBuilder: (context, index) {
            final option = BlockSlashMenu.options[index];
            final isSelected = index == _selectedIndex;
            return InkWell(
              onTap: () => _selectOption(index),
              onHover: (_) => setState(() => _selectedIndex = index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : null,
                child: Row(
                  children: [
                    Icon(option.icon, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(option.label, style: const TextStyle(fontSize: 14)),
                          if (option.description != null)
                            Text(
                              option.description!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 处理键盘导航（上下选择 / Enter 确认 / Escape 关闭）。
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % BlockSlashMenu.options.length;
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1 + BlockSlashMenu.options.length) %
            BlockSlashMenu.options.length;
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _selectOption(_selectedIndex);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _selectOption(int index) {
    final option = BlockSlashMenu.options[index];
    widget.onSelected(option.type);
  }
}
