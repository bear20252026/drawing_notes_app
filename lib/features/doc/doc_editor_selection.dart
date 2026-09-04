// 由 Claude 团队生成 | Drawing Notes App
// doc_editor 拆分（R4b 第二轮，架构审计 M1）：
// extension on DocEditorState（同库 part，可访问私有成员）。

part of 'doc_editor.dart';

extension DocEditorResources on DocEditorState {
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
    if (!_layerLinks.containsKey(block.id)) {
      _layerLinks[block.id] = LayerLink();
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
    _layerLinks.remove(blockId);
  }
}

extension DocEditorSelection on DocEditorState {
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
      editorSetState(() {
        _focusedBlockId = focused;
      });
      // 聚焦块切换：选区监听迁移到新控制器，浮动工具条先隐藏。
      _selectionListenerController?.removeListener(_onSelectionChanged);
      _selectionListenerController = focused == null
          ? null
          : _controllers[focused];
      _selectionListenerController?.addListener(_onSelectionChanged);
      _hasTextSelection = false;
      _syncSelectionToolbar();
    }
  }

  /// 聚焦块选区变化：出现非折叠选区时唤出浮动工具条（AFFiNE 风格）。
  void _onSelectionChanged() {
    final controller = _focusedBlockId == null
        ? null
        : _controllers[_focusedBlockId];
    final sel = controller?.selection;
    final hasSel =
        controller != null && sel != null && sel.isValid && !sel.isCollapsed;
    if (hasSel != _hasTextSelection) {
      editorSetState(() => _hasTextSelection = hasSel);
      _syncSelectionToolbar();
    }
  }

  /// 同步浮动选区工具条的显示/隐藏（幂等）。
  void _syncSelectionToolbar() {
    final link = _focusedBlockId == null ? null : _layerLinks[_focusedBlockId];
    final shouldShow = _hasTextSelection && link != null;
    if (shouldShow && _selectionToolbarOverlay == null) {
      _selectionToolbarOverlay = OverlayEntry(
        builder: (context) => _buildSelectionToolbar(link),
      );
      Overlay.of(context, rootOverlay: true).insert(_selectionToolbarOverlay!);
    } else if (!shouldShow && _selectionToolbarOverlay != null) {
      _selectionToolbarOverlay!.remove();
      _selectionToolbarOverlay = null;
    }
  }

  /// 隐藏并清理浮动选区工具条。
  void _dismissSelectionToolbar() {
    _hasTextSelection = false;
    _syncSelectionToolbar();
  }

  /// 复制当前聚焦块（新 id，插入其后并聚焦），AFFiNE 浮动工具条动作。
  void _duplicateFocusedBlock() {
    final blockId = _focusedBlockId;
    if (blockId == null) return;
    final block = _editor.findBlock(_root, blockId);
    if (block == null) return;
    final copyId = _nextId();
    final copy = block.copyWith(id: copyId);
    _root = _editor.insertAfter(_root, blockId, copy);
    _ensureBlockResources(_root);
    editorSetState(_updateDirtyState);
    _dismissSelectionToolbar();
    _focusNodes[copyId]?.requestFocus();
  }

  /// 删除当前聚焦块（浮动工具条动作）。
  void _deleteFocusedBlock() {
    final blockId = _focusedBlockId;
    if (blockId == null) return;
    _dismissSelectionToolbar();
    if (_selectionListenerController == _controllers[blockId]) {
      _selectionListenerController?.removeListener(_onSelectionChanged);
      _selectionListenerController = null;
    }
    _root = _editor.deleteBlock(_root, blockId);
    _disposeBlockResources(blockId);
    editorSetState(() {
      _focusedBlockId = null;
      _updateDirtyState();
    });
  }

  /// 浮动选区工具条（AFFiNE 风格深色胶囊）。
  ///
  /// 必须包 [Positioned]：Overlay 对未定位子项施加 tight 全屏约束
  /// （overlay.dart: nonPositionedChildConstraints = BoxConstraints.tight），
  /// 不包裹会把胶囊拉伸成覆盖全屏的黑幕。Positioned 提供松约束让
  /// 内容按 Row 自然收窄。
  Widget _buildSelectionToolbar(LayerLink link) {
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(28, 8),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1D1F),
              borderRadius: BorderRadius.circular(AppleRadius.md),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _selectionToolbarIcon(Icons.format_bold, '粗体', _toggleBold),
                _selectionToolbarIcon(Icons.format_italic, '斜体', _toggleItalic),
                _selectionToolbarIcon(
                  Icons.format_underline,
                  '下划线',
                  _toggleUnderline,
                ),
                _selectionToolbarIcon(Icons.link, '链接', _insertLink),
                _selectionToolbarDivider(),
                _selectionToolbarIcon(
                  Icons.content_copy_rounded,
                  '复制块',
                  _duplicateFocusedBlock,
                ),
                _selectionToolbarIcon(
                  Icons.delete_outline_rounded,
                  '删除块',
                  _deleteFocusedBlock,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionToolbarIcon(
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        onTap: () {
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _selectionToolbarDivider() {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.3),
    );
  }
}
