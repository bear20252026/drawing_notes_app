// core/config——EnvConfig 环境变量配置（安全加固 P0——避免硬编码密钥）。
//
// 安全原则：
// - 敏感配置（API 密钥、加密盐值等）通过 .env 文件加载
// - .env 文件已加入 .gitignore，不会被提交到仓库
// - 代码中只引用此服务，不直接硬编码敏感值
//
// 使用方式：
// 1. 复制 .env.example 为 .env
// 2. 填入实际配置值
// 3. 应用启动时调用 EnvConfig.load()
//
// GPL-3.0 许可证——保留原始版权声明。
library;

import 'dart:io';

/// 环境变量配置服务。
///
/// 从 .env 文件加载配置，支持默认值回退。
/// 安全：敏感值不进仓库，代码中只通过此类访问。
class EnvConfig {
  static final Map<String, String> _config = {};
  static bool _loaded = false;

  /// 加载 .env 文件。
  ///
  /// [path] — .env 文件路径（默认为应用目录下的 .env）
  static Future<void> load({String? path}) async {
    if (_loaded) return;

    final envPath = path ?? '.env';
    final file = File(envPath);

    if (!await file.exists()) {
      // .env 文件不存在——使用默认值（开发环境允许）。
      _loaded = true;
      return;
    }

    final content = await file.readAsString();
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final eqIndex = trimmed.indexOf('=');
      if (eqIndex < 0) continue;

      final key = trimmed.substring(0, eqIndex).trim();
      var value = trimmed.substring(eqIndex + 1).trim();

      // 移除引号包裹。
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }

      _config[key] = value;
    }

    _loaded = true;
  }

  /// 获取配置值，不存在时返回默认值。
  static String get(String key, {String defaultValue = ''}) {
    return _config[key] ?? defaultValue;
  }

  /// 获取必需的配置值，不存在时抛出异常。
  static String require(String key) {
    final value = _config[key];
    if (value == null || value.isEmpty) {
      throw EnvironmentError(
        '缺少必需的环境变量: $key\n'
        '请在 .env 文件中配置此变量（参考 .env.example）',
      );
    }
    return value;
  }

  /// 检查配置是否存在。
  static bool has(String key) => _config.containsKey(key);

  /// 获取所有配置的键（用于调试，不输出值）。
  static List<String> get keys => _config.keys.toList();

  /// 重置状态（测试用）。
  static void reset() {
    _config.clear();
    _loaded = false;
  }

  /// ---- 预定义配置项 ----

  /// 加密服务盐值（生产环境应使用随机值）。
  static String get encryptionSalt =>
      get('ENCRYPTION_SALT', defaultValue: 'default-salt-change-in-production');

  /// Nextcloud 服务器地址。
  static String get nextcloudServer =>
      get('NEXTCLOUD_SERVER', defaultValue: '');

  /// Nextcloud 用户名。
  static String get nextcloudUsername =>
      get('NEXTCLOUD_USERNAME', defaultValue: '');

  /// Nextcloud 密码（应用密码，非账户密码）。
  static String get nextcloudPassword =>
      get('NEXTCLOUD_PASSWORD', defaultValue: '');

  /// Sentry DSN（错误监控）。
  static String get sentryDsn =>
      get('SENTRY_DSN', defaultValue: '');
}
