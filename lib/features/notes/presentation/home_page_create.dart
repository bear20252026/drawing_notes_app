part of 'home_page.dart';

/// 创建流与编辑器导航（审计 2026-09-26 #37：自 home_page.dart 拆出，
/// 行为零变化）——画布/分页画布/笔记的新建、已有画布打开、加密解锁。
extension _HomePageCreateOps on _HomePageState {
  Widget _buildEditorPage({
    DrawingDocument? document,
    StorageService? documentStorage,
  }) {
    final builder = widget.editorPageBuilder;
    if (builder == null) {
      return Scaffold(
        body: Center(
          child: Text(_l10nSafe?.shellEditorNotAssembled ?? '编辑器尚未由应用层装配'),
        ),
      );
    }
    return builder(
      document: document,
      documentStorage: documentStorage,
      // C-06（审计 2026-09-27）：编辑器内嵌图片解密服务传线。
      mediaCrypto: widget.mediaCrypto,
    );
  }

  Future<void> _openEditor({
    DrawingDocument? document,
    StorageService? documentStorage,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _buildEditorPage(
          document: document,
          documentStorage: documentStorage,
        ),
      ),
    );
  }

  // ---------------- 画布（N1：画布 tab 收口无限画布/分页画布两类型） ----------------

  /// 「新建画布」：弹两选项（新建无限画布 / 新建分页画布）——
  /// 命名体系定案（2026-09-02）：无限画布=「画布」，旧笔记本=「分页画布」。
  Future<void> _createCanvas() async {
    final choice = await GlassDialog.show<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_l10nSafe?.docsNewCanvas ?? '新建画布'),
        children: [
          // 键盘可达：对话框打开时焦点落在首个选项上。
          Focus(
            autofocus: true,
            child: SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: ListTile(
                leading: const Icon(Icons.brush_rounded),
                title: Text(_l10nSafe?.homeNewInfiniteCanvas ?? '新建无限画布'),
                subtitle: Text(
                  _l10nSafe?.homeNewInfiniteCanvasSub ?? '自由绘制、图形与关系图',
                ),
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: ListTile(
              leading: const Icon(Icons.auto_stories_rounded),
              title: Text(_l10nSafe?.docsNewPagedCanvas ?? '新建分页画布'),
              subtitle: Text(
                _l10nSafe?.homeNewPagedCanvasSub ?? '多页装订、纸张模板与图文混排',
              ),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice) {
      await _createDrawing();
    } else {
      await _createNotebook();
    }
  }

  /// 新建无限画布并进入绘图工作区。
  Future<void> _createDrawing() async {
    final name = await GlassDialog.show<String>(
      context: context,
      builder: (ctx) =>
          _NameDialog(title: _l10nSafe?.homeNewInfiniteCanvas ?? '新建无限画布'),
    );
    if (name == null || name.trim().isEmpty) return;

    final doc = DrawingDocument(
      id: StorageService.newId(),
      title: name.trim(),
      infinite: true,
    );
    if (!mounted) return;
    await _openEditor(document: doc, documentStorage: _docStorage);
    unawaited(_refresh());
  }

  /// 新建分页画布并进入页面管理（旧「新建笔记本」入口恢复——N1）。
  ///
  /// 命名修复（2026-09-06）：此前硬编码「未命名」、无命名弹窗，用户无法给
  /// 分页画布起名（与「新建无限画布」的 [_NameDialog] 不对称）。现创建前先
  /// 命名；取消/空名则取消创建（与 _createDrawing 同语义）。
  ///
  /// U5a（审计 P2-6）：保存失败不再裸奔——原实现 save 抛错会未捕获
  /// 崩溃且用户无感知；现提示失败原因并停留在首页（不进入未落盘的
  /// 编辑页，避免后续保存连环失败）。
  Future<void> _createNotebook() async {
    final name = await GlassDialog.show<String>(
      context: context,
      builder: (ctx) =>
          _NameDialog(title: _l10nSafe?.docsNewPagedCanvas ?? '新建分页画布'),
    );
    if (name == null || name.trim().isEmpty) return;
    final nb = Notebook(
      id: NotebookStorage.newId('notebook'),
      title: name.trim(),
    );
    try {
      await _nbStorage.save(nb);
    } catch (_) {
      _showSnack(_l10nSafe?.homeCreateFailedFull ?? '新建失败：分页画布未能保存，请检查磁盘空间后重试');
      return;
    }
    widget.onDataChanged?.call();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotebookViewPage(
          notebook: nb,
          storage: _nbStorage,
          blockDocStore: _blockDocStore,
          editorPageBuilder: widget.editorPageBuilder,
          // C-06（审计 2026-09-27）：媒体服务同一实例传线。
          mediaCrypto: widget.mediaCrypto,
        ),
      ),
    );
    await _refresh();
  }

  /// 打开已有画布继续编辑。
  ///
  /// 批次②：受独立密码保护的画布先输密码（4–12 位可变长度密码盘，
  /// 验证成功即缓存进会话，本会话免重复输入）。
  Future<void> _openDrawing(DocumentMeta meta) async {
    try {
      // meta.locked 为列表占位（无会话密码）；再查一次文件头防元信息过期。
      if (meta.locked || await _docStorage.isFilePasswordProtected(meta.id)) {
        final unlocked = await _promptFilePassword(meta);
        if (!unlocked) return; // 用户取消 / 放弃
      }
      final doc = await _docStorage.load(meta.id);
      if (doc == null) {
        _showSnack(_l10nSafe?.homeCanvasMissing ?? '画布文件不存在或已损坏');
        return;
      }
      if (!mounted) return;
      await _openEditor(document: doc, documentStorage: _docStorage);
      unawaited(_refresh());
    } catch (e) {
      _showSnack(_l10nSafe?.homeOpenCanvasFailed ?? '打开画布失败，请重试');
    }
  }

  /// 加密画布解锁输入（验证通过密码已入会话缓存）。
  ///
  /// N4 批 2：左下角「忘记密码？」→ 重置密码盘重置流；重置成功后
  /// 会话已缓存新密码，本方法直接返回 true（调用方可继续打开）。
  Future<bool> _promptFilePassword(DocumentMeta meta) async {
    final pin = await UnlockFlow.show(
      context,
      title: _l10nSafe?.canvasDeletePasswordTitle ?? '该画布已加密，输入独立密码',
      flexible: true,
      onVerify: (p) => _docStorage.verifyFilePassword(meta.id, p),
      footerLabel: _l10nSafe?.homeForgotPasswordLink ?? '忘记密码？',
      onFooter: () {
        FilePasswordResetFlow.show(
          context,
          storage: _docStorage,
          docId: meta.id,
          docTitle: meta.title,
        );
      },
    );
    // pin 非空 = 验证通过；null 但会话已有密码 = 刚被重置流解锁。
    return pin != null || _docStorage.filePasswordFor(meta.id) != null;
  }

  // ---------------- 笔记（块文档；M12：笔记本=笔记） ----------------

  Future<void> _createNote() async {
    // M12.6 模板库：新建时选择模板（空白/会议纪要/每日日志/待办清单）。
    final template = await GlassDialog.show<DocTemplate>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_l10nSafe?.homeSelectTemplate ?? '选择笔记模板'),
        children: [
          for (final t in DocTemplate.values)
            // 键盘可达：首个模板选项初始聚焦。
            Focus(
              autofocus: t == DocTemplate.values.first,
              child: SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(t),
                child: ListTile(
                  leading: Icon(_templateIcon(t)),
                  title: Text(_docTemplateNameOf(context, t) ?? t.label),
                  subtitle: Text(_docTemplateDescOf(context, t)),
                ),
              ),
            ),
        ],
      ),
    );
    if (template == null || !mounted) return;

    var blockId = 0;
    final doc = NoteBlockDoc(
      id: NoteBlockDocStore.newId(),
      body: buildTemplateBody(template, () => 'block_${blockId++}'),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    try {
      await _blockDocStore.saveDocument(doc);
    } catch (e) {
      _showSnack(_l10nSafe?.homeCreateFailed ?? '创建失败，请重试');
      return;
    }
    widget.onDataChanged?.call();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocPage(
          document: doc,
          controller: DocController(
            onSave: (d) => _blockDocStore.saveDocument(d),
          ),
        ),
      ),
    );
    await _refresh();
  }

  /// 模板 → 图标（application 层不依赖 material，图标在展示层映射）。
  IconData _templateIcon(DocTemplate t) {
    switch (t) {
      case DocTemplate.blank:
        return Icons.crop_square_rounded;
      case DocTemplate.meeting:
        return Icons.groups_rounded;
      case DocTemplate.daily:
        return Icons.today_rounded;
      case DocTemplate.todoList:
        return Icons.checklist_rounded;
    }
  }
}
