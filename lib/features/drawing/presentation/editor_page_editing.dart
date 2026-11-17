part of 'editor_page.dart';

// 编辑器混排动作域（O1 拆分；R1 归并 2026-11-17 后文字编辑移往
// text_overlays、缩放移往 input、分组移往 drag_ops）：图片插入、
// 链接、点选/菜单/层序/删除等跨对象动作。

/// 编辑器混排动作域（拆分自 editor_page.dart）。
extension _EditorPageEditing on _EditorPageState {
  /// 图片工具：选择本地图片、复制为应用管理的离线副本后放置到画布中心。
  ///
  /// 分页笔记与独立绘图文档均支持导入；两者分别使用各自存储服务，避免
  /// 关闭或移动原文件后出现“图片图标存在但内容丢失”。
  Future<void> _insertImage() async {
    try {
      // file_selector：Flutter 官方文件选择器，跨 Windows/Android 一致，
      // 且已适配 AGP 9 的 built-in Kotlin（file_picker 存在兼容问题）。
      final typeGroup = XTypeGroup(
        label: AppLocalizations.of(context)?.edImageLabel ?? '图片',
        extensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      );
      // 「切后台即锁」豁免（[LockExemption]，import 在库本体 editor_page.dart）：
      // 原生图片选择器抢走 OS 焦点会投 inactive/hidden，不豁免就在选图途中
      // 假锁开屏、hidden 侧还清 KEK/会话口令。窗口**只**圈下面那一次对话框
      // 调用——拷图进应用存储（mediaCrypto 解密/加密读写）与后续弹框一律在
      // 窗口外，需要密钥的操作照常受锁约束；取消/异常由 run 的 finally 释放。
      final XFile? result = await LockExemption.run(
        () => openFile(acceptedTypeGroups: [typeGroup]),
      );
      if (result == null || result.path.isEmpty) return;
      if (!mounted) return;

      final center = Offset(
        _controller.document.width / 2,
        _controller.document.height / 2,
      );
      final page = widget.session;
      if (page != null) {
        final storage = widget.storage;
        if (storage == null) {
          _showSnack(_l10nSafe?.edNoteImageStoreUnavailable ?? '笔记页图片存储不可用');
          return;
        }
        // K_note（2026-11-16）：笔记本上下文——媒体按笔记本密钥加密。
        final nbId = widget.notebookId;
        if (nbId == null) {
          _showSnack('笔记页图片存储缺少笔记本上下文');
          return;
        }
        final storedPath = await storage.storeImage(nbId, result.path, page.id);
        if (!mounted) return;
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
          _showSnack(
            _l10nSafe?.edDrawingImageStoreUnavailable ?? '绘图文档图片存储不可用',
          );
          return;
        }
        final storedPath = await storage.storeImage(
          result.path,
          _controller.document.id,
        );
        if (!mounted) return;
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
              AppLocalizations.of(context)
                      ?.editorImageInsertFail(errorCode(e)) ??
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
        _showSnack(_l10nSafe?.edLinkStartPicked ?? '已选择起点，再点击另一个元素完成连线');
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
          _showSnack(_l10nSafe?.edLinkCreated ?? '已创建连接');
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
      items: [
        PopupMenuItem(
          value: _CtxAction.copyStyle,
          child: Text(AppLocalizations.of(context)?.ctxCopyStyle ?? '复制样式'),
        ),
        PopupMenuItem(
          value: _CtxAction.group,
          child: Text(AppLocalizations.of(context)?.ctxGroup ?? '分组'),
        ),
        PopupMenuItem(
          value: _CtxAction.link,
          // L-07（审计 2026-09-27）：同菜单其余项全走 ctx* 键，本项补键。
          child: Text(AppLocalizations.of(context)?.ctxSetLink ?? '设置链接…'),
        ),
        PopupMenuItem(
          value: _CtxAction.ungroup,
          child: Text(AppLocalizations.of(context)?.ctxUngroup ?? '取消分组'),
        ),
        PopupMenuItem(
          value: _CtxAction.delete,
          child: Text(AppLocalizations.of(context)?.delete ?? '删除'),
        ),
        PopupMenuItem(
          value: _CtxAction.bringToFront,
          child: Text(AppLocalizations.of(context)?.ctxBringToFront ?? '置顶'),
        ),
        PopupMenuItem(
          value: _CtxAction.sendToBack,
          child: Text(AppLocalizations.of(context)?.ctxSendToBack ?? '置底'),
        ),
      ],
    ).then((action) {
      if (!mounted) return;
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
  Future<void> _openHref(String href) async {
    // 审计修复（2026-08-15，命令注入面）：scheme 白名单 + 引号包裹。
    final safe = sanitizeHref(href);
    if (safe == null) {
      _showSnack(_l10nSafe?.edLinkInvalid ?? '链接无效或不受支持');
      return;
    }
    // H1（2026-11）：平台调用下沉到 core/utils（presentation 不 import dart:io）。
    // 链 F 加固（军工审计 2026-08-15）：Windows 走 rundll32 url.dll,
    // FileProtocolHandler 绕过 cmd.exe——cmd /c start 会把 URL 的 & | ^
    // 解释为命令分隔符（CVE-2026-32948/22168 同源模式），且 %VAR% 会被展开。
    // sanitizeHref 已拒绝 " 和 %（输入侧双保险）。
    final opened = await openExternalUrl(safe);
    if (opened) {
      _showSnack(_l10nSafe?.edLinkOpened ?? '已打开链接');
    } else {
      AuditLogger.log(
        'editor.href.open_failed',
        success: false,
        detail: 'launch_failed',
      );
      _showSnack(
        _l10nSafe?.linkOpenFailedSnack('launch_failed') ??
            '无法打开链接：launch_failed',
      );
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
    // 对话框返回（pop 即完成）后退出动画仍在跑，动画期间 TextField 重建
    // 会触碰 controller；捕获路由完全退出的时机，动画结束再释放。
    var routeExited = Future<void>.value();
    String? url;
    try {
      url = await GlassDialog.show<String>(
        context: context,
        builder: (ctx) {
          routeExited = ModalRoute.of(ctx)!.completed;
          return AlertDialog(
            title: Text(AppLocalizations.of(context)?.edLinkTitle ?? '设置链接'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'https://…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(AppleRadius.xs),
                  ),
                ),
                isDense: true,
              ),
            ),
            actions: AppleDialog.actions([
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.of(context)?.cancel ?? '取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                child: Text(
                  AppLocalizations.of(context)?.commonConfirm ?? '确定',
                ),
              ),
            ]),
          );
        },
      );
      await routeExited;
    } finally {
      controller.dispose();
    }
    if (url == null) return;
    if (!mounted) return;
    final trimmed = url.trim();
    // 审计修复（2026-08-15）：保存前 scheme 白名单校验，拒绝危险链接。
    final link = trimmed.isEmpty ? null : sanitizeHref(trimmed);
    if (trimmed.isNotEmpty && link == null) {
      _showSnack(
        _l10nSafe?.linkSchemeUnsupportedSnack ?? '链接仅支持 http/https/mailto',
      );
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
    _showSnack(
      link == null
          ? _l10nSafe?.edLinkCleared ?? '已清除链接'
          : _l10nSafe?.edLinkSet ?? '已设置链接',
    );
  }

