// BlockEditorWidget——块编辑器（AFFiNE BlockSuite 借鉴——2026-08-24）。
//
// 参考 BlockSuite 五层架构：Component → Block → Store → Extension → Preset。
// 本地化：NoteBlock + BlockEditorWidget + SlashCommandService。
//
// 功能：
// - 一切皆块（文本块/标题块/列表块/代码块/引用块/分隔线块）
// - / 命令菜单（插入块类型）
// - 块可拖拽排序
// - Enter 新增块、Backspace 删除空块
//
// 版权：AFFiNE（BSL 1.1——BlockSuite MIT）——仅概念借鉴——NOTICE 已记录。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:editor_core/editor_core.dart';

/// 块编辑器 Widget（AFFiNE BlockSuite 借鉴——一切皆块）。
///
/// 受控组件：blocks 来自父组件，onChanged 回调变更。
/// 支持：10+ 种块类型 + / 命令菜单 + 拖拽排序。
class BlockEditorWidget extends StatefulWidget {
  const BlockEditorWidget({
    super.key,
    required this.blocks,
    required this.onChanged,
    this.onSlashCommand,
  });

  /// 块列表（来自父组件——受控模式）。
  final List<NoteBlock> blocks;

  /// 块变更回调（父组件更新状态 + 持久化）。
  final ValueChanged<List<NoteBlock>> onChanged;

  /// / 命令回调（可选——自定义处理）。
  final void Function(SlashCommand command, int blockIndex)? onSlashCommand;

  @override
  State<BlockEditorWidget> createState() => _BlockEditorWidgetState();
}

