import 'package:drawing_notes_app/core/utils/domain_display_labels.dart';
import 'package:drawing_notes_app/core/security/vault_error_messages.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/theme/apple_motion.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
// 批次②：单文件密码需与开屏密码比对（matchesAppLockPin 静态探测）。
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/shared/application/search_service.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
// 批次②：单文件密码——移除密码需回封 v1 主密钥信封，锁定时 fail-closed。
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart'
    show VaultFileException, VaultFileLockException;
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/onboarding.dart';
// N1 命名统一：画布 tab FAB 弹两选项（新建无限画布/新建分页画布）——
// 分页画布新建入口恢复（M12 曾移除「新建笔记本」入口）。
import 'package:drawing_notes_app/features/notes/domain/notebook_entity.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/shared/widgets/apple_empty_state.dart';
import 'package:drawing_notes_app/shared/widgets/ambient_background.dart';
import 'package:drawing_notes_app/shared/widgets/glass_app_bar.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
// v1.10.5：导航类控件玻璃化——FAB 换液态玻璃胶囊。
import 'package:drawing_notes_app/shared/widgets/glass_fab.dart';
// U4a：首屏加载骨架屏。
import 'package:drawing_notes_app/shared/widgets/skeleton.dart';
import 'package:drawing_notes_app/shared/utils/image_decode_cap.dart';
import 'package:drawing_notes_app/shared/utils/time_format.dart';
import 'package:drawing_notes_app/shared/widgets/app_snack.dart';
import 'package:drawing_notes_app/features/doc/application/doc_templates.dart';
import 'package:drawing_notes_app/features/doc/application/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/presentation/doc_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/search_page.dart';
// 首页刷新修复②（2026-09-01）：RouteAware 可见性兜底——从编辑器/笔记本页
// 返回时自动刷新，覆盖所有遗漏的写路径（IndexedStack 保活下 initState 不再执行）。
// 审计 2026-09-26 #43：原 features/security/sync_fix.dart 归位 core/navigation。
import 'package:drawing_notes_app/core/navigation/app_refresh.dart'
    show AppRefresh, AppRefreshRouteAware;
import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart'
    show UnlockFlow;
// N4 批 2：忘记密码重置流 + 设密时插盘绑定重置密码盘。
import 'package:drawing_notes_app/features/security/presentation/file_password_reset_flow.dart';
// N2：笔记（块文档）文件密码——解锁拦截与忘记密码重置流。
import 'package:drawing_notes_app/features/security/presentation/block_doc_password_reset_flow.dart';
import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';

part 'home_page_widgets.dart';
part 'home_page_tabs.dart';
part 'home_page_password.dart';
// 审计 2026-09-26 #37：创建流/回收站自宿主拆出（行为零变化）。
// 注：_refresh 留在宿主——extension 成员不可调用 setState（protected）。
part 'home_page_create.dart';
part 'home_page_trash.dart';

/// 顶栏下方分段控件的插槽高度。
///
/// 与 [GlassAppBar.bottom] 的 `preferredSize` 以及 body 顶部让位高度共用，
/// 收成常量避免三处手算不一致。
const double _kTabSlotHeight = 56;

/// 首页：画布（无限画布 / 分页画布）/ 笔记 两分栏列表管理。
///
/// 三个主工作区（W1 归位 2026-09-02）：
/// - 画布 tab：「无限画布」（独立图形、关系图和自由绘制）与
///   「分页画布」（多页装订画册，旧「笔记本」——**整本粒度**展示，
///   不再以页粒度混入笔记 tab）；
/// - 笔记 tab：「笔记」（直接打字的块文档）。
///
/// 能力：
/// - 新建画布（弹两选项：新建无限画布 / 新建分页画布）/ 新建笔记
/// - 打开、删除（二次确认）
/// - 展示缩略图
///
/// 数据来源：本地文件存储（[StorageService] / [NotebookStorage]），无网络请求。
class HomePage extends StatefulWidget {
  const HomePage({
    required this.blockDocAccessor,
    this.refreshSignal,
    super.key,
    this.notebookStorage,
    this.docStorage,
    this.editorPageBuilder,
    this.loadDocs,
    this.loadNotebooks,
    this.onOpenDoc,
    this.blockDocStore,
    this.onDataChanged,
  });

  final NotebookStorage? notebookStorage;
  final StorageService? docStorage;

