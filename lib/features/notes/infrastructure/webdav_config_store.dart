// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 同步配置读写（shared_preferences 持久化）。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// WebDAV 同步配置。
class WebDavSyncConfig {
  const WebDavSyncConfig({
    this.baseUrl = '',
    this.username = '',
    this.password = '',
  });

  final String baseUrl; // 集合根，如 https://dav.example.com/drawing_notes/
  final String username;
  final String password;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  WebDavSyncConfig copyWith({
    String? baseUrl,
    String? username,
    String? password,
  }) =>
      WebDavSyncConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        username: username ?? this.username,
        password: password ?? this.password,
      );

  Map<String, Object?> toJson() => {
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
      };

  factory WebDavSyncConfig.fromJson(Map<String, Object?> json) =>
      WebDavSyncConfig(
        baseUrl: (json['baseUrl'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
      );
}

/// 配置门面（shared_preferences 持久化）。
class WebDavConfigStore {
  static const _key = 'webdav_sync_config';

  Future<WebDavSyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const WebDavSyncConfig();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return WebDavSyncConfig.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } catch (_) {
      return const WebDavSyncConfig();
    }
  }

  Future<void> save(WebDavSyncConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
