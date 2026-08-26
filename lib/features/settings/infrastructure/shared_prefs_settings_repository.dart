// settings — Infrastructure 层：基于 SharedPreferences 的设置仓储实现
// 遵循 Clean Architecture：Infrastructure 层实现 Domain 层定义的接口

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';
import '../domain/settings_repository.dart';

/// 基于 SharedPreferences 的设置仓储实现
///
/// 将 [AppSettings] 序列化为键值对存储到本地
/// 所有 I/O 异常向上传播——由 Application 层决定处理策略
class SharedPrefsSettingsRepository implements SettingsRepository {
  static const _keyThemeMode = 'settings_theme_mode';
  static const _keyLanguage = 'settings_language';
  static const _keyAppLock = 'settings_app_lock';
  static const _keyExportPath = 'settings_export_path';

  @override
  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      themeMode: _parseThemeMode(prefs.getString(_keyThemeMode)),
      language: _parseLanguage(prefs.getString(_keyLanguage)),
      appLockEnabled: prefs.getBool(_keyAppLock) ?? false,
      exportPath: prefs.getString(_keyExportPath),
    );
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, settings.themeMode.name);
    await prefs.setString(_keyLanguage, settings.language.name);
    await prefs.setBool(_keyAppLock, settings.appLockEnabled);
    if (settings.exportPath != null) {
      await prefs.setString(_keyExportPath, settings.exportPath!);
    } else {
      await prefs.remove(_keyExportPath);
    }
  }

  AppThemeMode _parseThemeMode(String? value) {
    if (value == null) return AppThemeMode.system;
    return AppThemeMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AppThemeMode.system,
    );
  }

  AppLanguage _parseLanguage(String? value) {
    if (value == null) return AppLanguage.system;
    return AppLanguage.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AppLanguage.system,
    );
  }
}
