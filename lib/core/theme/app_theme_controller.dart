import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用级主题控制器（Phase 7 深色模式）。
///
/// 负责三件事：
/// 1. 维护当前 [ThemeMode]（跟随系统 / 浅色 / 深色）；
/// 2. 把用户选择持久化到本地（shared_preferences），下次启动记住；
/// 3. 作为 [ChangeNotifier] 通知整个应用刷新主题。
///
/// 使用方式：在应用根部创建并监听，例如：
/// ```dart
/// final themeController = AppThemeController();
/// ValueListenableBuilder<ThemeMode>(
///   valueListenable: themeController,
///   builder: (_, mode, __) => MaterialApp(themeMode: mode, ...),
/// );
/// ```
class AppThemeController extends ChangeNotifier {
  AppThemeController({SharedPreferences? prefs}) {
    _prefs = prefs;
    _load();
  }

  static const String _prefsKey = 'theme_mode';

  /// 高对比度档的用户覆盖值：`system` / `on` / `off`。
  ///
  /// 默认 `system`——跟随 Windows 的「高对比度」系统设置
  /// （由 `AppleContrast.of(context)` 读取）。用户也可以手动强制开关，
  /// 手动值优先于系统值（无障碍是个人偏好，系统设置未必合用）。
  static const String _hcPrefsKey = 'high_contrast';

  SharedPreferences? _prefs;
  ThemeMode _mode = ThemeMode.system;

  /// null = 跟随系统。
  bool? _highContrastOverride;

  bool _loaded = false;

  ThemeMode get mode => _mode;

  /// 用户是否手动覆盖了高对比度档；null = 跟随系统。
  bool? get highContrastOverride => _highContrastOverride;

  /// 从本地存储恢复用户上次的选择。
  Future<void> _load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final saved = _prefs!.getString(_prefsKey);
      if (saved != null) {
        _mode = ThemeMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => ThemeMode.system,
        );
      }
      _highContrastOverride = switch (_prefs!.getString(_hcPrefsKey)) {
        'on' => true,
        'off' => false,
        _ => null, // 未设置或未知值一律跟随系统
      };
    } catch (_) {
      // 存储不可用时静默回退到跟随系统。
      _mode = ThemeMode.system;
    }
    _loaded = true;
    notifyListeners();
  }

  /// 是否已从本地存储恢复（避免启动时主题闪烁）。
  bool get loaded => _loaded;

  /// 切换主题模式并持久化。
  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_prefsKey, mode.name);
    } catch (_) {
      // 持久化失败不影响本次会话内的主题切换。
    }
  }

  /// 循环切换：跟随系统 → 浅色 → 深色 → 跟随系统。
  void cycle() {
    final next = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    setMode(next);
  }

  /// 设置高对比度档；传 null 表示恢复「跟随系统」。
  Future<void> setHighContrast(bool? value) async {
    if (_highContrastOverride == value) return;
    _highContrastOverride = value;
    notifyListeners();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(
        _hcPrefsKey,
        switch (value) {
          null => 'system',
          true => 'on',
          false => 'off',
        },
      );
    } catch (_) {
      // 持久化失败不影响本次会话内的切换。
    }
  }

  /// 三态循环：跟随系统 → 强制开 → 强制关 → 跟随系统。
  void cycleHighContrast() {
    setHighContrast(
      switch (_highContrastOverride) {
        null => true,
        true => false,
        false => null,
      },
    );
  }

  /// 设置项的当前文案。
  String get highContrastLabel => switch (_highContrastOverride) {
    null => '跟随系统（点击切换为强制开启）',
    true => '已开启（点击切换为强制关闭）',
    false => '已关闭（点击切换为跟随系统）',
  };
}
