// settings — Application 层：设置状态管理
// 遵循 Clean Architecture：Application 层只依赖 Domain 层

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_settings.dart';
import '../domain/settings_repository.dart';
import '../infrastructure/shared_prefs_settings_repository.dart';

/// 设置状态管理器
///
/// 通过 [SettingsRepository] 接口存取设置
/// 不直接依赖任何具体存储实现
class SettingsNotifier extends AsyncNotifier<AppSettings> {
  late final SettingsRepository _repository;

  @override
  Future<AppSettings> build() async {
    // 通过 ref 获取仓储 Provider（由 composition root 注入）
    _repository = ref.read(settingsRepositoryProvider);
    return _repository.loadSettings();
  }

  /// 更新主题模式
  Future<void> setThemeMode(AppThemeMode mode) async {
    final current = state.value ?? const AppSettings();
    final updated = current.copyWith(themeMode: mode);
    state = AsyncData(updated);
    await _repository.saveSettings(updated);
  }

  /// 更新语言设置
  Future<void> setLanguage(AppLanguage language) async {
    final current = state.value ?? const AppSettings();
    final updated = current.copyWith(language: language);
    state = AsyncData(updated);
    await _repository.saveSettings(updated);
  }

  /// 切换应用锁定
  Future<void> toggleAppLock(bool enabled) async {
    final current = state.value ?? const AppSettings();
    final updated = current.copyWith(appLockEnabled: enabled);
    state = AsyncData(updated);
    await _repository.saveSettings(updated);
  }

  /// 更新导出路径
  Future<void> setExportPath(String? path) async {
    final current = state.value ?? const AppSettings();
    final updated = current.copyWith(exportPath: path);
    state = AsyncData(updated);
    await _repository.saveSettings(updated);
  }
}

/// SettingsNotifier Provider（供 Presentation 层使用）
final settingsNotifierProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(
        SettingsNotifier.new);

/// SettingsRepository Provider（DI 入口——注入 SharedPreferences 实现）
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SharedPrefsSettingsRepository();
});
