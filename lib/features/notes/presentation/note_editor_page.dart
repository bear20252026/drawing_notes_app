/// 块式笔记编辑器页面（NoteEditorPage）。
///
/// 基于 M0 的 AFFiNE 风格块模型（[NoteBlock] / [NoteBlockEditor]），
/// 实现一个块式编辑器：每个块一个可编辑行，Enter 分块、
/// Backspace 空块合并、工具栏切换块类型。
///
/// 功能：
/// - 每个块一个可编辑行（支持 heading / text / bullet / ordered / todo /
///   quote / code / divider 八种块类型）
/// - Enter：在当前光标位置分块（前半留在当前块，后半进入新块）
/// - Backspace：在空块上退格，合并到前一块
/// - 底部工具栏：切换当前聚焦块的类型
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_editor.dart';
import 'package:drawing_notes_app/features/notes/presentation/embedded_block_view.dart';

/// 块式笔记编辑器页面。
class NoteEditorPage extends StatefulWidget {
  /// 创建块式笔记编辑器页面。
  ///
  /// [embeddedBlockBuilder] 为可选的自定义内嵌块渲染回调，
  /// 由组合根（app_shell）注入，用于渲染 canvas/chart 等复杂内嵌块。
  /// 为 null 时使用内置降级渲染。
  const NoteEditorPage({
    super.key,
    this.embeddedBlockBuilder,
  });

  /// 由组合根注入的自定义内嵌块渲染回调。
  /// 返回 null 时走默认降级渲染。
  final Widget? Function(NoteBlock block)? embeddedBlockBuilder;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

/// 工具栏块类型选项。
class _BlockTypeOption {
  const _BlockTypeOption({
    required this.type,
    required this.label,
    required this.icon,
    required this.tooltip,
  });

  final NoteBlockType type;
  final String label;
  final IconData icon;
  final String tooltip;
}

/// 支持的块类型工具栏列表（顺序即展示顺序）。
const List<_BlockTypeOption> _blockTypeOptions = [
  _BlockTypeOption(
    type: NoteBlockType.text,
    label: '¶',
    icon: Icons.notes_outlined,
    tooltip: '段落',
  ),
  _BlockTypeOption(
    type: NoteBlockType.heading,
    label: 'H',
    icon: Icons.title,
    tooltip: '标题',
  ),
  _BlockTypeOption(
    type: NoteBlockType.bullet,
    label: '•',
    icon: Icons.format_list_bulleted,
    tooltip: '无序列表',
  ),
  _BlockTypeOption(
    type: NoteBlockType.ordered,
    label: '1.',
    icon: Icons.format_list_numbered,
    tooltip: '有序列表',
  ),
  _BlockTypeOption(
    type: NoteBlockType.todo,
    label: '☐',
    icon: Icons.checklist,
    tooltip: '待办',
  ),
  _BlockTypeOption(
    type: NoteBlockType.quote,
    label: '"',
    icon: Icons.format_quote,
    tooltip: '引用',
  ),
  _BlockTypeOption(
    type: NoteBlockType.code,
    label: '</>',
    icon: Icons.code,
    tooltip: '代码',
  ),
  _BlockTypeOption(
    type: NoteBlockType.divider,
    label: '—',
    icon: Icons.horizontal_rule,
    tooltip: '分隔线',
  ),
  _BlockTypeOption(
    type: NoteBlockType.image,
    label: '🖼',
    icon: Icons.image_outlined,
    tooltip: '图片',
  ),
  _BlockTypeOption(
    type: NoteBlockType.link,
    label: '🔗',
    icon: Icons.link,
    tooltip: '链接',
  ),
  _BlockTypeOption(
    type: NoteBlockType.table,
    label: '⊞',
    icon: Icons.table_chart_outlined,
    tooltip: '表格',
  ),
  _BlockTypeOption(
    type: NoteBlockType.database,
    label: '🗄',
    icon: Icons.storage_outlined,
    tooltip: '数据库',
  ),
  _BlockTypeOption(
    type: NoteBlockType.canvas,
    label: '🎨',
    icon: Icons.dashboard_customize_outlined,
    tooltip: '内嵌画布',
  ),
  _BlockTypeOption(
    type: NoteBlockType.chart,
    label: '📊',
    icon: Icons.bar_chart,
    tooltip: '内嵌图表',
  ),
];

class _NoteEditorPageState extends State<NoteEditorPage> {
  /// 块树根节点（其 children 为顶层块列表）。
  late NoteBlock _root;

