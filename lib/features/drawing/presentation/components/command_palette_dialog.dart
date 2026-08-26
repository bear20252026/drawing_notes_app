/// 命令面板对话框（Ctrl/Cmd+K，对齐 Excalidraw CommandPalette）。
///
/// 独立 StatefulWidget：搜索框生命周期由 State 管理，
/// 对话框退出动画完成后才释放。
/// 命令条目完全来自统一注册表 [CommandRegistry]。
///
/// 从 editor_page_dialogs.dart 拆分为独立组件。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../application/command_registry.dart';

/// 命令面板对话框。
class CommandPaletteDialog extends StatefulWidget {
  const CommandPaletteDialog({
    super.key,
    required this.registry,
    this.initialLastCommandId,
  });

  final CommandRegistry registry;
  final String? initialLastCommandId;

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final TextEditingController _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  IconData _commandCategoryIcon(EditorCommandCategory category) {
    return switch (category) {
      EditorCommandCategory.edit => Icons.edit_outlined,
      EditorCommandCategory.format => Icons.format_size_rounded,
      EditorCommandCategory.insert => Icons.add_box_outlined,
      EditorCommandCategory.arrange => Icons.layers_outlined,
      EditorCommandCategory.view => Icons.visibility_outlined,
      EditorCommandCategory.export => Icons.ios_share_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text;
    final commands = widget.registry.search(query);
    final grouped = <EditorCommandCategory, List<EditorCommand>>{};
    for (final command in commands) {
      grouped.putIfAbsent(command.category, () => []).add(command);
    }
    final recent = query.trim().isEmpty
        ? widget.registry.find(widget.initialLastCommandId ?? '')
        : null;
    final showRecent = recent != null && recent.available;

    Widget commandTile(EditorCommand command, {bool recentItem = false}) {
      return GestureDetector(
        onTap: () => Navigator.of(context).pop(command.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(_commandCategoryIcon(command.category), size: 20,
                  color: const Color(0xFF0066CC)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      command.label,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF1D1D1F)),
                    ),
                    if (recentItem)
                      const Text(
                        '最近使用',
                        style:
                            TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                      ),
                  ],
                ),
              ),
              if (command.shortcut.isNotEmpty)
                Text(
                  command.shortcut,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                ),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final textColor =
        isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
    final subTextColor =
        isDark ? const Color(0xFFEBEBF5) : const Color(0xFF6E6E73);
    final dividerColor =
        isDark ? const Color(0xFF38383A) : const Color(0xFFE0E0E0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 520,
        height: 460,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                '命令面板',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    CupertinoTextField(
                      controller: _queryController,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (commands.isNotEmpty) {
                          Navigator.of(context).pop(commands.first.id);
                        }
                      },
                      placeholder: '搜索操作、工具或导出格式…',
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(CupertinoIcons.search,
                            size: 18, color: Color(0xFF8E8E93)),
                      ),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF3A3A3C)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: dividerColor),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: commands.isEmpty
                            ? Center(
                                child: Text(
                                  '没有可执行的匹配命令',
                                  style: TextStyle(color: subTextColor),
                                ),
                              )
                            : ListView(
                                children: [
                                  if (showRecent) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          8, 4, 8, 2),
                                      child: Text(
                                        '最近使用',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: subTextColor,
                                        ),
                                      ),
                                    ),
                                    commandTile(recent, recentItem: true),
                                    Container(
                                        height: 0.5, color: dividerColor),
                                  ],
                                  for (final category
                                      in EditorCommandCategory.values)
                                    if (grouped[category]?.isNotEmpty ??
                                        false) ...[
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            8, 10, 8, 2),
                                        child: Text(
                                          category.label,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: subTextColor,
                                          ),
                                        ),
                                      ),
                                      for (final command in grouped[category]!)
                                        if (!showRecent ||
                                            command.id != recent.id)
                                          commandTile(command),
                                    ],
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
