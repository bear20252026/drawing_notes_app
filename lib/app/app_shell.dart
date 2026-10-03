import 'package:drawing_notes_app/app/app_services.dart';
import 'package:drawing_notes_app/app/composition_root.dart';
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/layout/responsive.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/quick_unlock_service.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';

import 'package:drawing_notes_app/shared/widgets/glass_navigation_rail.dart';
// 批次②：AllDocs 打开画布的单文件密码拦截（与首页同口径）。
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart'
    show VaultFileLockException, VaultFilePasswordLockException;
import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/theme/app_locale_controller.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/core/all_doc_query.dart';
import 'package:drawing_notes_app/core/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_page.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_title_sync.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';
// 审计 2026-09-26 #17：块文档搜索访问器由组合根装配——home_page 只依赖
// core 契约，不再直接实例化 doc 侧的 infrastructure 实现。
import 'package:drawing_notes_app/features/doc/infrastructure/block_doc_search_accessor_impl.dart';
// 批次⑤：第四界面「设置」——密码体系集中管理。
import 'package:drawing_notes_app/features/notes/presentation/settings_page.dart';
import 'package:drawing_notes_app/features/doc/application/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/presentation/doc_page.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/features/doc/presentation/trash_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_entity.dart';
// 批次②：单文件密码输入（可变长度 4–12 位密码盘）。
import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart'
    show UnlockFlow;
// v1.10.5：导航类控件玻璃化——底部导航条换液态玻璃胶囊。
import 'package:drawing_notes_app/shared/widgets/glass_nav_bar.dart';
// N4 批 2：画布解锁弹窗「忘记密码？」→ 重置密码盘重置流。
import 'package:drawing_notes_app/features/security/presentation/file_password_reset_flow.dart';
// N4 批 3：分页画布解锁弹窗「忘记密码？」→ 重置密码盘重置流。
import 'package:drawing_notes_app/features/security/presentation/notebook_password_reset_flow.dart';
import 'package:drawing_notes_app/features/security/presentation/block_doc_password_reset_flow.dart';
// C-06（审计 2026-09-27）：媒体会话加密服务由组合根 AppServices 持有，
// shell 自身经 _services.mediaCrypto 使用，不再 import 全局单例。
import 'package:drawing_notes_app/l10n/app_localizations.dart';

// C-07（审计 2026-09-27）：app_shell 三职责拆分——路由装配域（open* 方法
// 群、全量文档查询、密码解锁拦截、命名同源回写）拆入下方 part，本主文件
// 只留导航 UI 与服务消费（同 doc_page 六 part 库内拆分先例）。
part 'app_shell_routes.dart';

