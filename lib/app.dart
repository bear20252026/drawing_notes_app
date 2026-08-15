import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/di/providers.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';

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
        builder: (_) => EditorPage(document: doc, docStorage: StorageService()),
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
          title: '绘图笔记',
          debugShowCheckedModeBanner: false,
          themeMode: _themeController.mode,
          theme: ref.watch(themeProvider),
          darkTheme: AppDesign.darkTheme(),
          home: HomePage(themeController: _themeController),
        ),
      ),
    );
  }
}
