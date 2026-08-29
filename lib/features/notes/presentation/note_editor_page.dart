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

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_editor.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_history.dart';
import 'package:drawing_notes_app/features/notes/domain/note_inline_span.dart';
import 'package:drawing_notes_app/features/notes/domain/text_span_editor.dart';
import 'package:drawing_notes_app/features/notes/presentation/embedded_block_view.dart';
import 'package:drawing_notes_app/features/notes/presentation/block_slash_menu.dart';

/// 块式笔记编辑器页面。
///
/// M4 集成：支持接收 [NoteBlockDoc] 并通过 [onSave] 回调双向绑定。
/// - 编辑过程通过 [NoteBlockEditor] 产生新的块树
/// - [title] 在文档内，appbar 可编辑
/// - 退出时用纯逻辑把 root 包装回 NoteBlockDoc 并回调 [onSave]
class NoteEditorPage extends StatefulWidget {
  /// 创建块式笔记编辑器页面。
  ///
  /// [document] 为可选的已有文档。若提供，编辑器从其 [NoteBlockDoc.body]
  /// 加载块树；若为 null，创建一个含单个空段落的新文档。
  ///
  /// [onSave] 为可选的保存回调。页面退出（pop）时，若此回调非 null，
  /// 会把当前编辑状态包装为 [NoteBlockDoc] 传出，由调用方决定如何持久化。
  /// 这保持页面不直接依赖存储层（infrastructure），符合分层架构。
  ///
  /// [embeddedBlockBuilder] 为可选的自定义内嵌块渲染回调，
  /// 由组合根（app_shell）注入，用于渲染 canvas/chart 等复杂内嵌块。
  /// 为 null 时使用内置降级渲染。
  const NoteEditorPage({
    super.key,
    this.document,
    this.onSave,
    this.embeddedBlockBuilder,
  });

  /// 要编辑的文档。为 null 时创建一个新文档。
  final NoteBlockDoc? document;

  /// 保存回调。页面退出时，把编辑后的 NoteBlockDoc 传出。
  /// 为 null 则不通知（用于纯预览/测试场景）。
  final ValueChanged<NoteBlockDoc>? onSave;

  /// 由组合根注入的自定义内嵌块渲染回调。
  /// 返回 null 时走默认降级渲染。
  final Widget? Function(NoteBlock block)? embeddedBlockBuilder;

  @override
  State<NoteEditorPage> createState() => NoteEditorPageState();
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

class NoteEditorPageState extends State<NoteEditorPage> {
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

  /// 当前正在拖拽的块 id（用于 dropline 指示）。
  String? _draggingBlockId;

  /// 当前拖拽目标插入索引（用于 dropline 渲染，null 表示无拖拽）。
  int? _dropTargetIndex;

  /// 撤销/重做历史。
  final NoteBlockHistory _history = NoteBlockHistory();

  /// 处于撤销/重做恢复流程时的标志，用于抑制 _syncText 的副作用，
  /// 避免回填 controller.text 时反向污染历史史栈。
  bool _restoring = false;

  /// id 生成计数器。
  int _idCounter = 0;

  /// 文档标题控制器。
  late TextEditingController _titleController;

  /// 当前文档（跟踪保存状态）。
  late NoteBlockDoc _doc;

  /// 是否已初始化。
  bool _initialized = false;

  /// 是否有未保存的改动。
  bool _isDirty = false;

  /// 上次保存时的 body 快照（用于 dirty 检测）。
  String _lastSavedBodySignature = '';

  /// 内联富文本编辑器（纯逻辑）。
  final TextSpanEditor _spanEditor = const TextSpanEditor();

  /// 是否显示 / 菜单。
  bool _showSlashMenu = false;

  /// / 菜单锚定的块 id。
  String? _slashMenuBlockId;

  /// / 菜单的 Overlay 条目。
  OverlayEntry? _slashMenuOverlay;

