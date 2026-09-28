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
      // V-01（审计 2026-09-27）：Tab/Shift+Tab 轮选画布对象——Delete/
      // Alt+方向键/Menu 键等既有键盘链路此前的公共前提「先指针选中」
      // 被本分支闭合。无对象时返回 ignored 放行焦点遍历。
      if (key == LogicalKeyboardKey.tab) {
        return _selectNextObject(reverse: isShift)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
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

    // V-01：Esc 清除选中（与指针「点空白取消」等价；裁剪模式已在上方
    // 分支先行处理；就地编辑由顶部 _editFocus 守卫放行给 TextField）。
    if (key == LogicalKeyboardKey.escape && !isCtrlOrMeta && !isAlt) {
      return _clearKeyboardSelection()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
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

// V-01（审计 2026-09-27）：键盘选中画布对象专项——Tab / Shift+Tab 轮选。
//
// 交互设计（Excalidraw 同款 + 本项目三输入纪律）：
// - 无选中 → Tab 选中 z 序第一个对象；继续 Tab 前进、Shift+Tab 后退，
//   到边界循环；无对象时忽略（放行焦点遍历）。Esc 清除选中。
// - 轮选即激活既有键盘链路：Delete/Backspace 删除、Alt+方向键微调、
//   Menu/Shift+F10 上下文菜单（上方分支此前全部依赖指针先选中——键盘
//   用户无法删除画布对象的本缺口就此闭合）。
// - 选中滚入视口：对象中心在视图外时平移视口至可见（旋转视图跳过——
//   旋转空间平移换算留待真实使用场景；rotation=0 为主路径）。
// - 不复用 _onItemTap：其含超链接打开与连线模式副作用，键盘轮选不应
//   触发浏览器打开或进入连线状态——走纯选中路径。
// - 轮选顺序与覆盖层渲染同源（EditorOverlayItemPlan，z-order 排序），
//   保证「选中的顺序 = 看到的叠放顺序」。
//
// 同域归位说明：本段与上方按键派发同属键盘域，故收在本 part 内
// （presentation 目录文件数已达 sloc-guard 结构门禁上限 40，不再新建
// part 文件）。

/// 编辑器键盘选中域（V-01 专项）。
extension _EditorPageKeyboardSelect on _EditorPageState {
  /// 当前可选对象计划（画布模式仅文字块；笔记页模式混排四类，
  /// 与 _buildOverlayItems 同一数据源）。
  List<EditorOverlayItemPlanEntry> get _selectablePlan {
    final page = widget.session;
    return page == null
        ? EditorOverlayItemPlan.forCanvas(_controller.document.textItems)
        : EditorOverlayItemPlan.forPage(
            textItems: page.textItems,
            imageItems: page.imageItems,
            shapes: page.shapes,
            charts: page.charts,
          );
  }

  /// Tab（reverse=false）/ Shift+Tab（reverse=true）轮选下一个对象。
  ///
  /// 返回是否处理（无对象返回 false——放行焦点遍历）。
  bool _selectNextObject({required bool reverse}) {
    final plan = _selectablePlan;
    if (plan.isEmpty) return false;

    final currentId = _selectedItemId;
    final count = plan.length;
    final index = currentId == null
        ? -1
        : plan.indexWhere((e) => e.id == currentId);
    // 无选中 → 第一个（reverse 则最后一个）；有选中 → 前进/后退循环。
    final nextIndex = reverse
        ? (index <= 0 ? count - 1 : index - 1)
        : (index < 0 ? 0 : (index + 1) % count);
    final next = plan[nextIndex];

    _applyState(() {
      _canvasInteraction.clearObjectSelection();
      _canvasInteraction.selectedItemId = next.id;
    });
    _ensureObjectVisible(next);
    return true;
  }

  /// 清除键盘选中（Esc）：与指针路径的「点空白处取消」等价。
  bool _clearKeyboardSelection() {
    if (_selectedItemId == null && !_canvasInteraction.hasMultiSelection) {
      return false;
    }
    _applyState(_canvasInteraction.clearObjectSelection);
    return true;
  }

  /// 键盘选中滚入视口：对象中心落在视图外（含边缘余量）时平移视口，
  /// 使对象中心移到视口中央。rotation ≠ 0 时跳过（旋转空间平移换算
  /// 留待真实场景；rotation = 0 为主路径）。
  void _ensureObjectVisible(EditorOverlayItemPlanEntry entry) {
    final viewportSize = _viewportSize;
    if (viewportSize == null || _controller.viewRotation != 0) return;
    final bounds = _entryCanvasBounds(entry);
    if (bounds == null) return;

    final center = bounds.center;
    final viewPos = _controller.canvasToView(center);
    const margin = 48.0;
    final visible = Rect.fromLTWH(
      margin,
      margin,
      (viewportSize.width - margin * 2).clamp(0, double.infinity),
      (viewportSize.height - margin * 2).clamp(0, double.infinity),
    );
    if (visible.contains(viewPos)) return;

    // rotation = 0：view = (canvas − center)·scale + center + offset，
    // 视口平移与画布平移同空间——把对象视图位对齐视口中心即可。
    final viewCenter = viewportSize.center(Offset.zero);
    final delta = viewCenter - viewPos;
    _applyState(() => _controller.viewOffset += delta);
  }

  /// 计划条目的画布坐标包围盒（各类型均以左上角 + 宽高存储）。
  Rect? _entryCanvasBounds(EditorOverlayItemPlanEntry entry) {
    final text = entry.text;
    if (text != null) {
      return Rect.fromLTWH(text.x, text.y, text.width ?? 120, 32);
    }
    final image = entry.image;
    if (image != null) {
      return Rect.fromLTWH(image.x, image.y, image.width, image.height);
    }
    final shape = entry.shape;
    if (shape != null) {
      return Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);
    }
    final chart = entry.chart;
    if (chart != null) {
      return Rect.fromLTWH(
        chart.position.dx,
        chart.position.dy,
        chart.width,
        chart.height,
      );
    }
    return null;
  }
}
