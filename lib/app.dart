import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:drawing_notes_app/app/default_editor_page_builder.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_contrast.dart';
import 'package:drawing_notes_app/core/di/providers.dart';
import 'package:drawing_notes_app/core/theme/app_locale_controller.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'l10n/app_localizations.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/app/app_shell.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
// 首页刷新修复②：注册全局路由观察者（HomePage 的 RouteAware 兜底刷新依赖它）。
// 审计 2026-09-26 #43：原 features/security/sync_fix.dart 归位 core/navigation。
import 'package:drawing_notes_app/core/navigation/app_refresh.dart'
    show AppRefresh;
// 应用启动锁：冷启动 + 切后台回锁（2026-09-01）。
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/app_lock_gate.dart';
import 'package:drawing_notes_app/core/security/quick_unlock_service.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';

/// 应用根组件：主题 + 路由。
///
/// 设计说明：
/// - 深色/浅色主题均支持，用户可手动切换（跟随系统/浅色/深色，Phase 7）；
/// - 主题模式由 [AppThemeController] 统一管理并持久化；
/// - 路由集中管理，新增页面时在此注册；
/// - 应用入口不承载业务逻辑，只负责装配。
class DrawingNotesApp extends StatefulWidget {
  const DrawingNotesApp({super.key, this.themeController});

  /// 主题控制器（测试时可注入；为空时内部创建）。
  final AppThemeController? themeController;

  @override
  State<DrawingNotesApp> createState() => _DrawingNotesAppState();
}

class _DrawingNotesAppState extends State<DrawingNotesApp> {
  late final AppThemeController _themeController;
  // 应用内语言覆盖（2026-09-27 增量）：设置页可切换 跟随系统/中文/English。
  late final AppLocaleController _localeController;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  // 组合根拥有共享依赖的生命周期；页面只接收这些实例，不自行创建。
  // 加密底座批次①b：保险库是密钥链根，存储层经 keyProvider 拿解锁态主密钥。
  // 存储收口（2026-09-02）：统一数据根——所有业务数据收进 Documents/绘图笔记数据/。
  final AppDataRoot _appDataRoot = AppDataRoot();
  late final StorageService _documentStorage = StorageService(
    // 统一根目录：存储层内部仍追加自己的子目录名（documents/thumbnails 等），
    // 落点收拢为 绘图笔记数据/<子目录>。
    directoryProvider: _appDataRoot.root,
    keyProvider: () async {
      final vault = _vaultKeyService;
      return vault.isUnlocked ? vault.masterKey : null;
    },
  );
  // late final：keyProvider 闭包引用 _vaultKeyService（late 初始化器允许
  // 访问实例成员；与 _documentStorage 同模式）。
  late final NotebookStorage _notebookStorage = NotebookStorage(
    directoryProvider: _appDataRoot.root,
    keyProvider: () async {
      final vault = _vaultKeyService;
      return vault.isUnlocked ? vault.masterKey : null;
    },
  );
  late final NoteBlockDocStore _blockDocStore = NoteBlockDocStore(
    directoryProvider: _appDataRoot.root,
    keyProvider: () async {
      final vault = _vaultKeyService;
      return vault.isUnlocked ? vault.masterKey : null;
    },
  );
  // 收藏/标签同样收进统一根目录（组合根创建，AppShell 透传）。
  late final FavoriteStore _favoriteStore = FavoriteStore(
    directoryProvider: _appDataRoot.root,
  );
  late final TagStore _tagStore = TagStore(
    directoryProvider: _appDataRoot.root,
  );
  final AppLockService _appLockService = AppLockService();
  // 保险库密钥文件迁入统一根目录 security/（原 AppData 支持目录）。
  late final VaultKeyService _vaultKeyService = VaultKeyService(
    vaultFileResolver: () => _appDataRoot.securityFile('vault.key.json'),
  );

  // 系统验证快速解锁（批D1）：Windows Hello 快速解锁开屏（默认关闭，
  // 设置页开启后生效）。仅作用于开屏锁；文件密码不参与。
  late final QuickUnlockService _quickUnlockService = QuickUnlockService();

