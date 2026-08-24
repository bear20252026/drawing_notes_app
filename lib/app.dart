import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/di/providers.dart';
import 'l10n/app_localizations.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';
import 'package:drawing_notes_app/core/error/error_service.dart';

/// 应用根组件：主题 + 路由。
///
/// 设计说明：
/// - 深色/浅色主题均支持，用户可手动切换（跟随系统/浅色/深色，Phase 7）；
/// - 主题模式由 Riverpod [themeModeProvider] 统一管理并持久化；
/// - 路由集中管理，新增页面时在此注册；
/// - 应用入口不承载业务逻辑，只负责装配。
class DrawingNotesApp extends ConsumerStatefulWidget {
  const DrawingNotesApp({super.key});

  @override
  ConsumerState<DrawingNotesApp> createState() => _DrawingNotesAppState();
}

class _DrawingNotesAppState extends ConsumerState<DrawingNotesApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    ErrorService.init(_navigatorKey);
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
        builder: (_) => EditorPage(document: doc, docStorage: StorageService()),
      ),
    );
  }

  @override
  void dispose() {
    hotKeyManager.unregisterAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: AppLocalizations.of(context)?.appTitle ?? '绘图笔记',
      locale: const Locale('en'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
      ],
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ref.watch(themeProvider),
      darkTheme: AppDesign.darkTheme(),
      home: const HomePage(),
    );
  }
}
