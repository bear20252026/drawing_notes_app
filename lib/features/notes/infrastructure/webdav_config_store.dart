// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 同步配置读写（shared_preferences 持久化）。
//
// 机密（WebDAV 认证密码 / E2E 同步口令）不落盘于此，而是经 SyncSecretStore
// （OS 凭据库）存储，见 sync_secret_store.dart；此处仅持久化非机密配置
// （baseUrl / username / syncSalt）。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sync_secret_store.dart';

/// WebDAV 同步配置（仅非机密字段）。
///
/// 机密字段（认证密码 / 同步口令）由 [SyncSecretStore] 承载，
/// 以保证「配置（非机密）」与「机密」分离、不混入明文存储。
class WebDavSyncConfig {
  const WebDavSyncConfig({
    this.baseUrl = '',
    this.username = '',
    this.syncSalt,
  });

  final String baseUrl; // 集合根，如 https://dav.example.com/drawing_notes/
  final String username;

  /// 派生密钥用的随机盐（base64 编码）。非机密，可与配置一起持久化。
  final String? syncSalt;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// 是否已具备派生密钥所需的盐。
  bool get hasSyncSalt => syncSalt != null && syncSalt!.isNotEmpty;

  WebDavSyncConfig copyWith({
    String? baseUrl,
    String? username,
    String? syncSalt,
  }) => WebDavSyncConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    username: username ?? this.username,
    syncSalt: syncSalt ?? this.syncSalt,
  );

  Map<String, Object?> toJson() => {
    'baseUrl': baseUrl,
    'username': username,
    'syncSalt': syncSalt,
  };

  factory WebDavSyncConfig.fromJson(Map<String, Object?> json) =>
      WebDavSyncConfig(
        baseUrl: (json['baseUrl'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        syncSalt: json['syncSalt'] as String?,
      );
}

/// 配置门面（shared_preferences 持久化，仅非机密）。
///
/// [secretStore]：可选注入。用于把旧版本明文存储的机密迁移到 OS 凭据库，
/// 并在迁移成功后剥离配置中的明文键（幂等）。生产组合根应总是注入
/// `SecureSyncSecretStore`；测试可注入 `MemorySyncSecretStore` 或留空。
class WebDavConfigStore {
  /// [secretStore]：可选注入，用于把旧版本明文机密迁移到 OS 凭据库。
  /// 生产组合根应总是注入 `SecureSyncSecretStore`；测试可留空或注入替身。
  WebDavConfigStore([this._secretStore]);

  final SyncSecretStore? _secretStore;

  static const _key = 'webdav_sync_config';

  Future<WebDavSyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const WebDavSyncConfig();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final map = Map<String, Object?>.from(decoded);
      final cfg = WebDavSyncConfig.fromJson(map);
      await _migrateLegacySecrets(prefs, map);
      return cfg;
    } catch (_) {
      return const WebDavSyncConfig();
    }
  }

  /// 旧版本把机密（password / syncPassphrase）明文存进配置 JSON。
  ///
  /// 若存在且注入了 secretStore，则迁移到机密存储，并重写配置（剥离明文）。
  /// 未注入 secretStore 时不做迁移、不剥离，避免丢数据。
  Future<void> _migrateLegacySecrets(
    SharedPreferences prefs,
    Map<String, Object?> map,
  ) async {
    if (!map.containsKey('password') && !map.containsKey('syncPassphrase')) {
      return;
    }
    final store = _secretStore;
    if (store == null) return;
    final legacyPassword = (map['password'] as String?)?.trim() ?? '';
    final legacyPassphrase = (map['syncPassphrase'] as String?)?.trim() ?? '';
    if (legacyPassword.isEmpty && legacyPassphrase.isEmpty) {
      return;
    }
    await store.write(
      SyncSecrets(
        webdavPassword: legacyPassword.isEmpty ? null : legacyPassword,
        syncPassphrase: legacyPassphrase.isEmpty ? null : legacyPassphrase,
      ),
    );
    // 迁移成功后剥离明文键，避免再次读取到。
    map.remove('password');
    map.remove('syncPassphrase');
    await prefs.setString(_key, jsonEncode(map));
  }

  /// 保存前 TLS 门禁（P1 修复）：非空 baseUrl 必须 https（本地回环 http
  /// 除外）——否则 Basic 口令与文档明文传输。非法抛 [ArgumentError]，
  /// 设置页捕获后向用户明示（fail-closed，不落盘）。
  static void requireHttpsBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ArgumentError('WebDAV 地址不合法');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return;
    final host = uri.host.toLowerCase();
    final loopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (scheme == 'http' && loopback) return;
    throw ArgumentError('WebDAV 仅允许 https（明文 http 会泄露口令与文档）');
  }

  Future<void> save(WebDavSyncConfig config) async {
    requireHttpsBaseUrl(config.baseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }

  /// 登出/重置：配置与机密一并清除（P1 修复——此前仅删配置，凭据库里的
  /// WebDAV 密码与同步口令残留）。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    try {
      await _secretStore?.clear();
    } catch (_) {}
  }
}