  /// 编辑器页面由应用组合根注入，notes 模块不直接依赖 drawing 的 UI。
  final EditorPageBuilder? editorPageBuilder;

  /// 块文档全文搜索访问器（审计 2026-09-26 #17）：由应用组合根注入
  /// doc 侧实现——本页只依赖 core 契约，不再直接实例化另一 feature
  /// 的 infrastructure 类型。
  final IBlockDocSearchAccessor blockDocAccessor;

  /// 数据版本通知（shell 在文档新增/修改后自增）：触发首页刷新。
  final ValueListenable<int>? refreshSignal;

  /// 统一数据源（M12.4）：与 All Docs 共用同一装配 loader（buildAllDocs 三源）。
  /// 笔记 Tab 数据 = 装配结果中 kind==blockdoc 的条目——
  /// 从根本上保证两处列表一致（用户反馈的"页面列表不同步"根因即双源分裂）。
  final Future<AllDocQueryResult> Function()? loadDocs;

  /// 分页画布整本 loader（W1 归位）：与 loadDocs 同注入先例——
  /// 生产由 shell 注入 notebookStorage.listAll，测试注入假源保 FakeAsync 安全。
  final Future<List<Notebook>> Function()? loadNotebooks;

  /// 块文档存储（R2 列表同步修复）：注入 shell 同一实例——
  /// 自建实例会导致 AllDocs 侧 listDocHeaders 缓存不失效（新笔记不显示）。
  final NoteBlockDocStore? blockDocStore;

  /// 数据变更通知（新建/删除/重命名后调用，驱动 AllDocs 刷新）。
  final VoidCallback? onDataChanged;

