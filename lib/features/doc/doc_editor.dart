/// 块式笔记编辑器页面（DocEditor）。
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_editor.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_history.dart';
import 'package:drawing_notes_app/features/doc/domain/note_inline_span.dart';
import 'package:drawing_notes_app/features/doc/application/doc_link_index.dart';
import 'package:drawing_notes_app/features/doc/domain/text_span_editor.dart';
import 'package:drawing_notes_app/features/doc/presentation/embedded_block_view.dart';
import 'package:drawing_notes_app/features/doc/presentation/block_slash_menu.dart';
part 'doc_editor_blocks.dart';
part 'doc_editor_toolbar.dart';
part 'doc_editor_editing.dart';
part 'doc_editor_selection.dart';

/// 块式笔记编辑器页面。
///
/// M4 集成：支持接收 [NoteBlockDoc] 并通过 [onSave] 回调双向绑定。
/// - 编辑过程通过 [NoteBlockEditor] 产生新的块树
/// - [title] 在文档内，appbar 可编辑
/// - 退出时用纯逻辑把 root 包装回 NoteBlockDoc 并回调 [onSave]
class DocEditor extends StatefulWidget {
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
  const DocEditor({
    super.key,
    this.document,
    this.onSave,
    this.embeddedBlockBuilder,
    this.showChrome = true,
    this.onDirty,
  });

  /// 要编辑的文档。为 null 时创建一个新文档。
  final NoteBlockDoc? document;

  /// 是否渲染自带外壳（AppBar 脚手架）。
  /// false = 仅内容（标题+块列表+工具栏），由宿主（如 DocPage）提供顶栏。
  final bool showChrome;

  /// 内容变为未保存（脏）时的回调——宿主据此驱动自动保存与状态显示。
  final VoidCallback? onDirty;

  /// 保存回调。页面退出时，把编辑后的 NoteBlockDoc 传出。
  /// 为 null 则不通知（用于纯预览/测试场景）。
  final ValueChanged<NoteBlockDoc>? onSave;

  /// 由组合根注入的自定义内嵌块渲染回调。
  /// 返回 null 时走默认降级渲染。
  final Widget? Function(NoteBlock block)? embeddedBlockBuilder;

  @override
  State<DocEditor> createState() => DocEditorState();
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

class DocEditorState extends State<DocEditor> {
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

  /// 块列表滚动控制器（大纲跳转用）。
  final ScrollController _listScroll = ScrollController();

  /// 大纲面板开合（AFFiNE 桌面式右侧停靠面板）。
  bool _outlineOpen = false;

  /// 每个块的 LayerLink（key = blockId）——浮动选区工具条锚定用。
  final Map<String, LayerLink> _layerLinks = {};

  /// 浮动选区工具条 Overlay（有非折叠文本选区时显示，AFFiNE 风格）。
  OverlayEntry? _selectionToolbarOverlay;

  /// 聚焦块是否存在非折叠文本选区。
  bool _hasTextSelection = false;

  /// 当前挂了选区监听的控制器（防止重复挂/漏摘）。
  TextEditingController? _selectionListenerController;

  /// 当前正在拖拽的块 id（用于 dropline 指示）。
  String? _draggingBlockId;

  /// 当前拖拽目标插入索引（用于 dropline 渲染，null 表示无拖拽）。
  int? _dropTargetIndex;

  /// 嵌套子块拖放：目标父块 id 与插入索引（M11：子块可拖拽）。
  String? _nestedDropParentId;
  int? _nestedDropIndex;

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
    _doc =
        widget.document ??
        NoteBlockDoc.empty('doc_${DateTime.now().microsecondsSinceEpoch}');
    _titleController = TextEditingController(text: _doc.title);
    _titleController.addListener(_onTitleEdited);
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
    _selectionToolbarOverlay?.remove();
    _selectionToolbarOverlay = null;
    // P1-M4（审计 2026-08-31）：slash 菜单 overlay 同样必须移除，
    // 否则脱离 widget 树后仍挂在 Overlay 上（内存泄漏 + 幽灵浮层）。
    _slashMenuOverlay?.remove();
    _slashMenuOverlay = null;
    _listScroll.dispose();
    _selectionListenerController?.removeListener(_onSelectionChanged);
    for (final node in _focusNodes.values) {
      node.removeListener(_onFocusChange);
      node.dispose();
    }
    for (final c in _controllers.values) {
      c.dispose();
    }
    _titleController.removeListener(_onTitleEdited);
    _titleController.dispose();
    _historyDebounce?.cancel();
    super.dispose();
  }

