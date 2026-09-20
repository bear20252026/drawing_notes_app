part of 'editor_page.dart';

// 编辑器快捷键处理域（O1 拆分）：Ctrl+Z/Y 等键盘分发从
// editor_page.dart 移出为 extension；行为零变化。

/// 编辑器快捷键处理域（拆分自 editor_page.dart）。
extension _EditorPageShortcuts on _EditorPageState {
  KeyEventResult _onShortcutKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // 就地编辑文字时禁用所有单键快捷键（对齐 Excalidraw 的
    // isEditingText 提前返回）：否则数字键 1-9 会被工具切换吞掉
    // （输入法选字的数字键同理），编辑已有块时退格会触发删除选区。
    // Ctrl 组合键等也不放行——撤销/重做由 TextField 自身处理。
    if (_editFocus.hasFocus) return KeyEventResult.ignored;

    final hw = HardwareKeyboard.instance;
    final isCtrlOrMeta = hw.isControlPressed || hw.isMetaPressed;
    final isShift = hw.isShiftPressed;
    final isAlt = hw.isAltPressed;
    final key = event.logicalKey;

    // 数字键 1-9 切换工具，保留符合绘图软件惯例的直接路径。
    if (!isCtrlOrMeta && !isAlt) {
      if (key == LogicalKeyboardKey.digit1) {
        _selectBrushTool();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit2) {
        _selectEraserTool();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit3) {
        _selectRectSelectTool();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit4) {
        if (!_marqueeActive) _toggleMarqueeTool();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit5) {
        _selectTextTool();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit6) {
        _selectShapeTool(ShapeType.rect);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit7) {
        _selectShapeTool(ShapeType.ellipse);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit8) {
        _selectShapeTool(ShapeType.arrow);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit9) {
        _selectShapeTool(ShapeType.line);
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.delete ||
              key == LogicalKeyboardKey.backspace) &&
          _commands.run('deleteSelection')) {
        return KeyEventResult.handled;
      }
      // 上下文菜单键盘入口（审计二-10）：Menu 键 / Shift+F10（Windows
      // 惯例），作用于当前选中元素；菜单出现在画布中央偏上。
      if ((key == LogicalKeyboardKey.contextMenu ||
              (key == LogicalKeyboardKey.f10 && isShift)) &&
          _selectedItemId != null) {
        _showItemContextMenu(_selectedItemId!);
        return KeyEventResult.handled;
      }
    }

    // 裁剪模式键盘微调（B3：拖拽手柄的键盘等价入口）：
    // 方向键平移裁剪框（1px，Shift=10px）；Enter 确认；Esc 退出。
    if (_canvasInteraction.isCropping && _cropRect != null) {
      const large = 10.0, small = 1.0;
      final step = isShift ? large : small;
      switch (key) {
        case LogicalKeyboardKey.arrowLeft:
          _nudgeCropRect(-step, 0);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          _nudgeCropRect(step, 0);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _nudgeCropRect(0, -step);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _nudgeCropRect(0, step);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
          unawaited(_confirmCrop());
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          _exitCropMode();
          return KeyEventResult.handled;
        default:
          break;
      }
    }

    // Alt+方向键微调选中元素位置（对齐 Excalidraw nudge，1px 步进）。
    if (isAlt && !isCtrlOrMeta && _selectedItemId != null) {
      switch (key) {
        case LogicalKeyboardKey.arrowLeft:
          _nudgeSelected(-1, 0);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          _nudgeSelected(1, 0);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _nudgeSelected(0, -1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _nudgeSelected(0, 1);
          return KeyEventResult.handled;
        default:
          break;
      }
    }

    if (!isCtrlOrMeta) return KeyEventResult.ignored;

    bool run(String id) => _commands.run(id);
    switch (key) {
      case LogicalKeyboardKey.keyZ:
        return (isShift ? run('redo') : run('undo'))
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyY:
        return run('redo') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyB:
        return run('bold') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyI:
        return run('italic') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyU:
        return run('underline')
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyE:
        return run('alignText')
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyC:
        if (isShift) {
          if (!_hasObjectSelection) return KeyEventResult.ignored;
          _copySelectedStyle();
          return KeyEventResult.handled;
        }
        return run('copy') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyV:
        if (isShift) {
          if (!_hasObjectSelection) return KeyEventResult.ignored;
          _pasteStyleToSelected();
          return KeyEventResult.handled;
        }
        return run('paste') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyD:
        return run('duplicate')
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyK:
        unawaited(_showCommandPalette());
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyP:
        if (isShift) {
          unawaited(_showCommandPalette());
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      default:
        return KeyEventResult.ignored;
    }
  }

  /// 右上角主菜单选择处理（对齐 Excalidraw main-menu）。

  /// B3：键盘平移裁剪框（画布坐标，钳制在裁剪对象 bounds 内）。
  void _nudgeCropRect(double dx, double dy) {
    final item = _canvasInteraction.cropItem;
    final rect = _cropRect;
    if (item == null || rect == null) return;
    final bounds = Rect.fromLTWH(item.x, item.y, item.width, item.height);
    var left = rect.left + dx;
    var top = rect.top + dy;
    left = left.clamp(bounds.left, bounds.right - rect.width);
    top = top.clamp(bounds.top, bounds.bottom - rect.height);
    _applyState(
      () => _cropRect = Rect.fromLTWH(left, top, rect.width, rect.height),
    );
  }

  /// B3：Esc 退出裁剪模式（不落盘）。
  void _exitCropMode() {
    _applyState(_canvasInteraction.clearCrop);
  }
}