  @override
  void initState() {
    super.initState();
    _doc = widget.document ?? NoteBlockDoc.empty('doc_${DateTime.now().microsecondsSinceEpoch}');
    _titleController = TextEditingController(text: _doc.title);
    _root = _buildRootFromDoc(_doc);
    _lastSavedBodySignature = _computeBodySignature();
    _initialized = true;

    // 推入初始文档到撤销历史
    _history.push(_buildDocFromState());

    // 初始聚焦第一块
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_root.children.isNotEmpty) {
        _focusNodes[_root.children.first.id]?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    // 退出时回调 onSave（若提供），由调用方决定如何持久化。
    _notifySave();
    for (final node in _focusNodes.values) {
      node.removeListener(_onFocusChange);
      node.dispose();
    }
    for (final c in _controllers.values) {
      c.dispose();
    }
    _titleController.dispose();
    super.dispose();
  }

  /// 退出时把编辑后的 NoteBlockDoc 通过 onSave 回调传给调用方。
  void _notifySave() {
    if (!_initialized || widget.onSave == null) return;
    final updatedDoc = _buildDocFromState();
    widget.onSave!(updatedDoc);
  }

  // ── 文档 ↔ 状态 互转 ───────────────────────────────────────

  /// 从 NoteBlockDoc 构建 root 块（title 由 _titleController 持有）。
  NoteBlock _buildRootFromDoc(NoteBlockDoc doc) {
    _ensureBlockResourcesForList(doc.body);
    return NoteBlock(
      id: 'root',
      type: NoteBlockType.text,
      children: List<NoteBlock>.from(doc.body),
    );
  }

  /// 从当前状态重建 NoteBlockDoc。
  NoteBlockDoc _buildDocFromState() {
    return _doc.copyWith(
      title: _titleController.text,
      body: List<NoteBlock>.from(_root.children),
      updatedAt: DateTime.now(),
    );
  }

  /// 当前编辑中的文档（供宿主在切换页面/无限画布模式时读取最新内容）。
  ///
  /// 仅作快照读取，不会触发任何通知或副作用。
  NoteBlockDoc get currentDoc => _buildDocFromState();

  /// 从历史快照恢复文档（撤销/重做）。
  ///
  /// 必须重建根树、标题与块资源，并回填仍存在控制器的文本，
  /// 否则 TextField 会显示回滚前的旧文本。恢复期间通过 [_restoring]
  /// 抑制 [_syncText] 的副作用，避免回填 controller.text 反向污染史栈。
  void _restoreDoc(NoteBlockDoc doc) {
    final keepIds = _collectAllDocBlockIds(doc);

    // 释放快照中已不存在的块资源。
    final stale = _controllers.keys.where((id) => !keepIds.contains(id)).toList();
    for (final id in stale) {
      _disposeBlockResources(id);
    }

    _restoring = true;
    setState(() {
      _titleController.text = doc.title;
      _root = _buildRootFromDoc(doc);
      // 回填仍存在控制器的文本，使其与快照一致（同步触发 onChanged，被 _restoring 拦截）。
      void fill(NoteBlock b) {
        _controllers[b.id]?.text = b.text;
        for (final c in b.children) {
          fill(c);
        }
      }
      for (final b in doc.body) {
        fill(b);
      }
      // 聚焦块若已不存在则清空。
      if (_focusedBlockId != null && !keepIds.contains(_focusedBlockId)) {
        _focusedBlockId = null;
      }
    });
    _restoring = false;
    _updateDirtyState();
  }

  /// 收集块及其子树的所有 id。
  Set<String> _collectBlockIds(NoteBlock block) {
    final ids = <String>{block.id};
    for (final child in block.children) {
      ids.addAll(_collectBlockIds(child));
    }
    return ids;
  }

  /// 收集文档 body 中所有块 id（含子树）。
  Set<String> _collectAllDocBlockIds(NoteBlockDoc doc) {
    final ids = <String>{};
    for (final block in doc.body) {
      ids.addAll(_collectBlockIds(block));
    }
    return ids;
  }

  // ── 块缩进 / 取消缩进（嵌套）───────────────────────────────

  /// 在根树中定位某块（含子树），返回其父节点与索引；找不到返回 null。
  ({NoteBlock parent, int index})? _locateBlock(String blockId) {
    NoteBlock? findParent(NoteBlock node, String id) {
      for (var i = 0; i < node.children.length; i++) {
        if (node.children[i].id == id) return node;
        final sub = findParent(node.children[i], id);
        if (sub != null) return sub;
      }
      return null;
    }

    final parent = findParent(_root, blockId);
    if (parent == null) return null;
    return (parent: parent, index: parent.children.indexWhere((b) => b.id == blockId));
  }

