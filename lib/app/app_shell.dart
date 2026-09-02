import 'package:drawing_notes_app/app/app_services.dart';
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/layout/responsive.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
// 批次②：AllDocs 打开画布的单文件密码拦截（与首页同口径）。
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart'
    show VaultFileLockException, VaultFilePasswordLockException;
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_page.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';
// 批次⑤：第四界面「设置」——密码体系集中管理。
import 'package:drawing_notes_app/features/notes/presentation/settings_page.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/features/doc/presentation/trash_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_entity.dart';
import 'package:drawing_notes_app/features/schedule/presentation/schedule_page.dart';
import 'package:drawing_notes_app/features/schedule/infrastructure/schedule_event_store.dart';
// 批次②：单文件密码输入（可变长度 4–12 位密码盘）。
import 'package:drawing_notes_app/fix/security_and_sync_fix.dart'
    show UnlockFlow;
// N4 批 2：画布解锁弹窗「忘记密码？」→ 重置密码盘重置流。
import 'package:drawing_notes_app/fix/file_password_reset_flow.dart';
// N4 批 3：分页画布解锁弹窗「忘记密码？」→ 重置密码盘重置流。
import 'package:drawing_notes_app/fix/notebook_password_reset_flow.dart';
import 'package:drawing_notes_app/fix/block_doc_password_reset_flow.dart';
// N4 批 3：加密分页画布解锁后媒体加密注入（页面图片解密用）。
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';