  /// 纯逻辑块编辑器。
  final NoteBlockEditor _editor = const NoteBlockEditor();

  /// 每个块的文本控制器（key = blockId）。
  final Map<String, TextEditingController> _controllers = {};

  /// 每个块的焦点节点（key = blockId）。
  final Map<String, FocusNode> _focusNodes = {};

  /// 当前聚焦的块 id。
  String? _focusedBlockId;

  /// id 生成计数器。
  int _idCounter = 0;

  @override
  void initState() {
    super.initState();
    _root = _createInitialTree();
    // 监听所有焦点节点以追踪当前聚焦块
    for (final node in _focusNodes.values) {
      node.addListener(_onFocusChange);
    }
    // 初始聚焦第一块
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_root.children.isNotEmpty) {
        _focusNodes[_root.children.first.id]?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.removeListener(_onFocusChange);
      node.dispose();
    }
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── 初始化 ─────────────────────────────────────────────────

  NoteBlock _createInitialTree() {
    final first = NoteBlock.textBlock(_nextId(), text: '');
    _ensureBlockResources(first);
    return NoteBlock(
      id: 'root',
      type: NoteBlockType.text,
      children: [first],
    );
  }

  String _nextId() => 'block_${_idCounter++}';

  /// 确保指定块及其子树拥有控制器和焦点节点。
  void _ensureBlockResources(NoteBlock block) {
    if (!_controllers.containsKey(block.id)) {
      _controllers[block.id] = TextEditingController(text: block.text);
    }
    if (!_focusNodes.containsKey(block.id)) {
      final node = FocusNode();
      node.addListener(_onFocusChange);
      _focusNodes[block.id] = node;
    }
    for (final child in block.children) {
      _ensureBlockResources(child);
    }
  }

  /// 释放指定块的资源。
  void _disposeBlockResources(String blockId) {
    final controller = _controllers.remove(blockId);
    controller?.dispose();
    final node = _focusNodes.remove(blockId);
    if (node != null) {
      node.removeListener(_onFocusChange);
      node.dispose();
    }
  }

  // ── 焦点追踪 ───────────────────────────────────────────────

  void _onFocusChange() {
    String? focused;
    for (final entry in _focusNodes.entries) {
      if (entry.value.hasFocus) {
        focused = entry.key;
        break;
      }
    }
    if (focused != _focusedBlockId) {
      setState(() {
        _focusedBlockId = focused;
      });
    }
  }

  // ── 文本同步 ───────────────────────────────────────────────

  /// 同步指定块的文本到块树。
  void _syncText(String blockId) {
    final controller = _controllers[blockId];
    if (controller == null) return;
    final block = _editor.findBlock(_root, blockId);
    if (block == null) return;
    if (block.text == controller.text) return;
    setState(() {
      _root = _editor.updateText(_root, blockId, controller.text);
    });
  }

  // ── Enter：分块 ────────────────────────────────────────────

  /// 在指定块的光标位置分块。
  void _splitBlock(String blockId) {
    final controller = _controllers[blockId];
    if (controller == null) return;
    final block = _editor.findBlock(_root, blockId);
    if (block == null) return;

    final text = controller.text;
    final cursorPos = controller.selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, cursorPos);
    final after = text.substring(cursorPos);

    final newId = _nextId();
    final newBlock = _createBlockOfType(block.type, newId, after);

    setState(() {
      // 当前块保留前半
      _root = _editor.updateText(_root, blockId, before);
      controller.text = before;
      // 插入新块（后半）
      _root = _editor.insertAfter(_root, blockId, newBlock);
      _ensureBlockResources(newBlock);
    });

