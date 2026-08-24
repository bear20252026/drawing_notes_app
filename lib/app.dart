import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/di/providers.dart';
import 'package:drawing_notes_app/core/router/app_router.dart';
import 'l10n/app_localizations.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/security/auth_guard.dart';

/// 应用根组件：主题 + 路由。
///
/// 设计说明：
/// - 深色/浅色主题均支持，用户可手动切换（跟随系统/浅色/深色，Phase 7）；
/// - 主题模式由 Riverpod [themeModeProvider] 统一管理并持久化；
/// - 路由使用 GoRouter 声明式管理，支持深度链接和路由守卫；
/// - 应用入口不承载业务逻辑，只负责装配。
class DrawingNotesApp extends ConsumerStatefulWidget {
  const DrawingNotesApp({super.key});

  @override
  ConsumerState<DrawingNotesApp> createState() => _DrawingNotesAppState();
}

class _DrawingNotesAppState extends ConsumerState<DrawingNotesApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter();

    // 初始化认证守卫（检查密码盘是否存在）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AuthGuard.instance.initialize();
      _registerGlobalHotkey();
      _handleInitialDeepLink();
    });
  }

  /// 处理启动时的深度链接/文件关联
  void _handleInitialDeepLink() {
    // Windows: 从命令行参数解析 .drawingnotes 文件关联
    final args = DeepLinkParser.parseFileAssociation(
      WidgetsBinding.instance.platformDispatcher.views.first
          .viewConfiguration
          .debugShowWidgetInspectorOverride == true
          ? <String>[]
          : [],
    );
    // 注意：命令行参数已通过 project.set_dart_entrypoint_arguments 传递
    // 实际解析在 main.dart 中完成并传入
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

  /// 全局热键触发：通过 GoRouter 打开快速记录。
  void _openQuickRecord() {
    final docId = StorageService.newId();
    final title =
        '快速记录 ${DateTime.now().hour.toString().padLeft(2, '0')}:'
        '${DateTime.now().minute.toString().padLeft(2, '0')}';
    _router.go(
      '${RoutePaths.editor}/$docId?title=${Uri.encodeComponent(title)}',
    );
  }

  @override
  void dispose() {
    hotKeyManager.unregisterAll();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
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
      routerConfig: _router,
    );
  }
}