  /// 应用经 NoteBlockEditor 变换后的新根树：确保资源、置脏、推历史。
  void _applyRootChange(NoteBlock newRoot) {
    setState(() {
      _root = newRoot;
      _ensureBlockResourcesForList(_root.children);
      _updateDirtyState();
    });
    _history.push(_buildDocFromState());
  }

  /// Tab：将块移到其上一兄弟的倒数子级（形成嵌套）。首块/无上一兄弟则不动作。
  void _indentBlock(String blockId) {
    final loc = _locateBlock(blockId);
    if (loc == null || loc.index == 0) return;
    final prevSibling = loc.parent.children[loc.index - 1];
    final newRoot = _editor.moveBlock(_root, blockId, prevSibling.id);
    if (!identical(newRoot, _root)) {
      _applyRootChange(newRoot);
    }
  }

  /// Shift+Tab：将块从父级中移出，成为其原父块的下一兄弟（取消嵌套）。
  /// 顶层块不动作。
  void _outdentBlock(String blockId) {
    final loc = _locateBlock(blockId);
    if (loc == null || loc.parent.id == _root.id) return;
    final parentLoc = _locateBlock(loc.parent.id);
    if (parentLoc == null) return;
    final newRoot = _editor.moveBlock(
      _root,
      blockId,
      parentLoc.parent.id,
      index: parentLoc.index + 1,
    );
    if (!identical(newRoot, _root)) {
      _applyRootChange(newRoot);
    }
  }

  // ── 初始化 ─────────────────────────────────────────────────

  /// 确保块列表中每个块都有控制器和焦点节点。
  void _ensureBlockResourcesForList(List<NoteBlock> blocks) {
    for (final block in blocks) {
      _ensureBlockResources(block);
    }
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
    if (_restoring) return;
    final controller = _controllers[blockId];
    if (controller == null) return;
    final block = _editor.findBlock(_root, blockId);
    if (block == null) return;
    if (block.text == controller.text) return;
    setState(() {
      _root = _editor.updateText(_root, blockId, controller.text);
      _updateDirtyState();
    });
    // 检测 / 菜单触发
    _checkSlashTrigger(blockId, controller.text, controller.selection.baseOffset);
    // 推入撤销历史
    _history.push(_buildDocFromState());
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
    // 推入撤销历史
    _history.push(_buildDocFromState());
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
      case NoteBlockType.attachment:
        return NoteBlock(id: id, type: NoteBlockType.attachment, text: text);
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
    // 推入撤销历史
    _history.push(_buildDocFromState());
  }

  // ── 工具栏：切换块类型 ─────────────────────────────────────

  /// 切换指定块的类型。
  void _changeBlockType(String blockId, NoteBlockType newType) {
    final block = _editor.findBlock(_root, blockId);
    if (block == null || block.type == newType) return;

    setState(() {
      _root = _editor.updateType(_root, blockId, newType);
      _updateDirtyState();
    });
    // 推入撤销历史
    _history.push(_buildDocFromState());
  }

  /// 切换 todo 块的完成状态。
  void _toggleTodo(String blockId) {
    final block = _editor.findBlock(_root, blockId);
    if (block == null || block.type != NoteBlockType.todo) return;
    setState(() {
      _root = _editor.toggleTodo(_root, blockId);
      _updateDirtyState();
    });
    // 推入撤销历史
    _history.push(_buildDocFromState());
  }

  /// 更新未保存状态（基于 body 签名比对）。
  void _updateDirtyState() {
    final signature = _computeBodySignature();
    setState(() {
      _isDirty = signature != _lastSavedBodySignature;
    });
  }

  /// 计算当前 body 的签名（用于 dirty 检测）。
  String _computeBodySignature() {
    return _root.children.map((b) => '${b.id}:${b.type.name}:${b.text}').join('|');
  }

  // ── 富文本操作 ─────────────────────────────────────────────