  /// 统一打开路径：与 All Docs 同一回调（note→NotebookViewPage，
  /// blockdoc→DocPage），保证两处点击行为一致。
  final void Function(AllDoc doc)? onOpenDoc;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AppRefreshRouteAware {
  late final NotebookStorage _nbStorage;
  late final StorageService _docStorage;
  late final NoteBlockDocStore _blockDocStore;

  List<AllDoc> _notes = [];
  List<DocumentMeta> _documents = [];

  /// 分页画布（整本粒度，W1 归位）：画布 tab 展示，按 updatedAt desc。
  /// 含保险库锁定占位（isLockedPlaceholder）与文件密码受密未解锁条目。
  List<Notebook> _notebooks = [];
  bool _loading = true;
  String? _error;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_onDataVersionChanged);
    _nbStorage = widget.notebookStorage ?? NotebookStorage();
    _docStorage = widget.docStorage ?? StorageService();
    _blockDocStore = widget.blockDocStore ?? NoteBlockDocStore();
    _refresh();
    // 首次启动引导（Phase 7）：仅第一次打开时显示，可跳过。
    _showOnboarding();
  }

  void _onDataVersionChanged() {
    if (mounted) _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首页刷新修复②：订阅路由可见性——从笔记本页/编辑器 didPopNext 时刷新。
    AppRefresh.routeObserver.subscribe(
      this,
      ModalRoute.of(context)! as PageRoute,
    );
  }

  @override
  void onPageVisibleAgain() {
    if (mounted) _refresh();
  }

  @override
  void dispose() {
    AppRefresh.routeObserver.unsubscribe(this);
    widget.refreshSignal?.removeListener(_onDataVersionChanged);
    super.dispose();
  }

  Future<void> _showOnboarding() async {
    try {
      await OnboardingService().showIfFirstLaunch(context);
    } catch (_) {
      // 引导展示失败不影响正常使用。
    }
  }

  // 刷新与三源装配（_refresh）：留宿主——extension 不可调 setState（protected）。
  // 创建流与编辑器导航（画布/分页画布/笔记新建、画布打开与解锁）：见 part home_page_create.dart。
  // 回收站对话框（恢复/永久删除/清空）：见 part home_page_trash.dart。

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await _docStorage.listDocuments();
      // W1 归位（2026-09-02）：分页画布整本列表——画布 tab 展示。
      final List<Notebook> notebooks;
      if (widget.loadNotebooks != null) {
        notebooks = await widget.loadNotebooks!();
      } else {
        notebooks = await _nbStorage.listAll();
      }
      // 拷贝后排序：loader 可能返回 const/不可变列表。
      final sortedNotebooks = notebooks.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      // 统一数据源（M12.4）：与 All Docs 同一装配；W1 起笔记 tab 只收
      // blockdoc（分页画布整本已归位画布 tab，页粒度条目不再混入）。
      List<AllDoc> notes;
      final loader = widget.loadDocs;
      if (loader != null) {
        final result = await loader();
        notes = result.docs
            .where((d) => d.kind == AllDocKind.blockdoc)
            .toList(growable: false);
      } else {
        final noteIds = await _blockDocStore.listIds();
        notes = <AllDoc>[];
        for (final id in noteIds) {
          // N2：受密未解锁的笔记跳过（fail-closed；正式装配走 loadDocs
          // ——listDocHeaders 已给锁定占位）。
          final NoteBlockDoc? d;
          try {
            d = await _blockDocStore.loadDocument(id);
          } on BlockDocLockedException {
            continue;
          }
          if (d != null) {
            notes.add(
              AllDoc(
                id: d.id,
                title: d.title,
                kind: AllDocKind.blockdoc,
                folder: '',
                createdAt: d.createdAt,
                updatedAt: d.updatedAt,
              ),
            );
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _notebooks = sortedNotebooks;
        _notes = notes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _l10nSafe?.homeReadListFailed ?? '读取列表失败，请重试';
        _loading = false;
      });
    }
  }

  AppLocalizations? get _l10nSafe =>
      mounted ? AppLocalizations.of(context) : null; // mounted 守卫跨 async

  void _showSnack(String message) {
    if (!mounted) return;
    AppSnack.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // 画布（无限画布/分页画布）/ 笔记（M11：「最近」时间线并入日历页）
      child: Scaffold(
        // 让内容延伸到顶栏之后——玻璃才有东西可模糊（否则背后是纯色，
        // BackdropFilter 采不到内容，观感退化成半透明色板）。
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: Text(_l10nSafe?.appTitle ?? '绘图笔记'),
          actions: [
            IconButton(
              tooltip: _l10nSafe?.search ?? '搜索',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchPage(
                    searchService: SearchService(
                      notebookAccessor: _nbStorage,
                      docStorage: _docStorage,
                      blockDocAccessor: widget.blockDocAccessor,
                    ),
                    notebookStorage: _nbStorage,
                    documentStorage: _docStorage,
                    editorPageBuilder: widget.editorPageBuilder,
                    blockDocStore: _blockDocStore,
                  ),
                ),
              ),
            ),
            // M-06 回收站入口（专家审计 2026-08-15）：查看/恢复/永久删除
            // 已删除文档（UX Patterns 官方模式——专用回收站界面）。
            IconButton(
              tooltip: _l10nSafe?.trash ?? '回收站（30 天内可恢复）',
              icon: const Icon(Icons.delete_outline),
              onPressed: _showTrashDialog,
            ),
            // 批次⑤：WebDAV/外观/应用锁/密码盘入口已收编至第四界面「设置」，
            // 顶栏只保留搜索与回收站两个文档操作。
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(_kTabSlotHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              // 红线：顶栏已是玻璃层，分段控件**不得再套 GlassSurface**
              // （玻璃叠玻璃，DESIGN_SYSTEM.md:218）。分段控件直接浮在玻璃上，
              // 这也是 Apple 的做法——控件本身不是一层新材质。
              child: TabBar(
                onTap: (i) => setState(() => _tabIndex = i),
                tabs: [
                  Tab(text: _l10nSafe?.homeTabCanvas ?? '画布'),
                  Tab(text: _l10nSafe?.homeTabNotes ?? '笔记'),
                ],
              ),
            ),
          ),
        ),
        body: AmbientBackground(
          child: Padding(
            padding: EdgeInsets.only(
              top: GlassAppBar.bodyTopPadding(
                context,
                bottomHeight: _kTabSlotHeight,
              ),
              // v1.10.5：extendBody 让位——app_shell 玻璃导航条把总高注入
              // MediaQuery.padding.bottom，网格视口收窄到胶囊条上缘；
              // AmbientBackground 仍延伸到条后供玻璃模糊（不退化成脏板）。
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            child: _buildBody(),
          ),
        ),
        floatingActionButton: _tabIndex == 0
            ? GlassFab.extended(
                onPressed: _createCanvas,
                icon: const Icon(Icons.add),
                label: Text(_l10nSafe?.docsNewCanvas ?? '新建画布'),
              )
            : GlassFab.extended(
                onPressed: _createNote,
                icon: const Icon(Icons.add),
                label: Text(_l10nSafe?.docsNewNote ?? '新建笔记'),
              ),
      ),
    );
  }
}
