// settings — Domain 层：应用设置实体（零外部依赖）
// 遵循 Clean Architecture：Domain 层不依赖任何外部库或框架

/// 主题模式枚举
enum AppThemeMode {
  /// 跟随系统
  system,
  /// 浅色模式
  light,
  /// 深色模式
  dark,
}

/// 应用语言枚举
enum AppLanguage {
  /// 跟随系统
  system,
  /// 简体中文
  chinese,
  /// 英文
  english,
}

/// 应用设置实体（不可变）
///
/// 包含用户可配置的所有应用级设置
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.language = AppLanguage.system,
    this.appLockEnabled = false,
    this.exportPath,
  });

  /// 主题模式
  final AppThemeMode themeMode;

  /// 应用语言
  final AppLanguage language;

  /// 是否启用应用锁定
  final bool appLockEnabled;

  /// 导出路径（null 表示使用默认路径）
  final String? exportPath;

  /// 创建副本并覆盖指定字段
  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppLanguage? language,
    bool? appLockEnabled,
    String? exportPath,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      exportPath: exportPath ?? this.exportPath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          language == other.language &&
          appLockEnabled == other.appLockEnabled &&
          exportPath == other.exportPath;

  @override
  int get hashCode =>
      themeMode.hashCode ^
      language.hashCode ^
      appLockEnabled.hashCode ^
      exportPath.hashCode;

  @override
  String toString() =>
      'AppSettings(themeMode: $themeMode, language: $language, '
      'appLockEnabled: $appLockEnabled, exportPath: $exportPath)';
}
