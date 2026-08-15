import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_design.dart';

/// Riverpod 状态管理骨架（S5/P1-a 落地，2026 官方推荐模式）。
///
/// 原则（riverpod.dev 官方）：
/// - Provider 是**顶层 final 不可变**声明（类似函数声明，可测试可维护）
/// - 编译时安全：provider 类型在编译期解析，拼写错误即编译失败
/// - 可测试：ProviderContainer 可独立构建，provider 可用 override 替换
///
/// 主题 provider（首个示例，验证管线打通；AppThemeController 保留兼容）。
final themeProvider = Provider<ThemeData>((ref) => AppDesign.lightTheme());

/// 深色模式开关（StateProvider 轻量示例，供 UI 层 ref.watch 驱动）。
final darkModeProvider = StateProvider<bool>((ref) => false);

/// 主题模式状态（Notifier，替代 ChangeNotifier 的渐进迁移示范）：
/// - [AppThemeController]（ChangeNotifier）职责迁入 [AppThemeNotifier]
/// - build() 承载初始化（恢复本地存储），AsyncValue 免手工 loading 标记
/// - UI 用 ref.watch(themeModeProvider) 消费，改模式调 ref.read(..notifier)
final themeModeProvider =
    NotifierProvider<AppThemeNotifier, ThemeMode>(AppThemeNotifier.new);

/// 主题模式 Notifier：维护 [ThemeMode] + shared_preferences 持久化。
class AppThemeNotifier extends Notifier<ThemeMode> {
  static const String _prefsKey = 'theme_mode';

  /// 初始化：从本地存储恢复用户上次选择（失败回退跟随系统）。
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        final mode = ThemeMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => ThemeMode.system,
        );
        state = mode;
      }
    } catch (_) {
      // 存储不可用时静默回退到跟随系统。
      state = ThemeMode.system;
    }
  }

  /// 切换主题模式并持久化。
  Future<void> setMode(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // 持久化失败不影响本次会话内的主题切换。
    }
  }

  /// 循环切换：跟随系统 → 浅色 → 深色 → 跟随系统。
  void cycle() {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    setMode(next);
  }
}
