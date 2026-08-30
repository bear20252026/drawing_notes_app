part of 'editor_page.dart';

/// 命令面板对话框（Ctrl/Cmd+K，对齐 Excalidraw CommandPalette）。
///
/// 独立 StatefulWidget：搜索框 [TextEditingController] 生命周期由 State 管理，
/// 对话框退出动画完成后才释放，避免关闭期间重建访问已释放对象。
/// 命令条目完全来自统一注册表 [CommandRegistry]，只展示当前可执行命令。
class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({
    required this.registry,
    this.initialLastCommandId,
  });

  final CommandRegistry registry;
  final String? initialLastCommandId;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
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
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(_commandCategoryIcon(command.category), size: 19),
        title: Text(command.label),
        subtitle: recentItem ? const Text('最近使用') : null,
        trailing: command.shortcut.isEmpty
            ? null
            : Text(
                command.shortcut,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
        onTap: () => Navigator.of(context).pop(command.id),
      );
    }

    return AlertDialog(
      title: const Text('命令面板'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _queryController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (commands.isNotEmpty) {
                  Navigator.of(context).pop(commands.first.id);
                }
              },
              decoration: const InputDecoration(
                hintText: '搜索操作、工具或导出格式…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: commands.isEmpty
                  ? const Center(child: Text('没有可执行的匹配命令'))
                  : ListView(
                      children: [
                        if (showRecent) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(8, 4, 8, 2),
                            child: Text('最近使用'),
                          ),
                          commandTile(recent, recentItem: true),
                          const Divider(),
                        ],
                        for (final category in EditorCommandCategory.values)
                          if (grouped[category]?.isNotEmpty ?? false) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
                              child: Text(
                                category.label,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                            for (final command in grouped[category]!)
                              if (!showRecent || command.id != recent.id)
                                commandTile(command),
                          ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 文字输入对话框的返回结果（文本 + 字号）。
class _TextDialogResult {
  const _TextDialogResult({required this.text, required this.fontSize});

  final String text;
  final double fontSize;
}

/// 文字输入对话框（支持字号选择，用于创建"特殊标签"）。
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog();

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final TextEditingController _controller = TextEditingController();
  double _fontSize = 28;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入文字'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '请输入文字内容',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          // 字号调节滑块
          Row(
            children: [
              const Icon(Icons.format_size, size: 18),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 8,
                  max: 200,
                  label: _fontSize.round().toString(),
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${_fontSize.round()}',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_TextDialogResult(text: _controller.text, fontSize: _fontSize)),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 右键上下文菜单动作。
enum _CtxAction {
  copyStyle,
  group,
  ungroup,
  link,
  delete,
  bringToFront,
  sendToBack,
}

/// 右上角主菜单项（对齐 Excalidraw main-menu）。
enum _MainMenuItem {
  clearCanvas,
  copyPng,
  exportPng,
  exportSvg,
  exportPdf,
  exportJson,
  exportPptx,
  exportText,
  exportWord,
  commandPalette,
  chart,
  presentation,
  library,
  stats,
  shortcuts,
  toggleInfinite,
}
