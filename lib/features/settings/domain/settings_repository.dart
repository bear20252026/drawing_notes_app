// settings — Domain 层：设置仓储接口（零外部依赖）
// 遵循 Clean Architecture：Domain 层定义抽象契约，实现由 Infrastructure 层提供

import 'app_settings.dart';

/// 设置仓储接口
///
/// 负责应用设置的持久化读写
/// 实现由 Infrastructure 层提供（基于 SharedPreferences / 文件系统等）
abstract class SettingsRepository {
  /// 加载当前设置（若无已保存设置则返回默认值）
  Future<AppSettings> loadSettings();

  /// 保存设置
  Future<void> saveSettings(AppSettings settings);
}
