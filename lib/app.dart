import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations;
// Flutter SDK 版 GlobalMaterialLocalizations 的别名（与 material_ui 版同名不同类）。
// 两者都要注册：material_ui 组件用 material_ui 版，flutter/material 组件
// （如 All Docs 侧栏搜索框等）用 Flutter 版，各取各的，互不冲突。
import 'package:flutter_localizations/flutter_localizations.dart'
    as fl_loc show GlobalMaterialLocalizations;

import 'package:drawing_notes_app/app/default_editor_page_builder.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/di/providers.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'l10n/app_localizations.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/app/app_shell.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/note_block_doc_store.dart';

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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  // 组合根拥有共享依赖的生命周期；页面只接收这些实例，不自行创建。
  final StorageService _documentStorage = StorageService();
  final NotebookStorage _notebookStorage = NotebookStorage();
  final NoteBlockDocStore _blockDocStore = NoteBlockDocStore();

  @override
  void initState() {
    super.initState();
    _themeController = widget.themeController ?? AppThemeController();
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
      title:
          '快速记录 ${DateTime.now().hour.toString().padLeft(2, '0')}:'
          '${DateTime.now().minute.toString().padLeft(2, '0')}',
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) => Consumer(
        builder: (context, ref, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          // L-04 国际化（专家审计 2026-08-15）：gen_l10n 本地化标题。
          title: AppLocalizations.of(context)?.appTitle ?? '绘图笔记',
          localizationsDelegates: [
            AppLocalizations.delegate,
            // 必须用 material_ui 的 GlobalMaterialLocalizations（而非 Flutter 的）：
            // 本应用的 Material 组件（AppBar/Scaffold 等）来自 material_ui 包，它拥有
            // 自己的一套 MaterialLocalizations。若注册 Flutter 版，debug 模式下
            // material_ui 组件里的 debugCheckHasMaterialLocalizations 会断言崩溃
            // （release 断言被裁剪所以表面正常）。故 Material 用 material_ui 的，
            // Widgets/Cupertino 仍用 flutter_localizations 的（material_ui 不导出）。
            GlobalMaterialLocalizations.delegate,
            // 同时注册 Flutter SDK 版，供 flutter/material 组件
            // （All Docs 侧栏搜索框等）解析 MaterialLocalizations，
            // 避免 "No MaterialLocalizations found"。两者类型不同，互不冲突。
            fl_loc.GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          debugShowCheckedModeBanner: false,
          themeMode: _themeController.mode,
          theme: ref.watch(themeProvider),
          darkTheme: AppDesign.darkTheme(),
          home: AppShell(
            notebookStorage: _notebookStorage,
            docStorage: _documentStorage,
            themeController: _themeController,
            editorPageBuilder: DefaultEditorPageBuilder.build,
            blockDocStore: _blockDocStore,
          ),
        ),
      ),
    );
  }
}