  /// 击键合帧定时器（P2-M6）。
  Timer? _historyDebounce;

  /// part 文件（extension）用的 setState 包装——State.setState 是
  /// protected，extension 中直接调用会报 invalid_use_of_protected_member。
  void editorSetState(VoidCallback fn) => setState(fn);

  /// 首次脏通知标志（架构审计 Q0 修复）：onDirty 只在"从未通知→通知"
  /// 边沿触发一次。原实现用 _isDirty 作门控，但 _syncText 先经
  /// _updateDirtyState 置 _isDirty=true，导致纯文本输入的 onDirty 被
  /// 短路——自动保存从不启动，用户输入永不落盘。
  bool _dirtyNotified = false;

  /// 提交一次编辑：压入历史栈并标记脏状态（触发宿主自动保存）。
  /// 结构性操作（分块/合并/删除/类型切换/插入引用）走本方法——即时入栈。
  void _commitHistory() {
    _historyDebounce?.cancel();
    _history.push(_buildDocFromState());
    _isDirty = true;
    _notifyDirtyOnce();
  }

  /// P2-M6：文本击键合帧——连续输入只在停顿 500ms 后压一次史栈
  /// （撤销粒度变为「输入 burst」而非单字符，与主流编辑器一致），
  /// 消除每键全文档深拷贝。脏标记仍即时（自动保存不受影响）。
  void _commitHistoryCoalesced() {
    _historyDebounce?.cancel();
    _historyDebounce = Timer(const Duration(milliseconds: 500), () {
      _history.push(_buildDocFromState());
    });
    _isDirty = true;
    _notifyDirtyOnce();
  }

  /// 边沿触发一次 onDirty（首次脏时通知宿主启动自动保存）。
  void _notifyDirtyOnce() {
    if (_dirtyNotified) return;
    _dirtyNotified = true;
    widget.onDirty?.call();
  }

  /// 把待提交的合帧快照立即入栈（saveNow/结构操作前调用，防丢撤销粒度）。
  void _flushPendingHistory() {
    _historyDebounce?.cancel();
    _history.push(_buildDocFromState());
  }

  void _onTitleEdited() {
    if (_restoring) return;
    if (!_isDirty) {
      _isDirty = true;
      widget.onDirty?.call();
    }
  }