  @override
  void initState() {
    super.initState();
    _themeController = widget.themeController ?? AppThemeController();
    _localeController = AppLocaleController();
    // 批次①c：注册共享保险库实例——无 context 的底层管线（图片裁剪
    // 写回等）经 VaultKeyService.sharedMasterKeyOrNull 取解锁态主密钥。
    _vaultKeyService.registerShared();
    // 全局热键必须在首帧后注册：此时 MaterialApp 已 build，
    // _navigatorKey.currentState 才可用（否则热键触发导航会静默失败）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerGlobalHotkey();
    });
  }

  /// 注册全局热键（D6，借鉴 Notes 全局热键唤出）：
  /// Ctrl+Alt+N 在任何应用中唤起快速记录。
  Future<void> _registerGlobalHotkey() async {
    try {
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        HotKey(
          key: LogicalKeyboardKey.keyN,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
        ),
        keyDownHandler: (_) => _openQuickRecord(),
      );
    } catch (_) {
      // 平台不支持全局热键时静默降级（不影响正常使用）。
    }
  }

  /// 全局热键触发：打开快速记录页（新建画作并进入编辑器）。
  void _openQuickRecord() {
    // 首帧后注册已确保 navigator 就绪；若极早期触发（currentState 为
    // null），静默忽略即可（用户可再按一次）。
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    final doc = DrawingDocument(
      id: StorageService.newId(),
      // L-03（审计 2026-09-27）：标题落盘无法按 locale 变化——新建存空串
      // （E6 惯例，同图层空名），列表/标题栏经 DomainDisplayLabels 渲染。
      title: '',
    );
    nav.push(
      MaterialPageRoute(
        builder: (_) => DefaultEditorPageBuilder.build(
          document: doc,
          documentStorage: _documentStorage,
        ),
      ),
    );
  }

  @override
  void dispose() {
    hotKeyManager.unregisterAll();
    _themeController.dispose();
    _localeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_themeController, _localeController]),
      builder: (context, _) => Consumer(
        builder: (context, ref, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          navigatorObservers: [AppRefresh.routeObserver],
          // 应用内语言覆盖（2026-09-27）：null = 跟随系统（既有行为）。
          locale: _localeController.locale,
          // L-04 国际化（专家审计 2026-08-15）：gen_l10n 本地化标题。
          title: AppLocalizations.of(context)?.appTitle ?? '绘图笔记',
          localizationsDelegates: [
            AppLocalizations.delegate,
            // W3 修正（2026-09-02）：原此处注册两次 GlobalMaterialLocalizations
            // （历史上 material_ui fork 曾需自己的 MaterialLocalizations——
            // 该包已移除，注释一并删除）。现在统一用 flutter_localizations 版。
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          debugShowCheckedModeBanner: false,
          themeMode: _themeController.mode,
          // 高对比度档（平台域裁决 C2）：用户手动值优先，未手动设置时
          // 跟随系统（Windows 的「高对比度」开关）。
          theme: ref.watch(
            themeProvider(_contrastOf(context) == AppleContrast.high),
          ),
          darkTheme: AppDesign.darkTheme(contrast: _contrastOf(context)),
          // 应用启动锁门：冷启动 + 切后台回锁；未配置 PIN 时完全透明。
          home: AppLockGate(
            service: _appLockService,
            vault: _vaultKeyService,
            quickUnlock: _quickUnlockService,
            child: CloudSyncNoticeHost(
              appDataRoot: _appDataRoot,
              appLockService: _appLockService,
              child: AppShell(
                notebookStorage: _notebookStorage,
                docStorage: _documentStorage,
                themeController: _themeController,
                localeController: _localeController,
                appDataRoot: _appDataRoot,
                editorPageBuilder: DefaultEditorPageBuilder.build,
                blockDocStore: _blockDocStore,
                favoriteStore: _favoriteStore,
                tagStore: _tagStore,
                appLockService: _appLockService,
                vaultKeyService: _vaultKeyService,
                quickUnlockService: _quickUnlockService,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 最终对比度档位：用户的手动覆盖值优先，否则跟随系统设置。
  ///
  /// 这里不能用 `MediaQuery.highContrastOf(context)`——本方法在
  /// `MaterialApp` **之上**调用，那个位置还没有 MediaQuery 可用；
  /// `AppleContrast.of` 直接从 [View] 读平台属性。
  AppleContrast _contrastOf(BuildContext context) => AppleContrast.resolve(
    override: _themeController.highContrastOverride,
    platform: AppleContrast.of(context),
  );
}

/// S-02（审计 2026-09-27）：云同步 Known Folder 未加密暴露警示宿主。
///
/// 数据根默认在系统「文档」Known Folder；OneDrive KFM 等会把该目录
/// 静默迁入云盘——未设开屏 PIN 时全量明文笔记随之上云（已设 PIN 的
/// 落盘为保险库密文，不在暴露面内）。命中时启动期弹一次性说明，
/// 「我知道了」写入 SharedPreferences 永久记住。检测/弹窗尽力而为，
/// 任何失败静默跳过，不阻塞启动。
class CloudSyncNoticeHost extends StatefulWidget {
  const CloudSyncNoticeHost({
    super.key,
    required this.appDataRoot,
    required this.appLockService,
    required this.child,
  });

  final AppDataRoot appDataRoot;
  final AppLockService appLockService;
  final Widget child;

  /// 「不再提醒」持久化键（公开供测试断言）。
  static const dismissedPrefKey = 's02.cloud_sync_warning_dismissed';

  @override
  State<CloudSyncNoticeHost> createState() => _CloudSyncNoticeHostState();
}

class _CloudSyncNoticeHostState extends State<CloudSyncNoticeHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndShow());
  }

  Future<void> _checkAndShow() async {
    try {
      final docsDir = await widget.appDataRoot.documentsDirectory();
      if (!AppDataRoot.isCloudSyncedKnownFolderPath(docsDir.path)) return;
      await widget.appLockService.load();
      // 已设 PIN：落盘为保险库密文，云同步暴露面收敛，不打扰。
      if (widget.appLockService.isConfigured) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(CloudSyncNoticeHost.dismissedPrefKey) ?? false) {
        return;
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      await GlassDialog.show<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n?.s02CloudSyncTitle ?? '笔记存储在云同步文件夹中'),
          content: Text(
            l10n?.s02CloudSyncBody ??
                '你的系统「文档」文件夹由 OneDrive 等云同步服务管理，'
                    '「绘图笔记数据」会随之同步上云。',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await prefs.setBool(CloudSyncNoticeHost.dismissedPrefKey, true);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Text(l10n?.s02CloudSyncOkay ?? '我知道了'),
            ),
          ],
        ),
      );
    } catch (_) {
      // 警示尽力而为：路径不可得/存储失败等一律静默跳过。
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