/// 应用导航壳：3 个顶层目的地（M11 IA 收敛 + 批次⑤设置集中）。
///
/// 信息架构（对齐 AFFiNE 的「单一文档工作台入口」）：
///   0. 全部文档  —— 唯一列表入口（画布/笔记/块文档统一聚合）
///   1. 画布·笔记 —— 绘画库（无限画布 + 分页画布 + 笔记）
///   2. 设置      —— 密码体系集中管理（批次⑤：应用锁/密码盘/单文件
///      密码三层关系 + 外观/WebDAV；HomePage 原散落入口一并收编）
///
/// M11 移除：纯笔记占位页（与块编辑器完全冗余）、日历页（M11 第二阶段
/// 2026-09-23：文档时间分组已并入首页/AllDocs，日程事件与月历页裁撤）。
///
/// 响应式：宽屏（>= [kDesktopBreakpoint]）用侧边栏 [NavigationRail]，
///         窄屏用底部 [NavigationBar]。两端共享同一导航模型与状态。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.notebookStorage,
    this.docStorage,
    this.themeController,
    this.localeController,
    this.appDataRoot,
    this.editorPageBuilder,
    this.blockDocStore,
    this.favoriteStore,
    this.tagStore,
    this.appLockService,
    this.vaultKeyService,
    this.quickUnlockService,
  });

  final NotebookStorage? notebookStorage;
  final StorageService? docStorage;
  final AppThemeController? themeController;

  /// 应用内语言覆盖（2026-09-27；null 时设置页隐藏语言入口）。
  final AppLocaleController? localeController;

  /// 统一数据根（批次 M：备份/恢复入口；null 时设置页隐藏两行）。
  final AppDataRoot? appDataRoot;
  final EditorPageBuilder? editorPageBuilder;
  final NoteBlockDocStore? blockDocStore;
  final FavoriteStore? favoriteStore;

  /// 标签注册表（存储收口 2026-09-02：组合根创建，透传给 AppServices）。
  final TagStore? tagStore;

  /// 应用启动锁服务（组合根注入，透传给 HomePage 设置入口）。
  final AppLockService? appLockService;

  /// 主密钥保险库（批次①b，组合根注入）：透传给 HomePage → 应用锁设置页。
  final VaultKeyService? vaultKeyService;

  /// 系统验证快速解锁（批D1，组合根注入）：透传给设置页。
  final QuickUnlockService? quickUnlockService;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 应用级服务门面（R2-Q2）：store 实例/数据版本/全量加载缓存。
  /// C-07（审计 2026-09-27）：缺省装配经组合根 createAppServices——
  /// 服务单例装配唯一落点（composition_root.dart），本壳只消费与透传注入。
  late final AppServices _services = CompositionRoot.createAppServices(
    blockDocStore: widget.blockDocStore,
    favoriteStore: widget.favoriteStore,
    tagStore: widget.tagStore,
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

  /// 已实际创建的标签页（Lazy IndexedStack，2026-09-06 内存审计）：
  /// 未访问过的页面不进入元素树（不构建、不保活）；首次访问后与
  /// IndexedStack 同样保活（切走再切回不丢状态）。
  final Set<int> _visited = {0};

  void _onSelect(int index) {
    setState(() {
      _index = index;
      _visited.add(index);
    });
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
      // C-06（审计 2026-09-27）：媒体会话加密服务组合根传线。
      mediaCrypto: _services.mediaCrypto,
      refreshSignal: _services.dataVersion,
      // 审计 2026-09-26 #17：搜索访问器由组合根注入（同一 store 实例，
      // 与 home_page 自建 Impl 的旧行为等价）。
      blockDocAccessor: BlockDocSearchAccessorImpl(
        store: _services.blockDocStore,
      ),
      // R2 列表同步：注入同一 store 实例 + 写后通知（新建/删除驱动 AllDocs 刷新）。
      blockDocStore: _services.blockDocStore,
      onDataChanged: _services.bumpDataVersion,
      // M12.4 统一数据源：首页笔记 Tab 与 All Docs 共用同一装配与打开路径。
      loadDocs: _loadAllDocs,
      // W1 归位（2026-09-02）：分页画布整本 loader——画布 tab 展示。
      loadNotebooks: () async {
        final storage = widget.notebookStorage;
        return storage == null ? const <Notebook>[] : storage.listAll();
      },
      onOpenDoc: _openAllDoc,
    ),
    // 2. 设置（批次⑤：密码体系集中管理——HomePage 原入口收编至此）
    SettingsPage(
      appLockService: widget.appLockService,
      vaultKeyService: widget.vaultKeyService,
      quickUnlockService: widget.quickUnlockService,
      themeController: widget.themeController,
      localeController: widget.localeController,
      appDataRoot: widget.appDataRoot,
      // C-05（审计 2026-09-27）：WebDAV 同步装配收口 application 层，
      // 经组合根注入设置页，页面不再自行 new 基础设施。
      syncController: _services.syncController,
    ),
  ];

  /// 底部导航栏（窄屏）目的地：[NavigationBar] 的 [NavigationDestination]。
  List<NavigationDestination> _barDestinations() {
    final l10n = AppLocalizations.of(context);
    return [
      NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: l10n?.shellAllDocs ?? '全部文档',
      ),
      NavigationDestination(
        icon: Icon(Icons.brush_outlined),
        selectedIcon: Icon(Icons.brush),
        label: l10n?.shellCanvasNotes ?? '画布·笔记',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: l10n?.shellSettings ?? '设置',
      ),
    ];
  }

  /// 侧边栏（宽屏）目的地：[NavigationRail] 的 [NavigationRailDestination]。
  List<NavigationRailDestination> _railDestinations() {
    final l10n = AppLocalizations.of(context);
    return [
      NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text(l10n?.shellAllDocs ?? '全部文档'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.brush_outlined),
        selectedIcon: Icon(Icons.brush),
        label: Text(l10n?.shellCanvasNotes ?? '画布·笔记'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text(l10n?.shellSettings ?? '设置'),
      ),
    ];
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
                // v1.17.20：宽屏侧栏玻璃化（导航域玻璃化收尾项）——
                // 与窄屏 GlassNavigationBar 同配方家族，M3 indicator 保留。
                GlassNavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _onSelect,
                  destinations: _railDestinations(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  // Lazy IndexedStack：只实例化访问过的标签页（未访问的
                  // 用零尺寸占位，不构建不保活）；已访问页面保持既有
                  // IndexedStack 语义（切走再切回不丢状态）。
                  child: IndexedStack(
                    index: _index,
                    children: [
                      for (var i = 0; i < _destinations.length; i++)
                        _visited.contains(i)
                            ? _destinations[i]
                            : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          // v1.10.5：内容延伸到玻璃导航条之后——玻璃才有东西可模糊
          // （与 settings_page 顶栏注释同一原则）。各页面按可滚动让位
          // 消费 MediaQuery.padding.bottom，见各页接入注释。
          extendBody: true,
          body: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _destinations.length; i++)
                _visited.contains(i)
                    ? _destinations[i]
                    : const SizedBox.shrink(),
            ],
          ),
          // AFFiNE mobile 语义：输入法弹出时隐藏底部导航（VirtualKeyboard
          // Service 同款体验），给内容与键盘让出完整空间。
          bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
              ? null
              : GlassNavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _onSelect,
                  destinations: _barDestinations(),
                ),
        );
      },
    );
  }
}