  /// 获取聚焦块的当前 span 列表（从 props 中读取，向后兼容纯文本）。
  List<NoteInlineSpan> _getSpansForFocusedBlock() {
    if (_focusedBlockId == null) return [];
    final block = _editor.findBlock(_root, _focusedBlockId!);
    if (block == null) return [];
    return _spansFromBlock(block);
  }

  /// 从 NoteBlock 的 props 中解析 span 列表（向后兼容纯文本）。
  List<NoteInlineSpan> _spansFromBlock(NoteBlock block) {
    final spansData = block.props['spans'];
    if (spansData is List) {
      return spansData
          .map((e) => NoteInlineSpan(
                text: e['text'] as String? ?? '',
                bold: e['bold'] as bool? ?? false,
                italic: e['italic'] as bool? ?? false,
                underline: e['underline'] as bool? ?? false,
                link: e['link'] as String?,
              ))
          .toList();
    }
    // 向后兼容：无 spans 属性 → 纯文本
    return NoteInlineSpanList.fromPlainText(block.text);
  }

  /// 将 span 列表序列化为 props 可存储格式。
  List<Map<String, dynamic>> _spansToProps(List<NoteInlineSpan> spans) {
    return spans.map((s) => {
      'text': s.text,
      'bold': s.bold,
      'italic': s.italic,
      'underline': s.underline,
      if (s.link != null) 'link': s.link,
    }).toList();
  }

  /// 更新聚焦块的 span 列表。
  void _updateSpans(String blockId, List<NoteInlineSpan> spans) {
    final plainText = spans.plainText;
    final props = _spansToProps(spans);
    setState(() {
      _root = _editor.updateText(_root, blockId, plainText);
      _root = _editor.updateProps(_root, blockId, {'spans': props});
      _updateDirtyState();
    });
  }

  /// 切换粗体。
  void _toggleBold() {
    final spans = _getSpansForFocusedBlock();
    if (spans.isEmpty) return;
    final controller = _controllers[_focusedBlockId];
    if (controller == null) return;
    final selection = controller.selection;
    final range = SpanRange(selection.start, selection.end);
    final result = _spanEditor.applyBold(spans, range);
    _updateSpans(_focusedBlockId!, result);
  }

  /// 切换斜体。
  void _toggleItalic() {
    final spans = _getSpansForFocusedBlock();
    if (spans.isEmpty) return;
    final controller = _controllers[_focusedBlockId];
    if (controller == null) return;
    final selection = controller.selection;
    final range = SpanRange(selection.start, selection.end);
    final result = _spanEditor.applyItalic(spans, range);
    _updateSpans(_focusedBlockId!, result);
  }

  /// 切换下划线。
  void _toggleUnderline() {
    final spans = _getSpansForFocusedBlock();
    if (spans.isEmpty) return;
    final controller = _controllers[_focusedBlockId];
    if (controller == null) return;
    final selection = controller.selection;
    final range = SpanRange(selection.start, selection.end);
    final result = _spanEditor.applyUnderline(spans, range);
    _updateSpans(_focusedBlockId!, result);
  }

  /// 插入链接（简化为对整个选区应用固定链接）。
  void _insertLink() {
    final spans = _getSpansForFocusedBlock();
    if (spans.isEmpty) return;
    final controller = _controllers[_focusedBlockId];
    if (controller == null) return;
    final selection = controller.selection;
    if (selection.isCollapsed) return;
    final range = SpanRange(selection.start, selection.end);
    final result = _spanEditor.applyLink(spans, range, 'https://example.com');
    _updateSpans(_focusedBlockId!, result);
  }

  // ── / 菜单 ─────────────────────────────────────────────────

  /// 检测是否应显示 / 菜单（键入 / 且光标在块末或空白块）。
  void _checkSlashTrigger(String blockId, String text, int cursorPos) {
    if (text == '/' && cursorPos == 1) {
      _openSlashMenu(blockId);
    } else if (_showSlashMenu && _slashMenuBlockId != blockId) {
      _closeSlashMenu();
    }
  }

