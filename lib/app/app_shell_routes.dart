// C-07（审计 2026-09-27）：app_shell 三职责拆分——本 part 承载路由装配域。
//
// 内容（自 app_shell.dart 库内拆出，extension on _AppShellState，同
// doc_page 六 part 先例）：
// - open* 方法群：_openAllDoc / _newAllDoc / _openTrash / _openBlockDocById；
// - 全量文档聚合查询 _loadAllDocs 与收藏切换 _toggleFavorite；
// - 三类密码解锁拦截：_ensureBlockDocUnlocked / _loadBlockDocGuarded；
// - 命名同源回写 _syncBlockDocTitleToNotebookPage。
//
// 零行为变化承诺：路由参数、解锁拦截顺序、mounted 守卫、错误兜底与拆分
// 前逐条一致——纯搬移，未改任何控制流。服务实例经主文件 _services
// （组合根 createAppServices 装配，见 composition_root.dart C-07 裁决）。
part of 'app_shell.dart';

/// 路由装配域（C-07）：AppShell 三职责之一——页面构造 + 解锁拦截 + 导航
/// 参数装配。导航 UI（rail/底部导航/_onSelect/build）留在主文件。
extension _AppShellRoutes on _AppShellState {
  /// N2：加载块文档——锁定异常折叠为 null（fail-closed，不暴露内容）。
  /// 独立 helper 以保证空安全类型提升（try 内赋值的局部变量不提升）。
  Future<NoteBlockDoc?> _loadBlockDocGuarded(
    NoteBlockDocStore store,
    String id,
  ) async {
    try {
      return await store.loadDocument(id);
    } on BlockDocLockedException {
      return null; // 会话 DEK 已被清（如切后台）——不暴露内容
    }
  }

  /// 命名同源（2026-09-07）：块文档与分页画布页是同一逻辑文件
  /// （doc.id == page.id）。在 DocPage 改标题后回写源页并让克隆快照
  /// 跟随，使分页画布页卡、搜索等展示区即时一致。
  ///
  /// 加密分页画布跳过：此处无会话密码，NotebookStorage.save 对加密本
  /// 抛 StateError，不能在此落盘；下次在该本内保存时由 NotebookViewPage
  /// 的命名收敛（块文档标题优先方向）补齐。失败不阻断保存主流程。
  Future<void> _syncBlockDocTitleToNotebookPage(
    String docId,
    String title,
  ) async {
    final storage = widget.notebookStorage;
    if (storage == null) return;
    try {
      for (final nb in await storage.listAll()) {
        if (nb.isLockedPlaceholder || nb.encrypted) continue;
        var changed = false;
        for (final page in nb.pages) {
          final ref = page.cloneOf;
          if (ref == null) {
            if (page.id == docId && page.title != title) {
              page
                ..title = title
                ..updatedAt = DateTime.now();
              changed = true;
            }
            continue;
          }
          if (ref.pageId != docId) continue;
          final expected = NotebookTitleSync.cloneTitleFor(title);
          if (page.title != expected) {
            page
              ..title = expected
              ..updatedAt = DateTime.now();
            changed = true;
          }
        }
        if (changed) await storage.save(nb);
      }
    } catch (_) {
      // 回写失败不阻断；下次保存时收敛补齐。
    }
  }

