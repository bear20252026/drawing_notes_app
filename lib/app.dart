import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_design.dart';
import 'infrastructure/di/providers.dart';
import 'l10n/app_localizations.dart';
import 'infrastructure/router/app_router.dart';
import 'core/security/auth_guard.dart';

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
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // 路由立即创建，AuthGuard 在后台异步初始化。
    // 路由 redirect 中会检查认证状态，初始化完成前不会错误拦截。
    _router = createAppRouter();
    _initAuth();
    // 全局热键必须在首帧后注册。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerGlobalHotkey();
    });
  }

  Future<void> _initAuth() async {
    await AuthGuard.instance.initialize();
    // 路由守卫已在 router redirect 中通过 listener 处理状态变更，
    // 无需 setState 重建 MaterialApp。
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

  /// 全局热键触发：通过 GoRouter 打开快速记录页。
  void _openQuickRecord() {
    _router.go('/editor/new');
  }

  @override
  void dispose() {
    hotKeyManager.unregisterAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppLocalizations.of(context)?.appTitle ?? '绘图笔记',
      locale: null, // 跟随系统语言
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
      // Apple 风格滚动物理：iOS 式弹性滚动
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        physics: const BouncingScrollPhysics(),
        scrollbars: true,
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      routerConfig: _router,
    );
  }
}