  /// 显示 / 菜单。
  void _openSlashMenu(String blockId) {
    _closeSlashMenu(); // 先清理旧菜单
    setState(() {
      _showSlashMenu = true;
      _slashMenuBlockId = blockId;
    });
    final overlay = Overlay.of(context);
    _slashMenuOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 100,
        left: 20,
        child: BlockSlashMenu(
          onSelected: (type) => _onSlashMenuSelected(blockId, type),
          onDismiss: _closeSlashMenu,
        ),
      ),
    );
    overlay.insert(_slashMenuOverlay!);
  }

  /// 隐藏 / 菜单。
  void _closeSlashMenu() {
    _slashMenuOverlay?.remove();
    _slashMenuOverlay = null;
    if (_showSlashMenu) {
      setState(() {
        _showSlashMenu = false;
        _slashMenuBlockId = null;
      });
    }
  }

  /// / 菜单选中类型。
  void _onSlashMenuSelected(String blockId, NoteBlockType type) {
    _closeSlashMenu();
    _changeBlockType(blockId, type);
  }

  /// 手动触发保存：把当前编辑状态通过 onSave 回调传出。
  void _manualSave() {
    if (widget.onSave == null) return;
    final doc = _buildDocFromState();
    widget.onSave!(doc);
    if (mounted) {
      setState(() {
        _doc = doc;
        _lastSavedBodySignature = _computeBodySignature();
        _isDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文档已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  // ── 构建 ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topLevelBlocks = _root.children;
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showExitDialog();
      },
      child: Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            hintText: 'Untitled',
            border: InputBorder.none,
          ),
          style: AppleType.titleStyle(Theme.of(context).colorScheme.onSurface),
        ),
        elevation: 1,
        actions: [
          if (_isDirty)
            Padding(
              padding: const EdgeInsets.only(right: AppleSpacing.sm),
              child: Center(
                child: Text(
                  '未保存',
                  style: AppleType.captionStyle(AppleColor.actionBlue),
                ),
              ),
            ),
          if (widget.onSave != null)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _manualSave,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: topLevelBlocks.isEmpty
                ? _buildEmptyHint()
                : _buildBlockList(topLevelBlocks),
          ),
          const Divider(height: 1),
          _buildToolbar(),
        ],
      ),
    ),
    );
  }

  /// 退出未保存提醒对话框。
  void _showExitDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('未保存的改动'),
        content: const Text('文档有未保存的改动，确定要退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('放弃'),
          ),
        ],
      ),
    );
  }

  /// 空文档提示（AFFiNE 风格：引导用户输入）。
  Widget _buildEmptyHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_note,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppleSpacing.md),
            Text(
              '键入 / 添加块',
              style: AppleType.titleStyle(Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: AppleSpacing.xs),
            Text(
              '按 Enter 分块，按 Backspace 合并空块',
              style: AppleType.bodyStyle(Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
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
    final isFocused = _focusedBlockId == block.id;
    final isDraggingThis = _draggingBlockId == block.id;
    final showDropLine = _draggingBlockId != null &&
        _dropTargetIndex != null &&
        _dropTargetIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          // 不接受自身拖拽到自身位置。
          if (details.data == block.id) return false;
          setState(() => _dropTargetIndex = index);
          return true;
        },
        onLeave: (_) {
          if (_dropTargetIndex == index) {
            setState(() => _dropTargetIndex = null);
          }
        },
        onAcceptWithDetails: (details) {
          _moveBlockToPosition(details.data, index);
        },
        builder: (context, candidateData, rejectedData) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDropLine)
                Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Opacity(
                opacity: isDraggingThis ? 0.3 : 1.0,
                child: Semantics(
                  label: _semanticLabelForBlock(block),
                  focused: isFocused,
                  container: true,
                  child: Container(
                    decoration: isFocused
                        ? BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          )
                        : null,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBlockHandle(block),
                        _buildBlockPrefix(block, index),
                        Expanded(child: _buildBlockInput(block)),
                      ],
                    ),
                  ),
                ),
              ),
              // ── 嵌套子块（缩进渲染，不可整行拖拽）────────────────
              if (block.children.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < block.children.length; i++)
                        _buildNestedBlockRow(block.children[i], i),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 构建嵌套子块行（缩进显示、无整行拖拽；仍是可编辑/可键盘操作的行）。
  Widget _buildNestedBlockRow(NoteBlock block, int index) {
    final isFocused = _focusedBlockId == block.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Opacity(
        opacity: 1.0,
        child: Semantics(
          label: _semanticLabelForBlock(block),
          focused: isFocused,
          container: true,
          child: Container(
            decoration: isFocused
                ? BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 非拖拽的缩进占位与 grip 视觉（保持对齐，但不生成拖动把手）
                const SizedBox(width: 24, height: 24, child: Center(
                  child: Icon(Icons.drag_handle, size: 18),
                )),
                _buildBlockPrefix(block, index),
                Expanded(child: _buildBlockInput(block)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建块拖拽手柄（grip）。
  Widget _buildBlockHandle(NoteBlock block) {
    return Draggable<String>(
      data: block.id,
      feedback: Material(
        color: Colors.transparent,
        child: Icon(
          Icons.drag_handle,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      childWhenDragging: const SizedBox(width: 24, height: 24),
      onDragStarted: () {
        setState(() {
          _draggingBlockId = block.id;
          _dropTargetIndex = null;
        });
      },
      onDragEnd: (_) {
        setState(() {
          _draggingBlockId = null;
          _dropTargetIndex = null;
        });
      },
      child: GestureDetector(
        onTap: () => _selectBlock(block.id),
        child: Padding(
          padding: const EdgeInsets.only(top: 10, right: 4),
          child: Opacity(
            opacity: _focusedBlockId == block.id ? 1.0 : 0.4,
            child: Icon(
              Icons.drag_handle,
              size: 18,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }

  /// 将指定块移动到目标索引位置（顶层列表内）。
  void _moveBlockToPosition(String blockId, int targetIndex) {
    final blocks = _root.children;
    final currentIndex = blocks.indexWhere((b) => b.id == blockId);
    if (currentIndex < 0) return;
    // 目标索引在源索引之后时，需减一（因为移除源后列表缩短）。
    final adjustedTarget =
        targetIndex > currentIndex ? targetIndex - 1 : targetIndex;
    if (adjustedTarget < 0 || adjustedTarget >= blocks.length) return;
    final moved = _editor.moveBlock(_root, blockId, _root.id,
        index: adjustedTarget);
    setState(() {
      _root = moved;
      _updateDirtyState();
    });
  }

  /// 选中整块（聚焦并更新聚焦 id）。
  void _selectBlock(String blockId) {
    setState(() => _focusedBlockId = blockId);
    final node = _focusNodes[blockId];
    node?.requestFocus();
  }

  /// 为无障碍朗读生成块描述标签。
  String _semanticLabelForBlock(NoteBlock block) {
    final typeLabel = switch (block.type) {
      NoteBlockType.heading => '标题${block.props['level'] ?? 1}',
      NoteBlockType.todo => '待办事项',
      NoteBlockType.code => '代码块',
      NoteBlockType.quote => '引用',
      NoteBlockType.bullet => '无序列表',
      NoteBlockType.ordered => '有序列表',
      NoteBlockType.divider => '分割线',
      NoteBlockType.callout => '提示',
      NoteBlockType.image => '图片',
      _ => '段落',
    };
    return '$typeLabel: ${block.text.isEmpty ? '空' : block.text}';
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
              color: AppleColor.actionBlue.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppleRadius.xs),
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
  Widget _buildBlockInput(NoteBlock block) {
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

    // 监听键盘事件。Focus 作为祖先节点监听按键（键盘事件会从聚焦的
    // TextField 沿焦点树向上冒泡到这里），因此无需与 TextField 共用
    // focusNode——共用还会触发 "child into parent of itself" 焦点错误。
    return Focus(
      onKeyEvent: (_, event) => _handleBlockKey(block.id, event),
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

    // ── 撤销 / 重做（Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y）────────────────
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isCtrl && (event.logicalKey == LogicalKeyboardKey.keyZ ||
        event.logicalKey == LogicalKeyboardKey.keyY)) {
      final isRedo = event.logicalKey == LogicalKeyboardKey.keyY ||
          HardwareKeyboard.instance.isShiftPressed;
      final doc = isRedo ? _history.redo() : _history.undo();
      if (doc != null) {
        _restoreDoc(doc);
      }
      return KeyEventResult.handled;
    }

    // ── 上 / 下 方向键块间导航 ───────────────────────────────────────
    final order = List<String>.from(_root.children.map((b) => b.id));
    final idx = order.indexOf(blockId);
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (idx > 0) {
        _focusNodes[order[idx - 1]]?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (idx >= 0 && idx < order.length - 1) {
        _focusNodes[order[idx + 1]]?.requestFocus();
      }
      return KeyEventResult.handled;
    }

    // ── Tab / Shift+Tab 缩进 / 取消缩进（创建/退出嵌套）──────────────
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _outdentBlock(blockId);
      } else {
        _indentBlock(blockId);
      }
      return KeyEventResult.handled;
    }

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

  /// 根据块类型返回文本样式（h1-h6 字级 + 主题感知）。
  TextStyle _textStyleForBlockType(NoteBlock block) {
    final theme = Theme.of(context);
    switch (block.type) {
      case NoteBlockType.heading:
        final level = (block.props['level'] as int? ?? 1).clamp(1, 6);
        const sizes = {1: 28.0, 2: 24.0, 3: 20.0, 4: 18.0, 5: 16.0, 6: 14.0};
        return TextStyle(
          fontSize: sizes[level],
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        );
      case NoteBlockType.code:
        return TextStyle(
          fontFamily: 'monospace',
          fontSize: 15,
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          color: theme.colorScheme.onSurface,
        );
      case NoteBlockType.todo:
        final checked = block.props['checked'] as bool? ?? false;
        return TextStyle(
          fontSize: 16,
          decoration: checked ? TextDecoration.lineThrough : null,
          color: checked ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : theme.colorScheme.onSurface,
        );
      case NoteBlockType.quote:
        return TextStyle(
          fontSize: 16,
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        );
      case NoteBlockType.callout:
        return TextStyle(
          fontSize: 16,
          backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          color: theme.colorScheme.onSurface,
        );
      default:
        return TextStyle(fontSize: 16, color: theme.colorScheme.onSurface);
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
      case NoteBlockType.attachment:
        return '';
    }
  }

  // ── 工具栏 ─────────────────────────────────────────────────

  Widget _buildToolbar() {
    final focusedType = _focusedBlockType;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppleSpacing.sm, horizontal: AppleSpacing.xs),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ..._buildRichTextButtons(),
            const VerticalDivider(width: 8),
            ..._blockTypeOptions.map((option) {
            final isSelected = focusedType == option.type;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: option.tooltip,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppleRadius.md),
                  onTap: _focusedBlockId != null
                      ? () => _changeBlockType(_focusedBlockId!, option.type)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppleSpacing.sm, horizontal: AppleSpacing.sm),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppleColor.actionBlue.withValues(alpha: 0.12)
                          : null,
                      borderRadius: BorderRadius.circular(AppleRadius.md),
                      border: isSelected
                          ? Border.all(
                              color: AppleColor.actionBlue,
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(option.icon, size: 20),
                        const SizedBox(height: AppleSpacing.xxs),
                        Text(
                          option.tooltip,
                          style: AppleType.captionStyle(Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          ],
        ),
      ),
    );
  }

  /// 构建富文本工具栏按钮（粗体/斜体/下划线/链接）。
  List<Widget> _buildRichTextButtons() {
    final hasFocus = _focusedBlockId != null;
    return [
      _toolbarIconButton(
        icon: Icons.format_bold,
        tooltip: '粗体',
        onPressed: hasFocus ? () => _toggleBold() : null,
      ),
      _toolbarIconButton(
        icon: Icons.format_italic,
        tooltip: '斜体',
        onPressed: hasFocus ? () => _toggleItalic() : null,
      ),
      _toolbarIconButton(
        icon: Icons.format_underline,
        tooltip: '下划线',
        onPressed: hasFocus ? () => _toggleUnderline() : null,
      ),
      _toolbarIconButton(
        icon: Icons.link,
        tooltip: '链接',
        onPressed: hasFocus ? () => _insertLink() : null,
      ),
    ];
  }

  /// 工具栏图标按钮的通用构造。
  Widget _toolbarIconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.xxs),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(AppleSpacing.sm),
            child: Icon(
              icon,
              size: 20,
              color: onPressed != null
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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
