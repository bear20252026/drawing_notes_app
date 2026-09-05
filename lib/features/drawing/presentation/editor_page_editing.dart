part of 'editor_page.dart';

// 编辑器文字/图片/形状编辑域（O1 拆分）：混排对象编辑方法从
// editor_page.dart 移出为 extension。这些方法完成文字块/图片/
// 形状/分组/链接的编辑；行为零变化。

/// 编辑器混排对象编辑域（拆分自 editor_page.dart）。
extension _EditorPageEditing on _EditorPageState {
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
      _editingItemId = item.id;
      _editController.clear();
      _viewModel.setTextToolActive(false);
      // 保存临时项供 overlay 渲染与提交。
      _pendingTextItem = item;
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
      _editingItemId = item.id;
      _editController.clear();
      _viewModel.setTextToolActive(false);
      _pendingTextItem = item;
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
    _editingItemId = null;
    _pendingTextItem = null;
    _slashOpen = false;
    _editFocus.unfocus();
  }

  /// 结束就地编辑（点画布其他位置/切换工具时调用）。
  void _cancelTextEditing() {
    _commitTextEditing();
    _editingItemId = null;
    _pendingTextItem = null;
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
  void _showPaginationPreview() {
    final page = widget.session;
    if (page == null) {
      _showSnack('仅分页画布页面支持分页预览');
      return;
    }
    if (page.textItems.isEmpty) {
      _showSnack('本页还没有文字内容');
      return;
    }
    GlassDialog.show<void>(
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
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
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
      _showSnack('本页没有文字块');
      return;
    }
    final target = _controller.color.toARGB32();
    _applyState(() {
      EditorTextStyleMutation.recolorAll(items: page.textItems, color: target);
    });
    _notifyChanged();
    _showSnack('已批量改色 ${page.textItems.length} 个文字块');
  }

  /// 图片工具：选择本地图片、复制为应用管理的离线副本后放置到画布中心。
  ///
  /// 分页笔记与独立绘图文档均支持导入；两者分别使用各自存储服务，避免
  /// 关闭或移动原文件后出现“图片图标存在但内容丢失”。
  Future<void> _insertImage() async {
    try {
      // file_selector：Flutter 官方文件选择器，跨 Windows/Android 一致，
      // 且已适配 AGP 9 的 built-in Kotlin（file_picker 存在兼容问题）。
      const typeGroup = XTypeGroup(
        label: '图片',
        extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      );
      final XFile? result = await openFile(acceptedTypeGroups: [typeGroup]);
      if (result == null || result.path.isEmpty) return;

      final center = Offset(
        _controller.document.width / 2,
        _controller.document.height / 2,
      );
      final page = widget.session;
      if (page != null) {
        final storage = widget.storage;
        if (storage == null) {
          _showSnack('笔记页图片存储不可用');
          return;
        }
        final storedPath = await storage.storeImage(result.path, page.id);
        final position = EditorImageMutation.pageImagePosition(
          centerX: center.dx,
          centerY: center.dy,
        );
        _applyState(() {
          page.imageItems.add(
            EditorImageMutation.createPageImage(
              id: LocalIdGenerator.next('img'),
              x: position.x,
              y: position.y,
              filePath: storedPath,
            ),
          );
          _selectedItemId = page.imageItems.last.id;
        });
      } else {
        final storage = widget.docStorage;
        if (storage == null) {
          _showSnack('绘图文档图片存储不可用');
          return;
        }
        final storedPath = await storage.storeImage(
          result.path,
          _controller.document.id,
        );
        final position = EditorImageMutation.documentImagePosition(
          centerX: center.dx,
          centerY: center.dy,
        );
        _applyState(() {
          _controller.document.imageItems.add(
            EditorImageMutation.createDocumentImage(
              id: StorageService.newId(),
              x: position.x,
              y: position.y,
              filePath: storedPath,
            ),
          );
          _controller.document.touch();
          _selectedItemId = _controller.document.imageItems.last.id;
        });
      }
      _notifyChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                    context,
                  )?.editorImageInsertFail(e.runtimeType.toString()) ??
                  '插入图片失败，请重试',
            ),
          ),
        );
      }
    }
  }

  /// 连线工具（D1）：连线模式下依次点选两个元素，创建连接线。
  void _toggleLinkMode() {
    _applyState(() {
      _toolMode.clearPointerModes();
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _controller.selectionTool = SelectionTool.none;
      _viewModel.setLinkMode(!_viewModel.linkMode);
      _viewModel.setLinkSourceId(null);
    });
  }

  /// 元素被选中：连线模式下作为连线端点；否则普通选中。
  void _onItemTap(String itemId) {
    // 元素超链接（借鉴 Excalidraw hyperlink）：有 href 的元素点击时
    // 用系统默认浏览器打开（Windows 用 start 命令）。
    final page = widget.session;
    if (page != null) {
      final href = EditorHyperlinkMutation.hrefOf(
        id: itemId,
        textItems: page.textItems,
        imageItems: page.imageItems,
        shapes: page.shapes,
      );
      if (href != null && href.isNotEmpty) {
        _openHref(href);
        return;
      }
    }
    if (_linkMode) {
      if (_linkSourceId == null) {
        _applyState(() => _viewModel.setLinkSourceId(itemId));
        _showSnack('已选择起点，再点击另一个元素完成连线');
      } else if (_linkSourceId != itemId) {
        final page = widget.session;
        if (page != null) {
          final connector = EditorLinkMutation.createConnector(
            sourceId: _linkSourceId,
            targetId: itemId,
            connectorId: LocalIdGenerator.next('cn'),
          );
          if (connector == null) return;
          _applyState(() {
            page.connectors.add(connector);
            _viewModel.setLinkSourceId(null);
            _viewModel.setLinkMode(false);
          });
          _notifyChanged();
          _showSnack('已创建连接');
        }
      }
      return;
    }
    _applyState(() => _selectedItemId = itemId);
  }

  /// 图层顺序操作（置顶/置底/上移/下移，借鉴 Excalidraw 图层操作）。
  ///
  /// 使用 fractional indexing 排序键（[fractionalIndex]，参考 Excalidraw）：
  /// 置顶/置底只需在边界生成一个新键，上移/下移只需与相邻元素交换键，
  /// 不需要重排其余元素的层级号。旧文档无键时按 zOrder 相对顺序补齐一次，
  /// 序列化向后兼容。
  void _reorderSelected(int mode) {
    final page = widget.session;
    if (page == null) return;
    final ids = _expandGroup(
      _multiSelectedIds.isNotEmpty
          ? _multiSelectedIds
          : <String>{?_selectedItemId},
    );
    if (ids.isEmpty) return;

    final entries = <EditorLayerOrderEntry>[
      for (final text in page.textItems)
        EditorLayerOrderEntry(
          id: text.id,
          fractionalIndex: text.fractionalIndex,
          zOrder: text.zOrder,
        ),
      for (final image in page.imageItems)
        EditorLayerOrderEntry(
          id: image.id,
          fractionalIndex: image.fractionalIndex,
          zOrder: image.zOrder,
        ),
      for (final shape in page.shapes)
        EditorLayerOrderEntry(
          id: shape.id,
          fractionalIndex: shape.fractionalIndex,
          zOrder: shape.zOrder,
        ),
    ];
    if (entries.isEmpty) return;

    final assignments = EditorLayerOrderMutation.reorder(
      entries: entries,
      selectedIds: ids,
      mode: mode,
    );
    if (assignments.isEmpty) return;

    void assign(String id, String? key) {
      for (final text in page.textItems) {
        if (text.id == id) {
          text.fractionalIndex = key;
          return;
        }
      }
      for (final image in page.imageItems) {
        if (image.id == id) {
          image.fractionalIndex = key;
          return;
        }
      }
      for (final shape in page.shapes) {
        if (shape.id == id) {
          shape.fractionalIndex = key;
          return;
        }
      }
    }

    _applyState(() {
      assignments.forEach(assign);
    });
    _notifyChanged();
  }

  /// 上下文菜单（借鉴 Excalidraw 菜单）：复制样式/删除/置顶/置底。
  ///
  /// 触达（审计二-10）：右键 / 触屏长按 / 键盘 Menu 键或 Shift+F10。
  /// [globalAnchor] 非空时菜单锚定触发点（指针/长按）；键盘触发为空，
  /// 落在画布中央偏上（不再是硬编码 100,100）。
  void _showItemContextMenu(String itemId, {Offset? globalAnchor}) {
    _applyState(() => _selectedItemId = itemId);
    final RelativeRect position;
    if (globalAnchor != null) {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      final bounds = overlay?.semanticBounds ?? Rect.fromLTWH(0, 0, 800, 600);
      position = RelativeRect.fromRect(
        Rect.fromPoints(globalAnchor, globalAnchor.translate(1, 1)),
        Offset.zero & bounds.size,
      );
    } else {
      final size = MediaQuery.sizeOf(context);
      position = RelativeRect.fromLTRB(size.width / 2, size.height / 3, 0, 0);
    }
    showMenu<_CtxAction>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(value: _CtxAction.copyStyle, child: Text('复制样式')),
        PopupMenuItem(value: _CtxAction.group, child: Text('分组')),
        PopupMenuItem(value: _CtxAction.link, child: Text('设置链接…')),
        PopupMenuItem(value: _CtxAction.ungroup, child: Text('取消分组')),
        PopupMenuItem(value: _CtxAction.delete, child: Text('删除')),
        PopupMenuItem(value: _CtxAction.bringToFront, child: Text('置顶')),
        PopupMenuItem(value: _CtxAction.sendToBack, child: Text('置底')),
      ],
    ).then((action) {
      switch (action) {
        case _CtxAction.copyStyle:
          _copySelectedStyle();
        case _CtxAction.group:
          _groupSelected();
        case _CtxAction.link:
          _setLink();
        case _CtxAction.ungroup:
          _ungroupSelected();
        case _CtxAction.delete:
          _deleteSelectedItem();
        case _CtxAction.bringToFront:
          _reorderSelected(0);
        case _CtxAction.sendToBack:
          _reorderSelected(1);
        case null:
          break;
      }
    });
  }

  /// 删除选中的混排对象。
  /// 打开超链接（Windows 用 start 命令调默认浏览器；其他平台提示）。
  void _openHref(String href) {
    // 审计修复（2026-08-15，命令注入面）：scheme 白名单 + 引号包裹。
    final safe = sanitizeHref(href);
    if (safe == null) {
      _showSnack('链接无效或不受支持');
      return;
    }
    try {
      if (Platform.isWindows) {
        // 链 F 调用点加固（军工审计 2026-08-15）：cmd /c start 会把 URL 的
        // & | ^ 解释为命令分隔符（CVE-2026-32948/22168 同源模式），且 %VAR%
        // 会被展开——改用 rundll32 url.dll,FileProtocolHandler 绕过 cmd.exe，
        // URL 原样交给 OS 协议处理器（multica PR #1202 社区批准标准修复）。
        // sanitizeHref 已拒绝 " 和 %（输入侧双保险）。
        Process.start('rundll32', ['url.dll,FileProtocolHandler', safe]);
      } else {
        Process.start('xdg-open', [safe]);
      }
      _showSnack('已打开链接');
    } catch (e) {
      _showSnack('无法打开链接：$e');
    }
  }

  /// 设置元素超链接（借鉴 Excalidraw hyperlink）：输入 URL 绑定到选中元素，
  /// 元素点击时用系统默认浏览器打开。
  Future<void> _setLink() async {
    final page = widget.session;
    final id = _selectedItemId;
    if (page == null || id == null) return;
    // 找到当前 href（若有）。
    final current = EditorHyperlinkMutation.hrefOf(
      id: id,
      textItems: page.textItems,
      imageItems: page.imageItems,
      shapes: page.shapes,
    );
    final controller = TextEditingController(text: current ?? '');
    final url = await GlassDialog.show<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置链接'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: AppleDialog.actions([
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('确定'),
          ),
        ]),
      ),
    );
    if (url == null) return;
    final trimmed = url.trim();
    // 审计修复（2026-08-15）：保存前 scheme 白名单校验，拒绝危险链接。
    final link = trimmed.isEmpty ? null : sanitizeHref(trimmed);
    if (trimmed.isNotEmpty && link == null) {
      _showSnack('链接仅支持 http/https/mailto');
      return;
    }
    _applyState(() {
      EditorHyperlinkMutation.setHref(
        id: id,
        href: link,
        textItems: page.textItems,
        imageItems: page.imageItems,
        shapes: page.shapes,
      );
    });
    _notifyChanged();
    _showSnack(link == null ? '已清除链接' : '已设置链接');
  }

  /// 分组：给选中的多个元素设置相同 groupId（借鉴 Excalidraw groupIds）。
  void _groupSelected() {
    final page = widget.session;
    if (page == null) return;
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    if (ids.length < 2) {
      _showSnack('请先框选/多选至少 2 个元素再分组');
      return;
    }
    final groupId = LocalIdGenerator.next('grp');
    _applyState(() {
      EditorPageObjectMutation.setGroupId(
        ids: ids,
        groupId: groupId,
        textItems: page.textItems,
        imageItems: page.imageItems,
        shapes: page.shapes,
      );
    });
    _notifyChanged();
    _showSnack('已分组 ${ids.length} 个元素');
  }

  /// 取消分组：清空选中元素的 groupId。
  void _ungroupSelected() {
    final page = widget.session;
    if (page == null) return;
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    _applyState(() {
      EditorPageObjectMutation.setGroupId(
        ids: ids,
        groupId: null,
        textItems: page.textItems,
        imageItems: page.imageItems,
        shapes: page.shapes,
      );
    });
    _notifyChanged();
    _showSnack('已取消分组');
  }

  void _deleteSelectedItem() {
    final page = widget.session;
    if (page == null) return;
    // 多选删除：删除全部选中的混排对象（文字/图片/形状，借鉴 Excalidraw 多选）。
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    if (ids.isEmpty) return;
    // 删除淡出动画：先标记为删除中，180ms 后真正移除（借鉴 Excalidraw）。
    _applyState(() {
      _canvasInteraction.beginDeleting(ids);
      _canvasInteraction.clearObjectSelection();
    });
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _applyState(() {
        EditorPageObjectMutation.remove(
          ids: ids,
          textItems: page.textItems,
          imageItems: page.imageItems,
          shapes: page.shapes,
          charts: page.charts,
        );
        _canvasInteraction.finishDeleting(ids);
      });
      _notifyChanged();
    });
  }

  /// 缩放控件：放大（借鉴 Excalidraw 缩放导航）。
  void _zoomIn() {
    _controller.viewScale = (_controller.viewScale * 1.25).clamp(0.05, 20.0);
    _controller.tickFrame();
  }

  /// 缩放控件：缩小。
  void _zoomOut() {
    _controller.viewScale = (_controller.viewScale / 1.25).clamp(0.05, 20.0);
    _controller.tickFrame();
  }

  /// 缩放控件：恢复 100%。
  void _zoomReset() {
    _controller.viewScale = 1.0;
    _controller.tickFrame();
  }

  /// 编辑选中的文字块：双击/工具栏进入就地编辑（直接打字修改，
  /// 借鉴 OneNote/Word，替代弹窗输入）。
  void _editTextItem() {
    final page = widget.session;
    final id = _selectedItemId;
    if (page == null || id == null) return;
    final item = EditorTextMutation.findById(items: page.textItems, id: id);
    if (item == null) return;

    _applyState(() {
      // 清理上一个未提交的就地编辑。
      _commitTextEditing();
      _editingItemId = item.id;
      _editController.text = item.text;
      _pendingTextItem = item;
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
