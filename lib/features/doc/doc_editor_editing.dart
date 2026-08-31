// 由 Claude 团队生成 | Drawing Notes App
// doc_editor 拆分（R4b 第二轮，架构审计 M1）：
// extension on DocEditorState（同库 part，可访问私有成员）。

part of 'doc_editor.dart';

extension DocEditorEditing on DocEditorState {
  // ── 文本同步 ───────────────────────────────────────────────

  /// 同步指定块的文本到块树。
  void _syncText(String blockId) {
    if (_restoring) return;
    final controller = _controllers[blockId];
    if (controller == null) return;
    final block = _editor.findBlock(_root, blockId);
    if (block == null) return;
    if (block.text == controller.text) return;
    editorSetState(() {
      _root = _editor.updateText(_root, blockId, controller.text);
      _updateDirtyState();
    });
    // 检测 / 菜单触发
    _checkSlashTrigger(
      blockId,
      controller.text,
      controller.selection.baseOffset,
    );
    // 推入撤销历史（P2-M6：文本击键合帧，500ms 停顿后入栈）
    _commitHistoryCoalesced();
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

    editorSetState(() {
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
    _commitHistory();
  }

  /// 根据类型创建对应工厂的新块。
  NoteBlock _createBlockOfType(NoteBlockType type, String id, String text) {
    switch (type) {
      case NoteBlockType.heading:
        return NoteBlock.headingBlock(id, level: 1, text: text);
      case NoteBlockType.toggle:
        return NoteBlock.toggleBlock(id, text: text);
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

    editorSetState(() {
      _root = _editor.deleteBlock(_root, blockId);
      _disposeBlockResources(blockId);
    });

    // 聚焦前一块末尾
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prevController = _controllers[previous.id];
      prevController?.selection = TextSelection.collapsed(
        offset: previousText.length,
      );
      _focusNodes[previous.id]?.requestFocus();
    });
    // 推入撤销历史
    _commitHistory();
  }

  // ── 工具栏：切换块类型 ─────────────────────────────────────

  /// 切换指定块的类型。
  void _changeBlockType(String blockId, NoteBlockType newType) {
    final block = _editor.findBlock(_root, blockId);
    if (block == null || block.type == newType) return;

    editorSetState(() {
      _root = _editor.updateType(_root, blockId, newType);
      _updateDirtyState();
    });
    // 推入撤销历史
    _commitHistory();
  }

  /// 切换 todo 块的完成状态。
  void _toggleTodo(String blockId) {
    final block = _editor.findBlock(_root, blockId);
    if (block == null || block.type != NoteBlockType.todo) return;
    editorSetState(() {
      _root = _editor.toggleTodo(_root, blockId);
      _updateDirtyState();
    });
    // 推入撤销历史
    _commitHistory();
  }

  /// 切换 toggle 块的展开/折叠（展开态持久化在 props，随文档保存；
  /// 折叠不改变内容，不入撤销历史——与 AFFiNE 一致）。
  void _toggleToggleExpanded(String blockId) {
    final block = _editor.findBlock(_root, blockId);
    if (block == null || block.type != NoteBlockType.toggle) return;
    editorSetState(() {
      final expanded = block.props['expanded'] as bool? ?? true;
      _root = _editor.updateProps(_root, blockId, {
        ...block.props,
        'expanded': !expanded,
      });
    });
  }

  /// 更新未保存状态（基于 body 签名比对）。
  void _updateDirtyState() {
    final signature = _computeBodySignature();
    editorSetState(() {
      _isDirty = signature != _lastSavedBodySignature;
    });
    if (_isDirty) _notifyDirtyOnce();
  }

  /// 计算当前 body 的签名（用于 dirty 检测）。
  String _computeBodySignature() {
    return _root.children
        .map((b) => '${b.id}:${b.type.name}:${b.text}')
        .join('|');
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
          .map(
            (e) => NoteInlineSpan(
              text: e['text'] as String? ?? '',
              bold: e['bold'] as bool? ?? false,
              italic: e['italic'] as bool? ?? false,
              underline: e['underline'] as bool? ?? false,
              link: e['link'] as String?,
            ),
          )
          .toList();
    }
    // 向后兼容：无 spans 属性 → 纯文本
    return NoteInlineSpanList.fromPlainText(block.text);
  }

  /// 将 span 列表序列化为 props 可存储格式。
  List<Map<String, dynamic>> _spansToProps(List<NoteInlineSpan> spans) {
    return spans
        .map(
          (s) => {
            'text': s.text,
            'bold': s.bold,
            'italic': s.italic,
            'underline': s.underline,
            if (s.link != null) 'link': s.link,
          },
        )
        .toList();
  }

  /// 更新聚焦块的 span 列表。
  void _updateSpans(String blockId, List<NoteInlineSpan> spans) {
    final plainText = spans.plainText;
    final props = _spansToProps(spans);
    editorSetState(() {
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
}
