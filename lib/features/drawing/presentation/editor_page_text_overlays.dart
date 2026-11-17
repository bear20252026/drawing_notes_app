part of 'editor_page.dart';

/// 编辑器文字域（R1 归并 2026-11-17：叠层/就地编辑/斜杠命令 + 文字
/// 编辑动作自 editing 逐字搬入）：渲染与编辑动作同域，状态修改仍委托
/// _EditorPageState 既有方法，不产生新的文档或工具状态源。
extension _EditorPageTextOverlays on _EditorPageState {
  Widget _buildInlineEditor(PageTextItem item) {
    final viewPos = _controller.canvasToView(item.position);
    return Positioned(
      left: viewPos.dx,
      top: viewPos.dy,
      // V-08（审计 2026-09-27）：斜杠菜单键盘导航——Focus 包装节点是
      // TextField 焦点链的祖先，↑↓/Esc 在冒泡路径上先于应用级文本编辑
      // Shortcuts 到达此处；菜单展开时拦截驱动高亮，收起时全部放行。
      child: Focus(
        onKeyEvent: _onSlashMenuKey,
        child: Stack(
          children: [
            SizedBox(
              width: 320, // 固定编辑宽度，避免布局跳动
              child: TextField(
                controller: _editController,
                focusNode: _editFocus,
                autofocus: true,
                textInputAction: TextInputAction.done,
                maxLines: null,
                minLines: 1,
                style: TextStyle(
                  fontSize: item.fontSize * _controller.viewScale,
                  color: Color(item.color),
                ),
                decoration: InputDecoration(
                  isCollapsed: false,
                  // 可见文本框（对齐 Excalidraw 打字体验）：
                  // 空文本时也显示明显边框+背景，用户能清楚看到输入位置。
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.92),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppleRadius.xs),
                    ),
                    borderSide: BorderSide(
                      color: AppleColor.actionBlue,
                      width: 1.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppleRadius.xs),
                    ),
                    borderSide: BorderSide(
                      color: AppleColor.actionBlue.withValues(alpha: 0.7),
                      width: 1.5,
                    ),
                  ),
                  // 键盘焦点环：Focus Blue 2px（DESIGN.md:300/440）。
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppleRadius.xs),
                    ),
                    borderSide: BorderSide(
                      color: AppleColor.focusBlue,
                      width: 2,
                    ),
                  ),
                  hintText:
                      AppLocalizations.of(context)?.canvasTextOverlayHint ??
                      '输入文字…（回车结束）',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                onChanged: (_) {
                  // D5 斜杠命令：输入 / 展开快捷菜单，继续输入则收起。
                  final text = _editController.text;
                  final showSlash =
                      text == '/' ||
                      (text.endsWith('/') &&
                          !text.substring(0, text.length - 1).contains('/'));
                  if (showSlash != _slashOpen) {
                    _applyState(() {
                      _slashOpen = showSlash;
                      _slashHighlight = 0;
                    });
                  }
                },
                onSubmitted: (_) {
                  // V-08：菜单展开时 Enter 应用键盘高亮项（替代提交文本）。
                  if (_slashOpen) {
                    final cmds = _slashCommands;
                    _applySlashCommand(
                      cmds[_slashHighlight.clamp(0, cmds.length - 1)].apply,
                    );
                  } else {
                    _commitTextEditing();
                  }
                },
                onTapOutside: (_) {
                  _commitTextEditing();
                },
              ),
            ),
            // 斜杠命令菜单（D5，借鉴 Lokus）：输入 / 时弹出
            if (_slashOpen)
              Positioned(
                top: 26,
                left: 0,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(AppleRadius.xs),
                  color: Theme.of(context).colorScheme.surface,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, cmd) in _slashCommands.indexed)
                        _slashCommand(
                          label: cmd.label,
                          highlighted: i == _slashHighlight,
                          onTap: () => _applySlashCommand(cmd.apply),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 斜杠命令表（V-08）：菜单渲染与键盘 Enter 共用同一数据源。
  List<({String label, void Function(PageTextItem) apply})>
  get _slashCommands => [
    (
      label: AppLocalizations.of(context)?.textBold ?? '加粗',
      apply: (it) => it.bold = true,
    ),
    (
      label: AppLocalizations.of(context)?.textItalic ?? '斜体',
      apply: (it) => it.italic = true,
    ),
    (
      label: AppLocalizations.of(context)?.textTodo ?? '待办',
      apply: (it) => it.isTodo = true,
    ),
    (
      label: AppLocalizations.of(context)?.textCenter ?? '居中',
      apply: (it) => it.align = TextAlignType.center,
    ),
  ];

  /// 斜杠菜单键盘导航（V-08）：仅菜单展开时拦截 ↑↓/Esc；Enter 由
  /// TextField 的 onSubmitted 分支处理。收起时全部放行（就地编辑的
  /// 撤销/光标移动不受影响）。
  KeyEventResult _onSlashMenuKey(FocusNode _, KeyEvent event) {
    if (!_slashOpen || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final cmds = _slashCommands;
    if (key == LogicalKeyboardKey.arrowDown) {
      _applyState(() => _slashHighlight = (_slashHighlight + 1) % cmds.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _applyState(
        () =>
            _slashHighlight = (_slashHighlight - 1 + cmds.length) % cmds.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _applyState(() => _slashOpen = false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _slashCommand({
    required String label,
    required bool highlighted,
    required VoidCallback onTap,
  }) {
    // V-08：行高 vertical 8→12（20px 文本 + 24 = 44px 触控目标），
    // 键盘高亮项加 actionBlue 12% 底（与工具栏选中态同语言）。
    return AppleFocusRing(borderRadius: 0, child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        color: highlighted
            ? AppleColor.actionBlue.withValues(alpha: 0.12)
            : null,
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
    ));
  }

  /// 应用斜杠命令：给当前文字块设置样式，并清除 '/' 与菜单。
  void _applySlashCommand(void Function(PageTextItem) apply) {
    final item = _pendingTextItem;
    if (item != null) {
      apply(item);
    }
    // 移除末尾的 '/'。
    final t = _editController.text;
    if (t.endsWith('/')) {
      _editController.text = t.substring(0, t.length - 1);
    }
    _applyState(() => _slashOpen = false);
    _notifyChanged();
  }

  /// 文字块叠加层（可拖动、点击选中、双击编辑）。
  /// [item.isSticky] 为 true 时以便利贴（标签）样式渲染：色块背景 + 圆角。
  Widget _buildTextOverlay(PageTextItem item) {
    final viewPos = _controller.canvasToView(item.position);
    final selected =
        _selectedItemId == item.id || _multiSelectedIds.contains(item.id);
    // 连线模式下的起点高亮（橙色）：让用户看到已选中的端点。
    final linkSource = _linkMode && _linkSourceId == item.id;
    // 放置过渡动画：新元素淡入（借鉴 Excalidraw 克制的微交互）。
    // 删除淡出：删除中的元素透明度渐变为 0（_deletingIds 标记）。
    // 注意：Positioned 必须是最外层（直接位于 Stack 下）——渐显动画
    // 只能包内容体。此前动画包在 Positioned 外面，提交文字的一瞬间
    // 触发 ParentDataWidget 崩溃，整页渲染冻结（真机「画板打字即冻结」
    // 的根因之二）。
    return Positioned(
      left: viewPos.dx,
      top: viewPos.dy,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppleMotion.modal,
        curve: AppleMotion.easeOut,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: AnimatedOpacity(
          opacity: _deletingIds.contains(item.id) ? 0 : 1,
          duration: AppleMotion.dropdown,
          child: _buildTextOverlayInner(item, selected, linkSource),
        ),
      ),
    );
  }

  Widget _buildTextOverlayInner(
    PageTextItem item,
    bool selected,
    bool linkSource,
  ) {
    final textLayout = EditorTextPresentationStyle.layout(
      width: item.width,
      viewScale: _controller.viewScale,
    );
    return Semantics(
      // 与形状/图表/图片覆盖层同款语义包装：文字块是可点选/可拖拽的
      // 画布对象（内部 Text 提供内容名，此处补 button 角色）。
      label:
          AppLocalizations.of(context)?.canvasItemSemantics(
            AppLocalizations.of(context)?.canvasKindText ?? '文字',
          ) ??
          '画布对象：文字',
      button: true,
      child: GestureDetector(
        onTap: () => _onItemTap(item.id),
        onDoubleTap: _editTextItem,
        onSecondaryTapDown: (d) =>
            _showItemContextMenu(item.id, globalAnchor: d.globalPosition),
        // 触屏长按 = 右键等价入口（审计二-10）。
        onLongPressStart: (d) =>
            _showItemContextMenu(item.id, globalAnchor: d.globalPosition),
        onPanStart: (_) => _beginMixedDrag(),
        onPanUpdate: (d) => _dragItem(item.id, d.delta),
        onPanEnd: (_) => _commitMixedDrag(),
        onPanCancel: _cancelMixedDrag,
        child: Stack(
          children: [
            Container(
              constraints: item.isSticky
                  ? const BoxConstraints(minWidth: 120, minHeight: 40)
                  : null,
              padding: item.isSticky
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                  : EdgeInsets.zero,
              decoration: item.isSticky
                  ? BoxDecoration(
                      color: Color(item.color),
                      borderRadius: BorderRadius.circular(AppleRadius.xs),
                      border: selected || linkSource
                          ? Border.all(
                              color: linkSource
                                  ? AppleColor.favourite
                                  : AppleColor.actionBlue,
                              width: 1.5,
                            )
                          : null,
                    )
                  : (selected || linkSource
                        ? BoxDecoration(
                            border: Border.all(
                              color: linkSource
                                  ? AppleColor.favourite
                                  : AppleColor.actionBlue,
                              width: 1.5,
                            ),
                          )
                        : null),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 待办 checkbox（借鉴 QOwnNotes：点击切换勾选状态）。
                  // 缩放后图标常 <20px——外包 44×44 热区（HIG 最小触控尺寸），
                  // 视觉图标保持原尺寸居中，并暴露勾选语义给读屏。
                  if (item.isTodo)
                    Semantics(
                      checked: item.todoChecked,
                      button: true,
                      label: AppLocalizations.of(context)?.textDone ?? '完成',
                      // V-12（审计 2026-09-27）：画布待办勾选框键盘焦点此前
                      // 只有 focusColor overlay——补 2px Focus Blue 描边环。
                      // 半径 0：InkWell 无 borderRadius（方形）。
                      child: AppleFocusRing(
                        borderRadius: 0,
                        child: InkWell(
                          onTap: () {
                            _applyState(
                              () => item.todoChecked = !item.todoChecked,
                            );
                            _notifyChanged();
                          },
                          child: SizedBox(
                            width: AppleTouch.minTarget,
                            height: AppleTouch.minTarget,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  item.todoChecked
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size:
                                      item.fontSize *
                                      _controller.viewScale *
                                      0.9,
                                  color: Color(item.color),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // 多行文本（对齐 Excalidraw 文本框）：width 非 null 时
                  // 约束宽度 + softWrap 自动换行，可拖拽右侧手柄调整。
                  Flexible(
                    child: ConstrainedBox(
                      constraints: textLayout.constraints,
                      // 富文本片段渲染（落地 Quill Delta runs，独立实现）：
                      // 有 runs 时按片段应用各自样式（加粗/斜体/下划线/颜色），
                      // 无 runs（旧文档）回退整块样式。
                      child: item.runs != null
                          ? Text.rich(
                              TextSpan(
                                style:
                                    EditorTextPresentationStyle.richBaseStyle(
                                      fontSize: item.fontSize,
                                      viewScale: _controller.viewScale,
                                      fontFamily: item.fontFamily,
                                    ),
                                children: [
                                  for (final run in item.runs!)
                                    TextSpan(
                                      text: run.text,
                                      style:
                                          EditorTextPresentationStyle.richRunStyle(
                                            fallbackColor: item.color,
                                            color: run.color,
                                            bold: run.bold,
                                            italic: run.italic,
                                            underline: run.underline,
                                            strikethrough: run.strikethrough,
                                          ),
                                    ),
                                ],
                              ),
                              softWrap: textLayout.softWrap,
                              textAlign:
                                  EditorTextPresentationStyle.textAlignFor(
                                    item.align.name,
                                  ),
                            )
                          : Text(
                              item.text,
                              softWrap: textLayout.softWrap,
                              textAlign:
                                  EditorTextPresentationStyle.textAlignFor(
                                    item.align.name,
                                  ),
                              style:
                                  EditorTextPresentationStyle.plainTextStyle((
                                    fontSize: item.fontSize,
                                    viewScale: _controller.viewScale,
                                    color: item.color,
                                    fontFamily: item.fontFamily,
                                    isTodo: item.isTodo,
                                    todoChecked: item.todoChecked,
                                    isSticky: item.isSticky,
                                    bold: item.bold,
                                    italic: item.italic,
                                    underline: item.underline,
                                    strikethrough: item.strikethrough,
                                  )),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            // 宽度拖拽手柄（落地 Excalidraw resizeElements 的文字缩放
            // 重排版）：选中且有宽度时，右下角手柄拖拽同步调整宽度与字号
            // （字号随宽度比例缩放，保持文字整体版式不变形）。
            if (selected && item.width != null)
              Positioned(
                // 44×44 命中区、10×10 视觉点居中：视觉中心相对角点内收 1px
                // 与旧定位（right/bottom -4 + 10/2）保持一致。
                right: -21,
                bottom: -21,
                child: CanvasDragHandle(
                  // 会话边界与指针拖拽同形：聚焦时取锚点，失焦时清空。
                  // 键盘的离散步进与鼠标的一像素拖拽在宿主看来是同一件事
                  // ——CanvasDragHandle 把两条路径都归到 onPanUpdate，因此
                  // 宽度算法全库只有一份，不会分叉。
                  onPanStart: () {
                    _beginMixedDrag();
                    _textResizeAnchor = (
                      width: item.width!,
                      fontSize: item.fontSize,
                      x: _controller.canvasToView(item.position).dx,
                    );
                  },
                  onPanEnd: () {
                    _textResizeAnchor = null;
                    _commitMixedDrag();
                  },
                  onPanUpdate: (d) {
                    final anchor = _textResizeAnchor;
                    if (anchor == null) return;
                    final delta = screenDeltaToCanvas(
                      d,
                      _controller.viewRotation,
                      _controller.viewScale,
                    );
                    _applyState(() {
                      final newWidth = (anchor.width + delta.dx)
                          .clamp(40, 2000)
                          .toDouble();
                      // 字号随宽度等比缩放（Excalidraw measureFontSizeFromWidth
                      // 思路），最小 8pt 保证可读性。
                      item.fontSize =
                          (anchor.fontSize * newWidth / anchor.width)
                              .clamp(8.0, 120.0)
                              .toDouble();
                      item.width = newWidth;
                      // 推进会话基准：`onPanUpdate` 回的是**增量**——指针路径
                      // 每次只给「自上一事件以来的位移」，键盘路径给的是固定
                      // 步进。两者都要求「下一次从上一次的结果继续」，所以每
                      // 应用一次就把锚点推到新位置。不推进的话连按两次方向键
                      // 只会重复同一个宽度，指针拖拽也会一移动就弹回锚点。
                      _textResizeAnchor = (
                        width: newWidth,
                        fontSize: item.fontSize,
                        x: anchor.x,
                      );
                    });
                    _notifyChanged();
                  },
                  label:
                      AppLocalizations.of(context)?.textWidthHandle ?? '调整文字宽度',
                  hint:
                      AppLocalizations.of(context)?.canvasHandleKeyboardHint ??
                      '方向键微调，Shift 加速',
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 文字编辑动作（R1 归并 2026-11-17：自 editing 逐字搬移，与就地
  // 编辑渲染同域；editing 只剩图片/链接/菜单/删除等混排动作）──

  void _addTextItem(Offset canvasPoint) {
    final page = widget.session;
    if (page == null) {
      // 画布模式（问题5）：文字块存入文档 textItems，不再禁用文字工具。
      _addCanvasTextItem(canvasPoint);
      return;
    }

    // 先完成上一项，再开始新项，避免 setState 内再次 setState 造成输入框失焦。
    _commitTextEditing();
    _applyState(() {
      // 创建临时文字块（尚未加入页面，提交时才加入）。
      final item = EditorTextMutation.createDraft(
        id: LocalIdGenerator.next('txt'),
        x: canvasPoint.dx,
        y: canvasPoint.dy,
      );
      _beginTextSession(item);
      _editController.clear();
      _viewModel.setTextToolActive(false);
      _selectedItemId = null;
    });
    // 下一帧把焦点交给就地编辑框。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
    });
  }

  /// 画布模式（无限画布）添加文字块（问题5修复）。
  ///
  /// 与笔记本页一致：创建临时文字块进入就地编辑，提交时写入
  /// [DrawingDocument.textItems]，渲染由画布 overlay 层承载。
  void _addCanvasTextItem(Offset canvasPoint) {
    _commitTextEditing();
    _applyState(() {
      final item = EditorTextMutation.createDraft(
        id: LocalIdGenerator.next('txt'),
        x: canvasPoint.dx,
        y: canvasPoint.dy,
      );
      _beginTextSession(item);
      _editController.clear();
      _viewModel.setTextToolActive(false);
      _selectedItemId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
    });
  }

  /// 画布双击（对齐 Excalidraw 双击插入文字）：
  /// 双击空白处 -> 新建文字块并立即进入就地编辑；
  /// 双击已有文字块 -> 进入该文字块的编辑。
  void _onCanvasDoubleTap(TapDownDetails details) {
    final page = widget.session;
    final canvasPoint = _controller.viewToCanvas(details.localPosition);
    // 查找双击位置命中的文字块（取其编辑框）。
    final hitId = EditorTextMutation.hitTextId(
      items: page?.textItems ?? _controller.document.textItems,
      x: canvasPoint.dx,
      y: canvasPoint.dy,
    );
    if (hitId != null) {
      _applyState(() => _selectedItemId = hitId);
      _editTextItem();
      return;
    }
    // 空白处：新建文字并编辑（Excalidraw 同款顺滑插入，问题11：
    // 一点画面即可打字；画布/笔记两种模式均支持）。
    _addTextItem(canvasPoint);
  }

  /// 提交就地编辑的文字块：空文本则丢弃，非空则加入页面并保存。
  ///
  /// 注意：编辑"已有"文字块时，[pending] 已在 [page.textItems] 中，
  /// 不能重复添加（评审发现 P1：重复项会被持久化并叠加渲染）。
  void _commitTextEditing() {
    final page = widget.session;
    final pending = _pendingTextItem;
    if (pending == null || _editingItemId == null) return;

    final text = _editController.text;
    final targetItems = page?.textItems ?? _controller.document.textItems;
    final committed = EditorTextMutation.commit(
      pending: pending,
      rawText: text,
      items: targetItems,
    );
    if (committed) {
      _applyState(() {
        if (page == null) {
          // 画布模式（问题5）：写入文档 textItems。
          _controller.document.touch();
        }
        _selectedItemId = pending.id;
      });
      _notifyChanged();
    }
    // C-04：会话字段/状态机统一收口（不论文本是否有效变更都结束会话）。
    _endTextSession(committed: true);
    _editFocus.unfocus();
  }

  /// 结束就地编辑（点画布其他位置/切换工具时调用）。
  void _cancelTextEditing() {
    _commitTextEditing();
  }

  /// 添加"特殊标签"（便利贴样式文字块，弹窗输入，可拖动移动）。
  ///
  /// 与就地编辑并存：就地编辑用于快速文字，标签用于醒目分类标注。
  Future<void> _addStickyNote() async {
    final page = widget.session;
    if (page == null) return;

    // 先结束可能存在的就地编辑。
    _cancelTextEditing();

    final result = await GlassDialog.show<_TextDialogResult>(
      context: context,
      builder: (_) => const _TextInputDialog(),
    );
    if (result == null || result.text.trim().isEmpty) return;
    if (!mounted) return;

    _applyState(() {
      page.textItems.add(
        PageTextItem(
          id: LocalIdGenerator.next('txt'),
          x: _controller.document.width / 2 - 100,
          y: _controller.document.height / 2 - 40,
          text: result.text.trim(),
          fontSize: result.fontSize,
          color: 0xFFFFF59D, // 便利贴黄底，文字用深色
          isSticky: true,
        ),
      );
      _selectedItemId = page.textItems.last.id;
    });
    _notifyChanged();
  }

  /// 调节选中文字块的字号（工具栏滑块调用）。
  void _setSelectedTextFontSize(double size) {
    final page = widget.session;
    final id = _selectedItemId;
    if (page == null || id == null) return;
    final item = page.textItems.where((t) => t.id == id).firstOrNull;
    if (item == null) return;
    _applyState(() {
      EditorTextStyleMutation.setFontSize(item: item, size: size);
    });
    _notifyChanged();
  }

  /// 分页预览（D3：长笔记多页预览，借鉴 Umo Editor 分页模式）。
  ///
  /// 把页面文字块按 A4 页面高度（逻辑像素）分页渲染到预览对话框，
  /// 便于查看长笔记的分页效果（导出 PDF 时的版式）。
  Future<void> _showPaginationPreview() async {
    final page = widget.session;
    if (page == null) {
      _showSnack(
        AppLocalizations.of(context)?.edPreviewPagedOnly ?? '仅分页画布页面支持分页预览',
      );
      return;
    }
    if (page.textItems.isEmpty) {
      _showSnack(AppLocalizations.of(context)?.edNoTextHere ?? '本页还没有文字内容');
      return;
    }
    await GlassDialog.show<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)?.editorPagePreviewTitle(page.title) ??
              '分页预览 · ${page.title}',
        ),
        content: SizedBox(
          width: 480,
          height: 560,
          child: PaginationPreview(textItems: page.textItems),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context)?.close ?? '关闭'),
          ),
        ],
      ),
    );
  }

  /// 修改选中文字块的颜色（复用颜色选择对话框）。
  Future<void> _changeSelectedTextColor() async {
    final page = widget.session;
    final id = _selectedItemId;
    if (page == null || id == null) return;
    final item = page.textItems.where((t) => t.id == id).firstOrNull;
    if (item == null) return;

    final color = await GlassDialog.show<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initialColor: Color(item.color)),
    );
    if (color == null) return;
    if (!mounted) return;
    _applyState(() {
      EditorTextStyleMutation.setColor(item: item, color: color.toARGB32());
    });
    _notifyChanged();
  }

  /// 宏：批量改色（B1，借鉴 Trilium 脚本自动化）——
  /// 把页面所有文字块的颜色统一改为当前画笔颜色。
  void _macroRecolorAllText() {
    final page = widget.session;
    if (page == null) return;
    if (page.textItems.isEmpty) {
      _showSnack(AppLocalizations.of(context)?.edNoTextBlocks ?? '本页没有文字块');
      return;
    }
    final target = _controller.color.toARGB32();
    _applyState(() {
      EditorTextStyleMutation.recolorAll(items: page.textItems, color: target);
    });
    _notifyChanged();
    _showSnack(
      _l10nSafe?.edRecoloredN(page.textItems.length) ??
          '已批量改色 ${page.textItems.length} 个文字块',
    );
  }

  /// 编辑选中的文字块：双击/工具栏进入就地编辑（直接打字修改，
  /// 借鉴 OneNote/Word，替代弹窗输入）。
  void _editTextItem() {
    final page = widget.session;
    final id = _selectedItemId;
    if (id == null) return;
    // 独立画布模式（page == null）同样支持编辑——items 源与双击命中的
    // _onCanvasDoubleTap 同口径取 document.textItems；此前直接 return，
    // 画布文字块创建后双击永远进不了编辑。
    final source = page?.textItems ?? _controller.document.textItems;
    final item = EditorTextMutation.findById(items: source, id: id);
    if (item == null) return;

    _applyState(() {
      // 清理上一个未提交的就地编辑。
      _commitTextEditing();
      _beginTextSession(item);
      _editController.text = item.text;
    });
    // 下一帧把焦点交给就地编辑框，并把光标移到末尾。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editFocus.requestFocus();
      _editController.selection = TextSelection.collapsed(
        offset: _editController.text.length,
      );
    });
  }
}
