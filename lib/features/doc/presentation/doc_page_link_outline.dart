part of 'doc_page.dart';

// 大纲与页链域（O1 拆分自 doc_page.dart）：大纲条目、开关、页链插入、
// 跨文档打开。字段 _allDocsFutureCache 留在本体。行为零变化。

/// 大纲/页链/跨文档打开域私有助手（拆分自 doc_page.dart）。
extension _DocPageLinkOutline on _DocPageState {

  /// 从编辑器抽取大纲条目（桌面停靠栏与移动底部面板共用）。
  List<OutlineEntry> _outlineEntries() => [
    for (final e in _editorKey.currentState?.outline() ?? const [])
      OutlineEntry(id: e.id, level: e.level, text: e.text),
  ];


  /// 大纲开关：桌面切换右缘停靠栏，移动端弹底部半屏面板。
  ///
  /// 移动端不用停靠栏的原因：240 的固定宽度在 ~400dp 手机屏上会吃掉约 60%
  /// 屏宽，正文只剩 160dp（与「全部文档」侧栏同一个坑）。AFFiNE mobile 的
  /// 做法是把这类面板改为 sheet 覆盖层，内容临时浮于正文之上。
  void _onToggleOutline() {
    if (!isDesktopLayout(context)) {
      showDocOutlineSheet(
        context: context,
        entries: _outlineEntries(),
        onTapEntry: (id) => _editorKey.currentState?.scrollToBlock(id),
      );
      return;
    }
    pageSetState(() => _outlineOpen = !_outlineOpen);
  }


  /// 选择目标文档 → 在文末追加 [[标题]] 页面引用（M12.7 反向链接）。
  Future<void> _insertPageLink() async {
    final all = await _effectiveAllDocsFuture;
    if (all == null || !mounted) return;
    final candidates = all.where((d) => d.id != _doc.id).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final l10n = AppLocalizations.of(context);
    final target = await GlassDialog.show<NoteBlockDoc>(
      context: context,
      builder: (ctx) {
        // 键盘可达：对话框打开后首个选项直接获得焦点，↑↓/Enter 可导航。
        Widget optionFor(NoteBlockDoc d) => SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(d),
          child: ListTile(
            leading: const Icon(Icons.edit_note_rounded),
            title: Text(_docName(d)),
            subtitle: Text(
              '${l10n?.docUpdatedAt ?? '更新于'} ${formatShortDate(d.updatedAt)}',
            ),
          ),
        );
        return SimpleDialog(
          title: Text(l10n?.docInsertPageLink ?? '插入页面链接'),
          children: [
            for (final (i, d) in candidates.take(50).indexed)
              if (i == 0)
                Focus(autofocus: true, child: optionFor(d))
              else
                optionFor(d),
          ],
        );
      },
    );
    if (target == null) return;
    _editorKey.currentState?.appendPageLink(target);
  }


  Future<List<NoteBlockDoc>>? get _effectiveAllDocsFuture {
    final loader = widget.allDocsLoader;
    if (loader != null) return _allDocsFutureCache ??= loader();
    final store = widget.blockDocStore;
    if (store == null) return null;
    return _allDocsFutureCache ??= () async {
      final docs = <NoteBlockDoc>[];
      for (final id in await store.listIds()) {
        try {
          final d = await store.loadDocument(id);
          if (d != null) docs.add(d);
        } on BlockDocLockedException {
          continue; // N2：受密未解锁的笔记不进反向链接索引（fail-closed）
        }
      }
      return docs;
    }();
  }


  void _openDocByIdInternal(String id) {
    final store = widget.blockDocStore;
    if (store == null) return;
    // N2：受密未解锁的笔记点击反向链接 → 先解锁（与宿主路由同口径）。
    // R-08（审计 2026-09-27）：原 `.then` 链无 catchError 且未 await——
    // loadDocument 抛非锁定异常（IO/主备双坏 rethrow）时成为未处理异步
    // 异常，点击反向链接毫无反应。改 async/await + 统一兜底反馈。
    Future<void> run() async {
      try {
        final protected = await store.isBlockDocPasswordProtected(id);
        if (protected && !store.isBlockDocUnlocked(id)) {
          if (!mounted) return;
          final l10n = AppLocalizations.of(context);
          // C-09：重置流启动器由组合根注入；null（测试桩）时页脚不出现。
          final reset = widget.resetBlockDocPassword;
          final pin = await UnlockFlow.show(
            context,
            title: l10n?.docUnlockTitle ?? '该笔记已加密，输入密码',
            flexible: true,
            onVerify: (p) => store.verifyBlockDocPassword(id, p),
            footerLabel: reset != null
                ? (l10n?.docForgotPassword ?? '忘记密码？')
                : null,
            onFooter: reset == null
                ? null
                : () {
                    reset(context, store: store, docId: id);
                  },
          );
          if (pin == null && !store.isBlockDocUnlocked(id)) return;
        }
        NoteBlockDoc? doc;
        try {
          doc = await store.loadDocument(id);
        } on BlockDocLockedException {
          return; // 会话 DEK 已被清——不暴露内容
        }
        // doc 在 try 内赋值不做类型提升——经 final 局部变量收口空安全。
        final loaded = doc;
        if (!mounted || loaded == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DocPage(
              document: loaded,
              controller: DocController(onSave: (d) => store.saveDocument(d)),
              blockDocStore: store,
              tagStore: widget.tagStore,
              resetBlockDocPassword: widget.resetBlockDocPassword,
            ),
          ),
        );
      } catch (e) {
        AuditLogger.log(
          'doc.link.open_failed',
          success: false,
          detail: e.runtimeType.toString(),
        );
        if (!mounted) return;
        AppSnack.show(
          context,
          AppLocalizations.of(context)?.docOpenFailed ?? '打开失败，请重试',
        );
      }
    }
    unawaited(run());
  }
}
