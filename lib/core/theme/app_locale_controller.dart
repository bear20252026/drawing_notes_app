import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用级语言控制器（设置页「语言」项，2026-09-27 增量新增）。
///
/// 职责与 [AppThemeController] 同构：
/// 1. 维护当前 [Locale] 覆盖值（跟随系统 / 中文 / English）；
/// 2. 持久化到 shared_preferences，下次启动记住；
/// 3. 作为 [ChangeNotifier] 通知 MaterialApp 重建（`locale:` 覆盖）。
///
/// 默认 null（跟随系统）——与 MaterialApp 既有行为一致：仅当用户显式
/// 选择后才覆盖系统语言。
class AppLocaleController extends ChangeNotifier {
  AppLocaleController({SharedPreferences? prefs}) {
    _prefs = prefs;
    _load();
  }

  static const String _prefsKey = 'app_locale';

  SharedPreferences? _prefs;
  Locale? _locale;
  bool _loaded = false;

  /// 当前语言覆盖；null = 跟随系统。
  Locale? get locale => _locale;

  /// 是否已从本地存储恢复。
  bool get loaded => _loaded;

  Future<void> _load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      _locale = switch (_prefs!.getString(_prefsKey)) {
        'zh' => const Locale('zh'),
        'en' => const Locale('en'),
        _ => null, // 未设置或未知值一律跟随系统
      };
    } catch (_) {
      // 存储不可用时静默回退到跟随系统。
      _locale = null;
    }
    _loaded = true;
    notifyListeners();
  }

  /// 设置语言覆盖；传 null 表示恢复「跟随系统」。
  Future<void> setLocale(Locale? locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_prefsKey, switch (locale?.languageCode) {
        null => 'system',
        'zh' => 'zh',
        'en' => 'en',
        _ => 'system', // 不在支持列表的语言回退跟随系统
      });
    } catch (_) {
      // 持久化失败不影响本次会话内的切换。
    }
  }

  /// 三态循环：跟随系统 → 中文 → English → 跟随系统。
  void cycle() {
    setLocale(switch (_locale?.languageCode) {
      null => const Locale('zh'),
      'zh' => const Locale('en'),
      _ => null,
    });
  }
}
