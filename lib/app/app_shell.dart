import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_page.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/features/doc/presentation/trash_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_entity.dart';
import 'package:drawing_notes_app/features/schedule/presentation/schedule_page.dart';

/// 应用导航壳：3 个顶层目的地（M11 IA 收敛）。
///
/// 信息架构（对齐 AFFiNE 的「单一文档工作台入口」）：
///   0. 全部文档  —— 唯一列表入口（画布/笔记/块文档统一聚合）
///   1. 画板·笔记本 —— 绘画库（无限画布 + 笔记本 + 搜索/同步/密码盘入口）
///   2. 日历      —— 按月历浏览文档活动（按修改日期定位当天动过的文档）
///
/// M11 移除：纯笔记占位页（与块编辑器完全冗余）。
///
/// 响应式：宽屏（>= [_railBreakpoint]）用侧边栏 [NavigationRail]，
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
  });

  final NotebookStorage? notebookStorage;
  final StorageService? docStorage;
  final AppThemeController? themeController;
  final EditorPageBuilder? editorPageBuilder;
  final NoteBlockDocStore? blockDocStore;
  final FavoriteStore? favoriteStore;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 数据版本通知器：任何文档新增/修改（经 shell 路由的 push 返回后）自增，
  /// 驱动首页（HomePage）与全部文档（AllDocsPage）刷新列表。
  final ValueNotifier<int> _dataVersion = ValueNotifier(0);

  /// 宽屏断点：>=900 判定为桌面/平板，用侧边栏。
  static const double _railBreakpoint = 900;

  int _index = 0;

  /// 块文档存储（All Docs 聚合与打开块文档用）。可注入，否则用默认实现。
  late final NoteBlockDocStore _blockDocStore =
      widget.blockDocStore ?? NoteBlockDocStore();

  /// 收藏存储（All Docs 收藏夹持久化）。可注入，否则用默认实现。
  late final FavoriteStore _favoriteStore =
      widget.favoriteStore ?? FavoriteStore();

  /// 标签注册表（M12.6 标签系统）。
  final TagStore _tagStore = TagStore();

  /// 全量块文档缓存（P1-H4）：反向链接面板每次自动保存都会重算索引，
  /// 全库磁盘加载会造成卡顿——内存缓存，_dataVersion 自增时失效。
  List<NoteBlockDoc>? _blockDocsCache;

  /// 全量块文档读取（M12.7 反向链接索引数据源）。
  Future<List<NoteBlockDoc>> _loadAllBlockDocs() async {
    final cached = _blockDocsCache;
    if (cached != null) return cached;
    final ids = await _blockDocStore.listIds();
    final docs = <NoteBlockDoc>[];
    for (final id in ids) {
      final d = await _blockDocStore.loadDocument(id);
      if (d != null) docs.add(d);
    }
    _blockDocsCache = docs;
    return docs;
  }

  /// 数据版本自增 + 文档缓存失效（shell 内所有写盘后的统一出口）。
  void _bumpDataVersion() {
    _blockDocsCache = null;
    _bumpDataVersion();
  }

  /// 打开指定块文档（反向链接条目点击路由）。
  Future<void> _openBlockDocById(String id) async {
    final doc = await _blockDocStore.loadDocument(id);
    if (doc == null || !mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => DocPage(
          document: doc,
          controller: DocController(
            onSave: (d) => _blockDocStore.saveDocument(d),
          ),
          tagStore: _tagStore,
          allDocsLoader: _loadAllBlockDocs,
          onOpenDocById: _openBlockDocById,
        ),
      ),
    );
    _bumpDataVersion();
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
      loadTags: _tagStore.listTags,
    ),
    HomePage(
      notebookStorage: widget.notebookStorage,
      docStorage: widget.docStorage,
      themeController: widget.themeController,
      editorPageBuilder: widget.editorPageBuilder,
      refreshSignal: _dataVersion,
      // M12.4 统一数据源：首页笔记 Tab 与 All Docs 共用同一装配与打开路径。
      loadDocs: _loadAllDocs,
      onOpenDoc: _openAllDoc,
    ),
    // 2. 日历（M11.2：纯待办/日程——文档时间线并入主页，功能去重）
    const SchedulePage(),
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
        label: '画板·笔记本',
      ),
      NavigationDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_today),
        label: '日历',
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
        label: Text('画板·笔记本'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_today),
        label: Text('日历'),
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
          loadTrash: _blockDocStore.listTrash,
          onRestore: (id) async {
            // P1-M1：恢复/彻底删除补门禁（白名单 note.restore / note.purge）。
            final restoreResult = const PolicyEngine().enforceCheck(
              'note.restore',
              target: id,
            );
            if (!restoreResult.isAllowed) return false;
            final ok = await _blockDocStore.restoreDocument(id);
            _bumpDataVersion();
            return ok;
          },
          onPurge: (id) async {
            final purgeResult = const PolicyEngine().enforceCheck(
              'note.purge',
              target: id,
            );
            if (!purgeResult.isAllowed) return false;
            final ok = await _blockDocStore.purgeFromTrash(id);
            _bumpDataVersion();
            return ok;
          },
        ),
      ),
    );
    _bumpDataVersion();
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
    final blockHeaders = await _blockDocStore.listDocHeaders();
    final blockDocs = <BlockDocMeta>[
      for (final h in blockHeaders)
        BlockDocMeta(
          id: h.id,
          title: h.title,
          folder: '',
          tags: h.tags,
          createdAt: h.createdAt,
          updatedAt: h.updatedAt,
        ),
    ];
    final result = buildAllDocs(
      docs: docs,
      notebooks: notebooks,
      blockDocs: blockDocs,
      now: DateTime.now(),
    );
    // 回填收藏状态（M11：收藏夹真实化）。
    final favKeys = await _favoriteStore.loadKeys();
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
    await _favoriteStore.toggleKey(doc.dedupKey);
  }

  /// 打开任意文档，按类型路由到对应编辑器。
  Future<void> _openAllDoc(AllDoc doc) async {
    final nav = Navigator.of(context, rootNavigator: true);
    switch (doc.kind) {
      case AllDocKind.canvas:
        final storage = widget.docStorage;
        if (storage == null) return;
        final drawing = await storage.load(doc.drawingId ?? doc.id);
        if (drawing == null) return;
        final builder = widget.editorPageBuilder;
        nav.push(
          MaterialPageRoute(
            builder: (_) => builder != null
                ? builder(document: drawing, documentStorage: storage)
                : const Scaffold(body: Center(child: Text('编辑器尚未由应用层装配'))),
          ),
        );
        _bumpDataVersion();
      case AllDocKind.note:
        final nbStorage = widget.notebookStorage;
        if (nbStorage == null) return;
        final nb = await nbStorage.load(doc.notebookId ?? '');
        if (nb == null) return;
        nav.push(
          MaterialPageRoute(
            builder: (_) => NotebookViewPage(
              notebook: nb,
              storage: nbStorage,
              editorPageBuilder: widget.editorPageBuilder,
            ),
          ),
        );
        _bumpDataVersion();
      case AllDocKind.blockdoc:
        final bd = await _blockDocStore.loadDocument(doc.id);
        if (bd == null) return;
        final favs = await _favoriteStore.loadKeys();
        await nav.push(
          MaterialPageRoute(
            builder: (_) => DocPage(
              document: bd,
              controller: DocController(
                onSave: (d) => _blockDocStore.saveDocument(d),
              ),
              isFavorite: favs.contains(doc.id),
              onToggleFavorite: (fav) async => fav
                  ? _favoriteStore.addKey(doc.id)
                  : _favoriteStore.removeKey(doc.id),
              tagStore: _tagStore,
              allDocsLoader: _loadAllBlockDocs,
              onOpenDocById: _openBlockDocById,
            ),
          ),
        );
        _bumpDataVersion();
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
        _bumpDataVersion();
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
              editorPageBuilder: widget.editorPageBuilder,
            ),
          ),
        );
        _bumpDataVersion();
      case AllDocKind.blockdoc:
        final bd = NoteBlockDoc.empty(NoteBlockDocStore.newId());
        await _blockDocStore.saveDocument(bd);
        await nav.push(
          MaterialPageRoute(
            builder: (_) => DocPage(
              document: bd,
              controller: DocController(
                onSave: (d) => _blockDocStore.saveDocument(d),
              ),
              tagStore: _tagStore,
              allDocsLoader: _loadAllBlockDocs,
              onOpenDocById: _openBlockDocById,
            ),
          ),
        );
        _bumpDataVersion();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _railBreakpoint;
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
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _onSelect,
            destinations: _barDestinations(),
          ),
        );
      },
    );
  }
}
