part of 'doc_editor.dart';

// 块操作域（O1 拆分自 doc_editor.dart）：缩进/反缩进、斜杠菜单触发与
// 分派。行为零变化。

/// 块操作域私有助手（拆分自 doc_editor.dart）。
extension _DocEditorBlockOps on DocEditorState {

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
   editorSetState(() {
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
     editorSetState(() {
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
}