/// 应用导航壳：4 个顶层目的地（M11 IA 收敛 + 批次⑤设置集中）。
///
/// 信息架构（对齐 AFFiNE 的「单一文档工作台入口」）：
///   0. 全部文档  —— 唯一列表入口（画布/笔记/块文档统一聚合）
///   1. 画布·笔记 —— 绘画库（无限画布 + 分页画布 + 笔记）
///   2. 日历      —— 按月历浏览文档活动（按修改日期定位当天动过的文档）
///   3. 设置      —— 密码体系集中管理（批次⑤：应用锁/密码盘/单文件
///      密码三层关系 + 外观/WebDAV；HomePage 原散落入口一并收编）
///
/// M11 移除：纯笔记占位页（与块编辑器完全冗余）。
///
/// 响应式：宽屏（>= [kDesktopBreakpoint]）用侧边栏 [NavigationRail]，
///         窄屏用底部 [NavigationBar]。两端共享同一导航模型与状态。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.notebookStorage,
    this.docStorage,
    this.themeController,
    this.editorPageBuilder,
    this.blockDocStore,
    this.favoriteStore,
    this.tagStore,
    this.scheduleEventStore,
    this.appLockService,
    this.vaultKeyService,
  });

  final NotebookStorage? notebookStorage;
  final StorageService? docStorage;
  final AppThemeController? themeController;
  final EditorPageBuilder? editorPageBuilder;
  final NoteBlockDocStore? blockDocStore;
  final FavoriteStore? favoriteStore;

  /// 标签注册表（存储收口 2026-09-02：组合根创建，透传给 AppServices）。
  final TagStore? tagStore;

  /// 日程存储（存储收口 2026-09-02：组合根创建，透传给日历页）。
  final ScheduleEventStore? scheduleEventStore;

  /// 应用启动锁服务（组合根注入，透传给 HomePage 设置入口）。
  final AppLockService? appLockService;

  /// 主密钥保险库（批次①b，组合根注入）：透传给 HomePage → 应用锁设置页。
  final VaultKeyService? vaultKeyService;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 应用级服务门面（R2-Q2）：store 实例/数据版本/全量加载缓存。
  late final AppServices _services = AppServices(
    blockDocStore: widget.blockDocStore,
    favoriteStore: widget.favoriteStore,
    tagStore: widget.tagStore,
    scheduleEventStore: widget.scheduleEventStore,
  );

  @override
  void initState() {
    super.initState();
    // 首页刷新修复①（2026-09-01）：写路径统一通知下沉到存储层——三个存储
    // 的写成功回调都汇入 bumpDataVersion，覆盖笔记本内新建/画布自动保存/
    // DocPage 保存等所有路径，不再依赖调用点逐一通知（根因即内部写路径
    // 绕过了 shell 的 bump 调用点，首页收不到通知）。
    widget.notebookStorage?.onWrite = _services.bumpDataVersion;
    widget.docStorage?.onWrite = _services.bumpDataVersion;
    _services.blockDocStore.onWrite = _services.bumpDataVersion;
  }

  int _index = 0;

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
        ),
      ),
    );
    _services.bumpDataVersion();
  }

  /// N2：笔记文件密码解锁拦截。返回 false = 用户取消且会话未解锁
  /// （不暴露内容）。解锁成功（含重置流）/ 未受密返回 true。
  Future<bool> _ensureBlockDocUnlocked(NoteBlockDocStore store, String id) async {
    if (!await store.isBlockDocPasswordProtected(id)) return true;
    if (store.isBlockDocUnlocked(id)) return true;
    if (!mounted) return false;
    final pin = await UnlockFlow.show(
      context,
      title: '该笔记已加密，输入密码',
      flexible: true,
      onVerify: (p) => store.verifyBlockDocPassword(id, p),
      footerLabel: '忘记密码？',
      onFooter: () {
        BlockDocPasswordResetFlow.show(context, store: store, docId: id);
      },
    );
    // pin 非空 = 验证通过；null 但会话已解锁 = 刚被重置流解锁。
    return pin != null || store.isBlockDocUnlocked(id);
  }

  /// 3 个目的地。用 [IndexedStack] 承载，保持各自状态（切走再切回不丢）。
  late final List<Widget> _destinations = [
    // 0. 全部文档（AFFiNE 风格主工作台）
    AllDocsPage(
      loadDocs: _loadAllDocs,
      onOpenDoc: _openAllDoc,
      onNewDoc: _newAllDoc,
      onToggleFavorite: _toggleFavorite,
      onOpenTrash: _openTrash,
      loadTags: _services.tagStore.listTags,
      // 首页/AllDocs 同步修复（2026-09-02）：v1.4.11 装配时漏传信号线，
      // 导致 IndexedStack 保活下 AllDocs 永远停在首次快照——补接同一
      // dataVersion 信号源，与 HomePage 对称。
      refreshSignal: _services.dataVersion,
    ),
    HomePage(
      notebookStorage: widget.notebookStorage,
      docStorage: widget.docStorage,
      editorPageBuilder: widget.editorPageBuilder,
      refreshSignal: _services.dataVersion,
      // R2 列表同步：注入同一 store 实例 + 写后通知（新建/删除驱动 AllDocs 刷新）。
      blockDocStore: _services.blockDocStore,
      onDataChanged: _services.bumpDataVersion,
      // M12.4 统一数据源：首页笔记 Tab 与 All Docs 共用同一装配与打开路径。
      loadDocs: _loadAllDocs,
      onOpenDoc: _openAllDoc,
    ),
    // 2. 日历（M11.2：纯待办/日程——文档时间线并入主页，功能去重）
    SchedulePage(eventStore: _services.scheduleEventStore),
    // 3. 设置（批次⑤：密码体系集中管理——HomePage 原入口收编至此）
    SettingsPage(
      appLockService: widget.appLockService,
      vaultKeyService: widget.vaultKeyService,
      themeController: widget.themeController,
    ),
  ];

  /// 底部导航栏（窄屏）目的地：[NavigationBar] 的 [NavigationDestination]。
  List<NavigationDestination> _barDestinations() {
    return const [
      NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: '全部文档',
      ),
      NavigationDestination(
        icon: Icon(Icons.brush_outlined),
        selectedIcon: Icon(Icons.brush),
        label: '画布·笔记',
      ),
      NavigationDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_today),
        label: '日历',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '设置',
      ),
    ];
  }

  /// 侧边栏（宽屏）目的地：[NavigationRail] 的 [NavigationRailDestination]。
  List<NavigationRailDestination> _railDestinations() {
    return const [
      NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('全部文档'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.brush_outlined),
        selectedIcon: Icon(Icons.brush),
        label: Text('画布·笔记'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_today),
        label: Text('日历'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('设置'),
      ),
    ];
  }

  void _onSelect(int index) => setState(() => _index = index);

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
  Future<void> _openAllDoc(AllDoc doc) async {
    final nav = Navigator.of(context, rootNavigator: true);
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
            title: '该画布已加密，输入独立密码',
            flexible: true,
            onVerify: (p) => storage.verifyFilePassword(id, p),
            footerLabel: '忘记密码？',
            onFooter: () {
              FilePasswordResetFlow.show(context, storage: storage, docId: id);
            },
          );
          if (pin == null &&
              storage.filePasswordFor(id) == null) {
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
        final builder = widget.editorPageBuilder;
        nav.push(
          MaterialPageRoute(
            builder: (_) => builder != null
                ? builder(document: drawing, documentStorage: storage)
                : const Scaffold(body: Center(child: Text('编辑器尚未由应用层装配'))),
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
            title: '该分页画布已加密，输入密码',
            flexible: true,
            onVerify: (p) => nbStorage.verifyNotebookPassword(nbId, p),
            footerLabel: '忘记密码？',
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
            final mediaSalt = await nbStorage.ensureMediaSalt();
            await MediaCryptoService.instance.setSessionPassword(
              sessionPw,
              mediaSalt,
            );
          } on FormatException {
            return; // 密码失效（缓存过期/重置竞态）——fail-closed
          }
        }
        nav.push(
          MaterialPageRoute(
            builder: (_) => NotebookViewPage(
              notebook: nb,
              storage: nbStorage,
              blockDocStore: _services.blockDocStore,
              editorPageBuilder: widget.editorPageBuilder,
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
        await nav.push(
          MaterialPageRoute(
            builder: (_) => DocPage(
              document: bd,
              controller: DocController(
                onSave: (d) => _services.blockDocStore.saveDocument(d),
              ),
              isFavorite: favs.contains(doc.id),
              onToggleFavorite: (fav) async => fav
                  ? _services.favoriteStore.addKey(doc.id)
                  : _services.favoriteStore.removeKey(doc.id),
              tagStore: _services.tagStore,
              allDocsLoader: _services.loadAllBlockDocs,
              onOpenDocById: _openBlockDocById,
            ),
          ),
        );
        _services.bumpDataVersion();
    }
  }

  /// 新建文档：按类型创建并打开。
  Future<void> _newAllDoc(AllDocKind kind) async {
    final nav = Navigator.of(context, rootNavigator: true);
    switch (kind) {
      case AllDocKind.canvas:
        final storage = widget.docStorage;
        if (storage == null) return;
        final draft = DrawingDocument(id: StorageService.newId(), title: '未命名');
        await storage.save(draft);
        final builder = widget.editorPageBuilder;
        nav.push(
          MaterialPageRoute(
            builder: (_) => builder != null
                ? builder(document: draft, documentStorage: storage)
                : const Scaffold(body: Center(child: Text('编辑器尚未由应用层装配'))),
          ),
        );
        _services.bumpDataVersion();
      case AllDocKind.note:
        final nbStorage = widget.notebookStorage;
        if (nbStorage == null) return;
        final nb = Notebook(
          id: NotebookStorage.newId('notebook'),
          title: '未命名',
        );
        await nbStorage.save(nb);
        nav.push(
          MaterialPageRoute(
            builder: (_) => NotebookViewPage(
              notebook: nb,
              storage: nbStorage,
              blockDocStore: _services.blockDocStore,
              editorPageBuilder: widget.editorPageBuilder,
            ),
          ),
        );
        _services.bumpDataVersion();
      case AllDocKind.blockdoc:
        final bd = NoteBlockDoc.empty(NoteBlockDocStore.newId());
        await _services.blockDocStore.saveDocument(bd);
        await nav.push(
          MaterialPageRoute(
            builder: (_) => DocPage(
              document: bd,
              controller: DocController(
                onSave: (d) => _services.blockDocStore.saveDocument(d),
              ),
              tagStore: _services.tagStore,
              allDocsLoader: _services.loadAllBlockDocs,
              onOpenDocById: _openBlockDocById,
            ),
          ),
        );
        _services.bumpDataVersion();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = isDesktopWidth(constraints.maxWidth);
        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _onSelect,
                  labelType: NavigationRailLabelType.all,
                  destinations: _railDestinations(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: IndexedStack(index: _index, children: _destinations),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          body: IndexedStack(index: _index, children: _destinations),
          // AFFiNE mobile 语义：输入法弹出时隐藏底部导航（VirtualKeyboard
          // Service 同款体验），给内容与键盘让出完整空间。
          bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _onSelect,
                  destinations: _barDestinations(),
                ),
        );
      },
    );
  }
}