  /// 打开指定块文档（反向链接条目点击路由）。
  ///
  /// N2：受独立文件密码保护的笔记先解锁（与画布/分页画布同口径——
  /// 验证成功 DEK 即入会话缓存，本会话免重复输入）。
  Future<void> _openBlockDocById(String id) async {
    final store = _services.blockDocStore;
    if (!await _ensureBlockDocUnlocked(store, id)) return;
    final doc = await _loadBlockDocGuarded(store, id);
    if (doc == null || !mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => DocPage(
          document: doc,
          controller: DocController(
            onSave: (d) => _services.blockDocStore.saveDocument(d),
          ),
          tagStore: _services.tagStore,
          allDocsLoader: _services.loadAllBlockDocs,
          onOpenDocById: _openBlockDocById,
          resetBlockDocPassword: BlockDocPasswordResetFlow.show,
        ),
      ),
    );
    _services.bumpDataVersion();
  }

  /// N2：笔记文件密码解锁拦截。返回 false = 用户取消且会话未解锁
  /// （不暴露内容）。解锁成功（含重置流）/ 未受密返回 true。
  Future<bool> _ensureBlockDocUnlocked(
    NoteBlockDocStore store,
    String id,
  ) async {
    if (!await store.isBlockDocPasswordProtected(id)) return true;
    if (store.isBlockDocUnlocked(id)) return true;
    if (!mounted) return false;
    final pin = await UnlockFlow.show(
      context,
      title:
          AppLocalizations.of(context)?.shellUnlockNoteTitle ?? '该笔记已加密，输入密码',
      flexible: true,
      onVerify: (p) => store.verifyBlockDocPassword(id, p),
      footerLabel: AppLocalizations.of(context)?.docForgotPassword ?? '忘记密码？',
      onFooter: () {
        BlockDocPasswordResetFlow.show(context, store: store, docId: id);
      },
    );
    // pin 非空 = 验证通过；null 但会话已解锁 = 刚被重置流解锁。
    return pin != null || store.isBlockDocUnlocked(id);
  }

  /// 聚合画布 / 笔记页 / 块文档三类文档为统一的「全部文档」查询结果，
  /// 并按 FavoriteStore 回填收藏状态。
  /// 打开回收站（M12.6）：软删除的打字笔记恢复/彻底删除。
  Future<void> _openTrash() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => TrashPage(
          loadTrash: _services.blockDocStore.listTrash,
          onRestore: (id) async {
            // P1-M1：恢复/彻底删除补门禁（白名单 note.restore / note.purge）。
            final restoreResult = const PolicyEngine().enforceCheck(
              'note.restore',
              target: id,
            );
            if (!restoreResult.isAllowed) return false;
            final ok = await _services.blockDocStore.restoreDocument(id);
            _services.bumpDataVersion();
            return ok;
          },
          onPurge: (id) async {
            final purgeResult = const PolicyEngine().enforceCheck(
              'note.purge',
              target: id,
            );
            if (!purgeResult.isAllowed) return false;
            final ok = await _services.blockDocStore.purgeFromTrash(id);
            _services.bumpDataVersion();
            return ok;
          },
        ),
      ),
    );
    _services.bumpDataVersion();
  }

  Future<AllDocQueryResult> _loadAllDocs() async {
    final docStorage = widget.docStorage;
    final nbStorage = widget.notebookStorage;
    if (docStorage == null && nbStorage == null) {
      return AllDocQueryResult(docs: const [], sections: const []);
    }
    final docs =
        await (docStorage?.listDocuments() ??
            Future.value(const <DocumentMeta>[]));
    final notebooks =
        await (nbStorage?.listAll() ?? Future.value(const <Notebook>[]));
    final blockHeaders = await _services.blockDocStore.listDocHeaders();
    final blockDocs = <BlockDocMeta>[
      for (final h in blockHeaders)
        BlockDocMeta(
          id: h.id,
          title: h.title,
          folder: '',
          tags: h.tags,
          createdAt: h.createdAt,
          updatedAt: h.updatedAt,
          locked: h.locked,
        ),
    ];
    final result = buildAllDocs(
      docs: docs,
      notebooks: notebooks,
      blockDocs: blockDocs,
      now: DateTime.now(),
    );
    // 回填收藏状态（M11：收藏夹真实化）。
    final favKeys = await _services.favoriteStore.loadKeys();
    if (favKeys.isEmpty) return result;
    AllDoc apply(AllDoc d) =>
        d.copyWith(isFavorite: favKeys.contains(d.dedupKey));
    return AllDocQueryResult(
      docs: result.docs.map(apply).toList(growable: false),
      sections: [
        for (final s in result.sections)
          AllDocSection(
            group: s.group,
            label: s.label,
            docs: s.docs.map(apply).toList(growable: false),
          ),
      ],
    );
  }

  /// 收藏切换：持久化（UI 乐观更新由 AllDocsPage 负责）。
  Future<void> _toggleFavorite(AllDoc doc) async {
    await _services.favoriteStore.toggleKey(doc.dedupKey);
  }

  /// 打开任意文档，按类型路由到对应编辑器。
  ///
  /// P2 修复（审计 2026-10）：此前在方法开头捕获 `Navigator.of(context)` 并
  /// 跨过解锁弹窗与多次加载才 push——widget 被 dispose 后仍用旧引用推页。
  /// 现与兄弟路径 [_openBlockDocById] 同款：await 之后先复查 `mounted`，
  /// 再从当前 context 现取 Navigator。解锁拦截顺序、路由参数、错误兜底
  /// 语义逐条不变（C-07 零行为变化承诺）。
  Future<void> _openAllDoc(AllDoc doc) async {
    switch (doc.kind) {
      case AllDocKind.canvas:
        final storage = widget.docStorage;
        if (storage == null) return;
        final id = doc.drawingId ?? doc.id;
        // 批次②：独立密码拦截——未解锁先输密码（与首页同口径，
        // 验证成功即入会话缓存，本会话免重复输入）。
        // N4 批 2：「忘记密码？」→ 重置密码盘重置流；重置成功后密码
        // 已入会话，pin 为 null 也继续尝试加载（仍锁定则 load 抛错返回）。
        if (await storage.isFilePasswordProtected(id)) {
          if (!mounted) return;
          final pin = await UnlockFlow.show(
            context,
            title:
                AppLocalizations.of(context)?.shellUnlockCanvasTitle ??
                '该画布已加密，输入独立密码',
            flexible: true,
            onVerify: (p) => storage.verifyFilePassword(id, p),
            footerLabel:
                AppLocalizations.of(context)?.docForgotPassword ?? '忘记密码？',
            onFooter: () {
              FilePasswordResetFlow.show(context, storage: storage, docId: id);
            },
          );
          if (pin == null && storage.filePasswordFor(id) == null) {
            return; // 用户取消且会话无密码——不暴露内容
          }
        }
        final DrawingDocument? drawing;
        try {
          drawing = await storage.load(id);
        } on VaultFilePasswordLockException {
          return; // 会话密码已被忘记（如切后台）——不暴露内容
        }
        if (drawing == null) return;
        if (!mounted) return;
        final builder = widget.editorPageBuilder;
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => builder != null
                ? builder(
                    document: drawing,
                    documentStorage: storage,
                    // C-06（审计 2026-09-27）：编辑器内嵌图片解密服务传线。
                    mediaCrypto: _services.mediaCrypto,
                  )
                : Scaffold(
                    body: Center(
                      child: Text(
                        AppLocalizations.of(context)?.shellEditorNotAssembled ??
                            '编辑器尚未由应用层装配',
                      ),
                    ),
                  ),
          ),
        );
        _services.bumpDataVersion();
      case AllDocKind.note:
        final nbStorage = widget.notebookStorage;
        if (nbStorage == null) return;
        final nbId = doc.notebookId ?? '';
        // 锁定守卫（占位行点击 / 保险库锁定竞态）：fail-closed 不暴露内容。
        final Notebook? loaded;
        try {
          loaded = await nbStorage.load(nbId);
        } on VaultFileLockException {
          return; // 保险库已锁定——请先重新验证开屏密码
        }
        if (loaded == null) return;
        Notebook nb = loaded;
        // N4 批 3：加密分页画布解锁拦截（M12 回归修复——重做首页时丢失
        // 解锁路径）+ 忘记密码重置入口。会话已有密码（本会话已解锁/重置）
        // 则跳过弹窗直接解密。占位条目（encryptedPayload 为 null——保险库
        // 锁定）不弹文件密码框：其锁定来自保险库而非文件密码。
        if (nb.encrypted &&
            nb.encryptedPayload != null &&
            nbStorage.notebookPasswordFor(nbId) == null) {
          if (!mounted) return;
          final pin = await UnlockFlow.show(
            context,
            title:
                AppLocalizations.of(context)?.shellUnlockNotebookTitle ??
                '该分页画布已加密，输入密码',
            flexible: true,
            onVerify: (p) => nbStorage.verifyNotebookPassword(nbId, p),
            footerLabel:
                AppLocalizations.of(context)?.docForgotPassword ?? '忘记密码？',
            onFooter: () {
              NotebookPasswordResetFlow.show(
                context,
                storage: nbStorage,
                notebookId: nbId,
                notebookTitle: nb.title,
              );
            },
          );
          if (pin == null && nbStorage.notebookPasswordFor(nbId) == null) {
            return; // 用户取消且会话无密码——不暴露内容
          }
        }
        // 会话密码解密页面内容（解锁/重置成功后必有；未加密为 null 跳过）。
        final sessionPw = nbStorage.notebookPasswordFor(nbId);
        if (sessionPw != null) {
          final fresh = await nbStorage.load(nbId);
          if (fresh == null) return;
          try {
            final ok = await nbStorage.decryptNotebook(fresh, sessionPw);
            if (!ok) return;
            nb = fresh;
            // H-03 媒体加密注入（与旧解锁路径同口径——页面图片解密用）。
            // C-06：媒体服务经 AppServices 组合根持有（不再直取全局单例）。
            final mediaSalt = await nbStorage.ensureMediaSalt();
            await _services.mediaCrypto.setSessionPassword(sessionPw, mediaSalt);
          } on FormatException {
            return; // 密码失效（缓存过期/重置竞态）——fail-closed
          }
        }
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => NotebookViewPage(
              notebook: nb,
              storage: nbStorage,
              blockDocStore: _services.blockDocStore,
              editorPageBuilder: widget.editorPageBuilder,
              // C-06（审计 2026-09-27）：媒体会话加密服务组合根传线。
              mediaCrypto: _services.mediaCrypto,
              sessionPassword: sessionPw,
            ),
          ),
        );
        _services.bumpDataVersion();
      case AllDocKind.blockdoc:
        final store = _services.blockDocStore;
        // N2：文件密码解锁拦截（未解锁先输密码；忘记密码 → 重置流）。
        if (!await _ensureBlockDocUnlocked(store, doc.id)) return;
        final bd = await _loadBlockDocGuarded(store, doc.id);
        if (bd == null) return;
        final favs = await _services.favoriteStore.loadKeys();
        if (!mounted) return;
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => DocPage(
              document: bd,
              controller: DocController(
                onSave: (d) async {
                  await _services.blockDocStore.saveDocument(d);
                  // 命名同源（2026-09-07）：块文档与分页画布页是同一逻辑
                  // 文件（doc.id == page.id），改名后回写源页并让克隆快照
                  // 跟随，使分页画布页卡/搜索等展示区即时一致。
                  await _syncBlockDocTitleToNotebookPage(d.id, d.title);
                },
              ),
              isFavorite: favs.contains(doc.id),
              onToggleFavorite: (fav) async => fav
                  ? _services.favoriteStore.addKey(doc.id)
                  : _services.favoriteStore.removeKey(doc.id),
              tagStore: _services.tagStore,
              allDocsLoader: _services.loadAllBlockDocs,
              onOpenDocById: _openBlockDocById,
              resetBlockDocPassword: BlockDocPasswordResetFlow.show,
            ),
          ),
        );
        _services.bumpDataVersion();
    }
  }

  /// 新建文档：按类型创建并打开。
  ///
  /// P2 修复（审计 2026-10）：与 [_openAllDoc] 同型——await 落盘之后才推页，
  /// 必须复查 mounted 并现取 Navigator（旧写法把跨 await 的引用留到最后）。
  /// 文档在 push 之前已保存成功，早退只影响「是否自动进入编辑器」，不影响数据。
  Future<void> _newAllDoc(AllDocKind kind) async {
    switch (kind) {
      case AllDocKind.canvas:
        final storage = widget.docStorage;
        if (storage == null) return;
        final draft = DrawingDocument(id: StorageService.newId(), title: '');
        await storage.save(draft);
        if (!mounted) return;
        final builder = widget.editorPageBuilder;
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => builder != null
                ? builder(
                    document: draft,
                    documentStorage: storage,
                    // C-06（审计 2026-09-27）：编辑器内嵌图片解密服务传线。
                    mediaCrypto: _services.mediaCrypto,
                  )
                : Scaffold(
                    body: Center(
                      child: Text(
                        AppLocalizations.of(context)?.shellEditorNotAssembled ??
                            '编辑器尚未由应用层装配',
                      ),
                    ),
                  ),
          ),
        );
        _services.bumpDataVersion();
      case AllDocKind.note:
        final nbStorage = widget.notebookStorage;
        if (nbStorage == null) return;
        final nb = Notebook(
          id: NotebookStorage.newId('notebook'),
          title: '',
        );
        await nbStorage.save(nb);
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => NotebookViewPage(
              notebook: nb,
              storage: nbStorage,
              blockDocStore: _services.blockDocStore,
              editorPageBuilder: widget.editorPageBuilder,
              // C-06（审计 2026-09-27）：媒体会话加密服务组合根传线。
              mediaCrypto: _services.mediaCrypto,
            ),
          ),
        );
        _services.bumpDataVersion();
      case AllDocKind.blockdoc:
        final bd = NoteBlockDoc.empty(NoteBlockDocStore.newId());
        await _services.blockDocStore.saveDocument(bd);
        if (!mounted) return;
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => DocPage(
              document: bd,
              controller: DocController(
                onSave: (d) async {
                  await _services.blockDocStore.saveDocument(d);
                  // 命名同源（2026-09-07）：块文档与分页画布页是同一逻辑
                  // 文件（doc.id == page.id），改名后回写源页并让克隆快照
                  // 跟随，使分页画布页卡/搜索等展示区即时一致。
                  await _syncBlockDocTitleToNotebookPage(d.id, d.title);
                },
              ),
              tagStore: _services.tagStore,
              allDocsLoader: _services.loadAllBlockDocs,
              onOpenDocById: _openBlockDocById,
              resetBlockDocPassword: BlockDocPasswordResetFlow.show,
            ),
          ),
        );
        _services.bumpDataVersion();
    }
  }
}