class _BlockEditorWidgetState extends State<BlockEditorWidget> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  late int _currentBlockCount;

  /// / 命令菜单状态。
  bool _showSlashMenu = false;
  int _slashMenuBlockIndex = -1;
  List<SlashCommand> _slashCommands = [];

  final SlashCommandService _slashService = const SlashCommandService();

  @override
  void initState() {
    super.initState();
    _currentBlockCount = widget.blocks.length;
    _controllers = widget.blocks
        .map((b) => TextEditingController(text: b.content))
        .toList();
    _focusNodes = List.generate(widget.blocks.length, (_) => FocusNode());
  }

  @override
  void didUpdateWidget(BlockEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newCount = widget.blocks.length;
    if (newCount != _currentBlockCount) {
      _rebuildControllers();
      _currentBlockCount = newCount;
    }
  }

  void _rebuildControllers() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _controllers = widget.blocks
        .map((b) => TextEditingController(text: b.content))
        .toList();
    _focusNodes = List.generate(widget.blocks.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ──────────────────────────── 块操作 ────────────────────────────

  /// 更新块内容。
  void _updateBlock(int index, String text) {
    if (index >= widget.blocks.length) return;

    // 检测 / 命令
    if (SlashCommandService.isSlash(text)) {
      final commands = _slashService.search(text);
      setState(() {
        _showSlashMenu = commands.isNotEmpty;
        _slashMenuBlockIndex = index;
        _slashCommands = commands;
      });
    } else {
      setState(() {
        _showSlashMenu = false;
      });
    }

    final updated = List<NoteBlock>.from(widget.blocks);
    updated[index] = updated[index].copyWith(content: text);
    widget.onChanged(updated);
  }

  /// 新增块（Enter 键——在指定位置后插入新段落块）。
  void _addBlock(int afterIndex) {
    final updated = List<NoteBlock>.from(widget.blocks);
    final newId = 'block_${DateTime.now().millisecondsSinceEpoch}';
    updated.insert(
      afterIndex + 1,
      NoteBlock(id: newId, type: NoteBlockType.paragraph),
    );
    widget.onChanged(updated);
    // 聚焦新块
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetIndex = afterIndex + 1;
      if (targetIndex < _focusNodes.length) {
        _focusNodes[targetIndex].requestFocus();
      }
    });
  }

  /// 删除块（Backspace 空块——合并到上一块）。
  void _deleteBlock(int index) {
    if (index <= 0) return; // 保留第一个块
    if (widget.blocks.length <= 1) return; // 至少保留一个块

    final updated = List<NoteBlock>.from(widget.blocks);
    updated.removeAt(index);
    widget.onChanged(updated);

    // 聚焦前一块末尾
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetIndex = index - 1;
      if (targetIndex < _focusNodes.length) {
        _focusNodes[targetIndex].requestFocus();
        final controller = _controllers[targetIndex];
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
      }
    });
  }

  /// 转换块类型（/ 命令或工具栏）。
  void _convertBlock(int index, NoteBlockType newType) {
    if (index >= widget.blocks.length) return;
    final updated = List<NoteBlock>.from(widget.blocks);
    updated[index] = updated[index].copyWith(type: newType);
    widget.onChanged(updated);
    setState(() {
      _showSlashMenu = false;
    });
  }

  /// 应用 / 命令。
  void _applySlashCommand(SlashCommand command, int blockIndex) {
    final newType = NoteBlock.fromSlashType(command.type);
    _convertBlock(blockIndex, newType);

    // 清除 / 前缀
    if (blockIndex < _controllers.length) {
      _controllers[blockIndex].text = '';
      _updateBlock(blockIndex, '');
    }

    if (widget.onSlashCommand != null) {
      widget.onSlashCommand!(command, blockIndex);
    }
  }

  /// 移动块（拖拽排序）。
  void _moveBlock(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    final updated = List<NoteBlock>.from(widget.blocks);
    final block = updated.removeAt(fromIndex);
    final insertIndex = toIndex > fromIndex ? toIndex - 1 : toIndex;
    updated.insert(insertIndex, block);
    widget.onChanged(updated);
  }

  // ──────────────────────────── 构建 UI ────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 块列表
        GestureDetector(
          onTap: () {
            // 点击空白聚焦最后一块
            if (_focusNodes.isNotEmpty) {
              _focusNodes.last.requestFocus();
            }
            // 关闭 / 菜单
            if (_showSlashMenu) {
              setState(() => _showSlashMenu = false);
            }
          },
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
            itemCount: widget.blocks.length,
            // ignore: deprecated_member_use
            onReorder: _moveBlock,
            itemBuilder: (context, index) {
              if (index >= widget.blocks.length) {
                return const SizedBox.shrink(key: ValueKey('empty'));
              }
              final block = widget.blocks[index];
              return _buildBlockWidget(context, index, block);
            },
          ),
        ),

        // / 命令菜单
        if (_showSlashMenu && _slashMenuBlockIndex >= 0)
          _buildSlashMenu(context),
      ],
    );
  }

  Widget _buildBlockWidget(BuildContext context, int index, NoteBlock block) {
    if (index >= _controllers.length) {
      return const SizedBox.shrink(key: ValueKey('overflow'));
    }

    final controller = _controllers[index];

    // 同步控制器文本
    if (controller.text != block.content) {
      final oldOffset = controller.selection.extentOffset;
      controller.text = block.content;
      try {
        final safeOffset = oldOffset.clamp(0, controller.text.length);
        controller.selection = TextSelection.collapsed(offset: safeOffset);
      } catch (_) {}
    }

    // 分隔线块——特殊渲染
    if (block.type == NoteBlockType.divider) {
      return ReorderableDragStartListener(
        key: ValueKey('block-${block.id}'),
        index: index,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(child: Divider(thickness: 1)),
              IconButton(
                icon: Icon(Icons.close, size: 16),
                onPressed: () => _deleteBlock(index),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
        ),
      );
    }

    return ReorderableDragStartListener(
      key: ValueKey('block-${block.id}'),
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 块类型图标（拖拽手柄）
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Icon(
                _getBlockIcon(block.type),
                size: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            // 块内容
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;

                  // Enter：新增块
                  if (event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _addBlock(index);
                    return KeyEventResult.handled;
                  }

                  // Backspace：删除空块
                  if (event.logicalKey == LogicalKeyboardKey.backspace &&
                      controller.text.isEmpty &&
                      index > 0) {
                    _deleteBlock(index);
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: _buildTextField(context, block, controller, index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context,
    NoteBlock block,
    TextEditingController controller,
    int index,
  ) {
    final theme = Theme.of(context);

    switch (block.type) {
      case NoteBlockType.heading1:
        return TextField(
          controller: controller,
          focusNode: _focusNodes[index],
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            hintText: '标题 1',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (text) => _updateBlock(index, text),
          textInputAction: TextInputAction.next,
        );

      case NoteBlockType.heading2:
        return TextField(
          controller: controller,
          focusNode: _focusNodes[index],
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            hintText: '标题 2',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (text) => _updateBlock(index, text),
          textInputAction: TextInputAction.next,
        );

      case NoteBlockType.heading3:
        return TextField(
          controller: controller,
          focusNode: _focusNodes[index],
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            hintText: '标题 3',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (text) => _updateBlock(index, text),
          textInputAction: TextInputAction.next,
        );

      case NoteBlockType.bulletList:
        return TextField(
          controller: controller,
          focusNode: _focusNodes[index],
          maxLines: null,
          minLines: 1,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText: '列表项',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            prefixText: '• ',
            prefixStyle: theme.textTheme.bodyLarge,
          ),
          onChanged: (text) => _updateBlock(index, text),
        );

      case NoteBlockType.numberedList:
        return TextField(
          controller: controller,
          focusNode: _focusNodes[index],
          maxLines: null,
          minLines: 1,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText: '列表项',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            prefixText: '${index + 1}. ',
            prefixStyle: theme.textTheme.bodyLarge,
          ),
          onChanged: (text) => _updateBlock(index, text),
        );

      case NoteBlockType.code:
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: controller,
            focusNode: _focusNodes[index],
            maxLines: null,
            minLines: 2,
            keyboardType: TextInputType.multiline,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: '输入代码…',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (text) => _updateBlock(index, text),
          ),
        );

      case NoteBlockType.quote:
        return Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.primary,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 12),
          child: TextField(
            controller: controller,
            focusNode: _focusNodes[index],
            maxLines: null,
            minLines: 1,
            keyboardType: TextInputType.multiline,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            decoration: InputDecoration(
              hintText: '引用…',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (text) => _updateBlock(index, text),
          ),
        );

      case NoteBlockType.image:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (block.meta['url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  block.meta['url'] as String,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Container(
                    height: 100,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Center(child: Text('图片加载失败')),
                  ),
                ),
              )
            else
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(Icons.image, size: 48, color: theme.colorScheme.outline),
                ),
              ),
            if (block.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  block.content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );

      case NoteBlockType.table:
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: Text('表格块（详见 TableViewWidget）',
              style: theme.textTheme.bodySmall),
        );

      case NoteBlockType.paragraph:
      default:
        return TextField(
          controller: controller,
          focusNode: _focusNodes[index],
          maxLines: null,
          minLines: 1,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: '输入文字，或输入 / 打开命令菜单…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (text) => _updateBlock(index, text),
        );
    }
  }

  /// / 命令菜单。
  Widget _buildSlashMenu(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned(
      left: 40,
      bottom: 100,
      child: Material(
        elevation: 8,
 borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 220,
          constraints: BoxConstraints(maxHeight: 300),
 decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(vertical: 4),
            itemCount: _slashCommands.length,
            itemBuilder: (context, index) {
              final cmd = _slashCommands[index];
              return ListTile(
                dense: true,
 leading: Text(cmd.icon, style: TextStyle(fontSize: 18)),
                title: Text(cmd.name),
                onTap: () => _applySlashCommand(cmd, _slashMenuBlockIndex),
              );
            },
          ),
        ),
      ),
    );
  }

  IconData _getBlockIcon(NoteBlockType type) {
    switch (type) {
      case NoteBlockType.paragraph:
        return Icons.drag_indicator;
      case NoteBlockType.heading1:
      case NoteBlockType.heading2:
      case NoteBlockType.heading3:
        return Icons.title;
      case NoteBlockType.bulletList:
        return Icons.format_list_bulleted;
      case NoteBlockType.numberedList:
        return Icons.format_list_numbered;
      case NoteBlockType.code:
        return Icons.code;
      case NoteBlockType.quote:
        return Icons.format_quote;
      case NoteBlockType.divider:
        return Icons.horizontal_rule;
      case NoteBlockType.image:
        return Icons.image;
      case NoteBlockType.table:
        return Icons.table_chart;
    }
  }
}