  /// 立即保存：构建当前文档快照、清除脏标记并回调 onSave。
  /// 返回保存的文档快照（供宿主显示"已保存"时间等）。
  NoteBlockDoc saveNow() {
    // P2-M6：先入栈待提交的击键合帧快照，保证撤销粒度完整。
    _flushPendingHistory();
    final doc = _buildDocFromState();
    _isDirty = false;
    _dirtyNotified = false; // 已落盘，后续编辑重新走首次通知
    widget.onSave?.call(doc);
    return doc;
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

  /// 在文档末尾追加一个页面引用块（M12.7 反向链接：[[标题]] 双链语法）。
  /// 走完整保存链（脏标记→自动保存→撤销历史）。
  void appendPageLink(NoteBlockDoc target) {
    final link = NoteBlock.textBlock(_nextId(), text: formatDocLink(target));
    if (_root.children.isEmpty) {
      _root = NoteBlock(
        id: _root.id,
        type: _root.type,
        text: _root.text,
        props: _root.props,
        children: [link],
      );
    } else {
      final last = _root.children.last;
      _root = _editor.insertAfter(_root, last.id, link);
    }
    _ensureBlockResources(link);
    _commitHistory();
    setState(() {});
  }

  /// 从历史快照恢复文档（撤销/重做）。
  ///
  /// 必须重建根树、标题与块资源，并回填仍存在控制器的文本，
  /// 否则 TextField 会显示回滚前的旧文本。恢复期间通过 [_restoring]
  /// 抑制 [_syncText] 的副作用，避免回填 controller.text 反向污染史栈。
  void _restoreDoc(NoteBlockDoc doc) {
    _historyDebounce?.cancel(); // 撤销/重做恢复期间丢弃待提交击键
    final keepIds = _collectAllDocBlockIds(doc);

    // 释放快照中已不存在的块资源。
    final stale = _controllers.keys
        .where((id) => !keepIds.contains(id))
        .toList();
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
    return (
      parent: parent,
      index: parent.children.indexWhere((b) => b.id == blockId),
    );
  }

  /// 应用经 NoteBlockEditor 变换后的新根树：确保资源、置脏、推历史。
  void _applyRootChange(NoteBlock newRoot) {
    setState(() {
      _root = newRoot;
      _ensureBlockResourcesForList(_root.children);
      _updateDirtyState();
    });
    _commitHistory();
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
    // 无外壳模式：宿主（DocPage）提供顶栏与页面脚手架。
    if (!widget.showChrome) {
      return Column(
        children: [
          _buildTitleField(),
          Expanded(
            child: topLevelBlocks.isEmpty
                ? _buildEmptyHint()
                : _buildBlockList(topLevelBlocks),
          ),
          const Divider(height: 1),
          _buildToolbar(),
        ],
      );
    }
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showExitDialog();
      },
      child: Scaffold(
        appBar: AppBar(
          // M11：AFFiNE 式——标题不在 AppBar，而是正文第一个大标题块。
          title: const Text(''),
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
              IconButton(icon: const Icon(Icons.save), onPressed: _manualSave),
            IconButton(
              tooltip: '大纲',
              icon: Icon(
                Icons.format_list_bulleted_rounded,
                color: _outlineOpen
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onPressed: () => setState(() => _outlineOpen = !_outlineOpen),
            ),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  // AFFiNE 式正文大标题（受控于 _titleController，随 onSave 持久化）
                  _buildTitleField(),
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
            // 大纲停靠面板（AFFiNE Outline）
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _outlineOpen
                  ? _buildOutlineDrawer()
                  : const SizedBox.shrink(key: ValueKey('outline-off')),
            ),
          ],
        ),
      ),
    );
  }

  /// AFFiNE 式正文大标题。
  Widget _buildTitleField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: TextField(
        controller: _titleController,
        decoration: const InputDecoration(
          hintText: 'Untitled',
          border: InputBorder.none,
        ),
        style: AppleType.titleStyle(
          Theme.of(context).colorScheme.onSurface,
        ).copyWith(fontSize: 26, fontWeight: FontWeight.w700),
        maxLines: null,
      ),
    );
  }

  // ── 大纲（Outline，对标 AFFiNE Outline 面板）─────────────────

  /// 按文档顺序抽取所有标题块（含嵌套），供大纲面板展示。
  List<({String id, int level, String text})> outline() {
    final out = <({String id, int level, String text})>[];
    void walk(NoteBlock b) {
      if (b.type == NoteBlockType.heading) {
        out.add((
          id: b.id,
          level: (b.props['level'] as int?)?.clamp(1, 6) ?? 1,
          text: b.text,
        ));
      }
      for (final c in b.children) {
        walk(c);
      }
    }

    for (final b in _root.children) {
      walk(b);
    }
    return out;
  }

  bool _containsId(NoteBlock node, String id) {
    if (node.id == id) return true;
    for (final c in node.children) {
      if (_containsId(c, id)) return true;
    }
    return false;
  }

  /// 大纲点击跳转：按顶层索引估算滚动位置（v1 行高估算）。
  void scrollToBlock(String blockId) {
    final topLevel = _root.children;
    var index = -1;
    for (var i = 0; i < topLevel.length; i++) {
      if (_containsId(topLevel[i], blockId)) {
        index = i;
        break;
      }
    }
    if (index < 0 || !_listScroll.hasClients) return;
    const estimatedExtent = 72.0;
    final target = (index * estimatedExtent).clamp(
      0.0,
      _listScroll.position.maxScrollExtent,
    );
    _listScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  /// 大纲停靠面板。
  Widget _buildOutlineDrawer() {
    final entries = outline();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('outline-on'),
      width: 264,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '大纲',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => setState(() {}),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        '暂无标题块，用 / 菜单插入「标题」后出现在这里',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        return InkWell(
                          onTap: () {
                            scrollToBlock(e.id);
                            Navigator.of(context).pop();
                          },
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 16 + (e.level - 1) * 16.0,
                              right: 16,
                              top: 8,
                              bottom: 8,
                            ),
                            child: Text(
                              e.text.isEmpty ? '（空标题）' : e.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: e.level <= 2
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
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
}
