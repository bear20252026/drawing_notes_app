// 由 Claude 团队生成 | Drawing Notes App
// doc_editor 拆分（R4b 第二轮，架构审计 M1）：
// extension on DocEditorState（同库 part，可访问私有成员）。

part of 'doc_editor.dart';

extension DocEditorEditing on DocEditorState {
  // ── 文本同步 ───────────────────────────────────────────────

  /// 同步指定块的文本到块树。
  ///
  /// U3 P1-9：击键热路径不再整树 setState——TextField 由自身 controller
  /// 驱动显示，模型静默同步即可；装饰性消费方（大纲/空标题提示）经
  /// [_scheduleCosmeticRefresh] 200ms 合帧跟进，dirty 值翻转时才重建。
  /// 结构操作（分块/合并/类型切换）仍走 editorSetState 即时重建。
  void _syncText(String blockId) {
    if (_restoring) return;
    final controller = _controllers[blockId];
    if (controller == null) return;
    final block = _editor.findBlock(_root, blockId);
    if (block == null) return;
    if (block.text == controller.text) return;
    _root = _editor.updateText(_root, blockId, controller.text);
    _updateDirtyState();
    _scheduleCosmeticRefresh();
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
    // 拆分保留原块全部属性（标题级别/todo 勾选/code 语言/spans）——
    // 经工厂重建会丢失这些属性。children 不随后半走——子块仍归属前半。
    final newBlock = block.copyWith(id: newId, text: after, children: const []);

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

  // ── Backspace：空块合并 ────────────────────────────────────

  /// 在空块上退格，合并到前一块。
  void _mergeWithPrevious(String blockId) {
    final controller = _controllers[blockId];
    if (controller == null) return;
    if (controller.text.isNotEmpty) return; // 仅处理空块

    final index = _root.children.indexWhere((b) => b.id == blockId);
    if (index <= 0) return; // 无前一块，不做操作

    final block = _editor.findBlock(_root, blockId);
    if (block == null) return;
    final previous = _root.children[index - 1];
    final previousText = previous.text;

    editorSetState(() {
      // 空块下挂子块时先把子块上移为同级（Notion 语义）——直接删块
      // 会按子树连坐销毁，一次退格静默吞掉全部缩进子块。
      var anchor = previous.id;
      for (final child in block.children) {
        _root = _editor.insertAfter(_root, anchor, child);
        _ensureBlockResources(child);
        anchor = child.id;
      }
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
      // props 已纳入脏签名：折叠态翻转须翻转脏态，否则永不触发保存。
      _updateDirtyState();
    });
  }

  /// 更新未保存状态（基于 body 签名比对）。
  ///
  /// U3 P1-9：仅 dirty 值翻转时 setState——签名计算每键照常执行（廉价），
  /// 但未保存角标只在 false→true / true→false 边沿需要一次重建。
  void _updateDirtyState() {
    final signature = _computeBodySignature();
    final dirty = signature != _lastSavedBodySignature;
    if (dirty != _isDirty) {
      editorSetState(() => _isDirty = dirty);
    }
    if (_isDirty) _notifyDirtyOnce();
  }

  /// 计算当前 body 的签名（用于 dirty 检测）。
  ///
  /// 递归覆盖全部块（含嵌套子块）并纳入 props（排序后稳定输出）：
  /// 旧签名只看顶层 (id,type,text)，导致 ① 缩进子块里的编辑不翻转
  /// 脏态、自动保存不启动、退出静默丢字；② 折叠态/spans 等 props 变化
  /// 永不触发保存。签名仍是廉价字符串拼接，无深拷贝。
  String _computeBodySignature() {
    final buffer = StringBuffer();
    void visit(NoteBlock block) {
      if (block.props.isNotEmpty) {
        final sortedKeys = block.props.keys.toList()..sort();
        buffer.write('(');
        for (final key in sortedKeys) {
          buffer.write(key);
          buffer.write('=');
          buffer.write(block.props[key]);
          buffer.write(',');
        }
        buffer.write(')');
      }
      buffer
        ..write(block.id)
        ..write(':')
        ..write(block.type.name)
        ..write(':')
        ..write(block.text);
      for (final child in block.children) {
        buffer.write('{');
        visit(child);
        buffer.write('}');
      }
      buffer.write('|');
    }

    for (final block in _root.children) {
      visit(block);
    }
    return buffer.toString();
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