    // 聚焦新块并将光标置于开头
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final newController = _controllers[newId];
      newController?.selection = const TextSelection.collapsed(offset: 0);
      _focusNodes[newId]?.requestFocus();
    });
  }

  /// 根据类型创建对应工厂的新块。
  NoteBlock _createBlockOfType(NoteBlockType type, String id, String text) {
    switch (type) {
      case NoteBlockType.heading:
        return NoteBlock.headingBlock(id, level: 1, text: text);
      case NoteBlockType.bullet:
        return NoteBlock.bulletBlock(id, text: text);
      case NoteBlockType.ordered:
        return NoteBlock.orderedBlock(id, text: text);
      case NoteBlockType.todo:
        return NoteBlock.todoBlock(id, text: text);
      case NoteBlockType.code:
        return NoteBlock.codeBlock(id, text: text);
      case NoteBlockType.quote:
        return NoteBlock.quoteBlock(id, text: text);
      case NoteBlockType.text:
        return NoteBlock.textBlock(id, text: text);
      case NoteBlockType.divider:
        return NoteBlock.dividerBlock(id);
      case NoteBlockType.image:
        return NoteBlock.textBlock(id, text: text);
      case NoteBlockType.callout:
        return NoteBlock(id: id, type: NoteBlockType.callout, text: text);
      case NoteBlockType.canvas:
        return NoteBlock(id: id, type: NoteBlockType.canvas);
      case NoteBlockType.chart:
        return NoteBlock(id: id, type: NoteBlockType.chart);
      case NoteBlockType.link:
        return NoteBlock(id: id, type: NoteBlockType.link, text: text);
      case NoteBlockType.table:
        return NoteBlock(id: id, type: NoteBlockType.table);
      case NoteBlockType.database:
        return NoteBlock(id: id, type: NoteBlockType.database);
    }
  }

  // ── Backspace：空块合并 ────────────────────────────────────

  /// 在空块上退格，合并到前一块。
  void _mergeWithPrevious(String blockId) {
    final controller = _controllers[blockId];
    if (controller == null) return;
    if (controller.text.isNotEmpty) return; // 仅处理空块

    final index = _root.children.indexWhere((b) => b.id == blockId);
    if (index <= 0) return; // 无前一块，不做操作

    final previous = _root.children[index - 1];
    final previousText = previous.text;

    setState(() {
      _root = _editor.deleteBlock(_root, blockId);
      _disposeBlockResources(blockId);
    });

    // 聚焦前一块末尾
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prevController = _controllers[previous.id];
      prevController?.selection =
          TextSelection.collapsed(offset: previousText.length);
      _focusNodes[previous.id]?.requestFocus();
    });
  }

  // ── 工具栏：切换块类型 ─────────────────────────────────────

  /// 切换指定块的类型。
  void _changeBlockType(String blockId, NoteBlockType newType) {
    final block = _editor.findBlock(_root, blockId);
    if (block == null || block.type == newType) return;

    setState(() {
      _root = _editor.updateType(_root, blockId, newType);
    });
  }

  /// 切换 todo 块的完成状态。
  void _toggleTodo(String blockId) {
    final block = _editor.findBlock(_root, blockId);
    if (block == null || block.type != NoteBlockType.todo) return;
    setState(() {
      _root = _editor.toggleTodo(_root, blockId);
    });
  }

  // ── 构建 ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topLevelBlocks = _root.children;
    return Scaffold(
      appBar: AppBar(
        title: const Text('块式笔记'),
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildBlockList(topLevelBlocks),
          ),
          const Divider(height: 1),
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildBlockList(List<NoteBlock> blocks) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        return _buildBlockRow(blocks[index], index);
      },
    );
  }

  Widget _buildBlockRow(NoteBlock block, int index) {
    final isFocused = block.id == _focusedBlockId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBlockPrefix(block, index),
          Expanded(child: _buildBlockInput(block, isFocused)),
        ],
      ),
    );
  }

  /// 根据块类型构建前缀 widget（列表符号、复选框等）。
  Widget _buildBlockPrefix(NoteBlock block, int index) {
    switch (block.type) {
      case NoteBlockType.bullet:
        return const Padding(
          padding: EdgeInsets.only(top: 12, right: 4),
          child: Text('•', style: TextStyle(fontSize: 18)),
        );
      case NoteBlockType.ordered:
        return Padding(
          padding: const EdgeInsets.only(top: 12, right: 4),
          child: Text(
            '${index + 1}.',
            style: const TextStyle(fontSize: 16),
          ),
        );
      case NoteBlockType.todo:
        final checked = block.props['checked'] as bool? ?? false;
        return Padding(
          padding: const EdgeInsets.only(top: 8, right: 4),
          child: GestureDetector(
            onTap: () => _toggleTodo(block.id),
            child: Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 22,
              color: checked ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        );
      case NoteBlockType.quote:
        return Padding(
          padding: const EdgeInsets.only(top: 8, right: 8),
          child: Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      case NoteBlockType.divider:
        return const SizedBox.shrink();
      default:
        return const SizedBox(width: 8);
    }
  }

  /// 构建块的可编辑输入区域。
  Widget _buildBlockInput(NoteBlock block, bool isFocused) {
    // 分隔线块特殊渲染
    if (block.type == NoteBlockType.divider) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Divider(thickness: 2),
      );
    }

    // 内嵌块使用 EmbeddedBlockView 渲染（不进入可编辑 TextField）
    if (EmbeddedBlockView.isEmbeddedType(block.type)) {
      return EmbeddedBlockView(
        block: block,
        embeddedBuilder: widget.embeddedBlockBuilder,
      );
    }

    final controller = _controllers[block.id];
    final focusNode = _focusNodes[block.id];
    if (controller == null || focusNode == null) {
      return const SizedBox.shrink();
    }

    // 使用独立的 Focus 节点监听键盘事件，避免与 TextField 的 focusNode
    // 产生"子节点成为自身父节点"的冲突。
    return Focus(
      onKeyEvent: (node, event) => _handleBlockKey(block.id, event),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: _textStyleForBlockType(block),
        decoration: InputDecoration(
          hintText: _hintTextForBlockType(block.type),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          isDense: true,
        ),
        maxLines: null,
        textInputAction: TextInputAction.none,
        onChanged: (text) => _syncText(block.id),
        onTap: () {
          if (_focusedBlockId != block.id) {
            setState(() {
              _focusedBlockId = block.id;
            });
          }
        },
      ),
    );
  }

  /// 处理块的键盘事件（Enter 分块 / Backspace 空块合并）。
  KeyEventResult _handleBlockKey(String blockId, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _splitBlock(blockId);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      final controller = _controllers[blockId];
      if (controller != null && controller.text.isEmpty) {
        _mergeWithPrevious(blockId);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// 根据块类型返回文本样式。
  TextStyle _textStyleForBlockType(NoteBlock block) {
    switch (block.type) {
      case NoteBlockType.heading:
        final level = (block.props['level'] as int? ?? 1).clamp(1, 3);
        final sizes = {1: 24.0, 2: 20.0, 3: 18.0};
        return TextStyle(
          fontSize: sizes[level],
          fontWeight: FontWeight.bold,
        );
      case NoteBlockType.code:
        return const TextStyle(
          fontFamily: 'monospace',
          fontSize: 15,
          backgroundColor: Color(0xFFF5F5F5),
        );
      case NoteBlockType.todo:
        final checked = block.props['checked'] as bool? ?? false;
        return TextStyle(
          fontSize: 16,
          decoration: checked ? TextDecoration.lineThrough : null,
          color: checked ? Colors.grey : null,
        );
      case NoteBlockType.quote:
        return const TextStyle(
          fontSize: 16,
          fontStyle: FontStyle.italic,
          color: Colors.grey,
        );
      default:
        return const TextStyle(fontSize: 16);
    }
  }

  /// 根据块类型返回占位提示文本。
  String _hintTextForBlockType(NoteBlockType type) {
    switch (type) {
      case NoteBlockType.heading:
        return '标题';
      case NoteBlockType.bullet:
        return '列表项';
      case NoteBlockType.ordered:
        return '列表项';
      case NoteBlockType.todo:
        return '待办事项';
      case NoteBlockType.quote:
        return '引用';
      case NoteBlockType.code:
        return '代码';
      case NoteBlockType.text:
        return '输入内容...';
      case NoteBlockType.divider:
      case NoteBlockType.image:
      case NoteBlockType.callout:
      case NoteBlockType.canvas:
      case NoteBlockType.chart:
      case NoteBlockType.link:
      case NoteBlockType.table:
      case NoteBlockType.database:
        return '';
    }
  }

  // ── 工具栏 ─────────────────────────────────────────────────

  Widget _buildToolbar() {
    final focusedType = _focusedBlockType;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _blockTypeOptions.map((option) {
            final isSelected = focusedType == option.type;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: option.tooltip,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _focusedBlockId != null
                      ? () => _changeBlockType(_focusedBlockId!, option.type)
                      : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.5)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(
                              color:
                                  Theme.of(context).colorScheme.primary,
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(option.icon, size: 20),
                        const SizedBox(height: 2),
                        Text(
                          option.tooltip,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 当前聚焦块的类型（若无聚焦块则返回 null）。
  NoteBlockType? get _focusedBlockType {
    if (_focusedBlockId == null) return null;
    final block = _editor.findBlock(_root, _focusedBlockId!);
    return block?.type;
  }
}