  void _deleteSelectedItem() {
    final page = widget.session;
    // V-01（审计 2026-09-27）：独立画布模式（session 为空）此前直接
    // return——Delete/选中工具条的删除对画布文字对象全是 no-op（伴生
    // 缺口，指针与键盘一起受害）。画布模式可选对象 = document.textItems
    // （与 forCanvas 计划同源），回退到文档集合删除。
    final textItems = page?.textItems ?? _controller.document.textItems;
    // 多选删除：删除全部选中的混排对象（文字/图片/形状，借鉴 Excalidraw 多选）。
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    if (ids.isEmpty) return;
    // 删除淡出动画：先标记为删除中，稍后真正移除（借鉴 Excalidraw）。
    _applyState(() {
      _canvasInteraction.beginDeleting(ids);
      _canvasInteraction.clearObjectSelection();
    });
    // M-03（审计 2026-09-27）：移除延迟与配对淡出动画同用 AppleMotion
    // .dropdown（200ms）——原裸 180ms 会让元素在淡出完成前 20ms 被移除，
    // 动画截断跳变；两处引用同一令牌常量即永不再漂移。
    Future.delayed(AppleMotion.dropdown, () {
      if (!mounted) return;
      _applyState(() {
        // EUI-02（第四轮审计）：删除登记成一条可撤销记录。
        MixedObjectDeleteRecorder.deleteAndRecord(
          ids: ids,
          textItems: textItems,
          imageItems: page?.imageItems ?? <PageImageItem>[],
          shapes: page?.shapes ?? <PageShapeItem>[],
          charts: page?.charts ?? <PageChartItem>[],
          host: _controller,
          markDirty: _notifyChanged,
        );
        _canvasInteraction.finishDeleting(ids);
      });
      _notifyChanged();
    });
  }
}
