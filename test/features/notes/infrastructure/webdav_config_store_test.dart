// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 配置存储测试。
//
// 说明：机密（认证密码/同步口令）已从 WebDavSyncConfig 移除，改由 SyncSecretStore
// （OS 凭据库）承载；本测试仅覆盖非机密配置的持久化，以及「旧明文 → 机密存储」迁移。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('保存/读取回环（非机密）', () async {
    final store = WebDavConfigStore();
    await store.save(const WebDavSyncConfig(
      baseUrl: 'https://dav.example.com/n/',
      username: 'user',
      syncSalt: 'c2FsdDEyMw==',
    ));
    final cfg = await store.load();
    expect(cfg.baseUrl, 'https://dav.example.com/n/');
    expect(cfg.username, 'user');
    expect(cfg.syncSalt, 'c2FsdDEyMw==');
    expect(cfg.isConfigured, isTrue);
  });

  test('无配置时返回默认空配置', () async {
    final cfg = await WebDavConfigStore().load();
    expect(cfg.isConfigured, isFalse);
    expect(cfg.baseUrl, '');
    expect(cfg.username, '');
    expect(cfg.syncSalt, isNull);
  });

  test('损坏的存储回退为空配置', () async {
    SharedPreferences.setMockInitialValues({
      'webdav_sync_config': '{bad json',
    });
    final cfg = await WebDavConfigStore().load();
    expect(cfg.isConfigured, isFalse);
  });

  test('clear 移除配置', () async {
    final store = WebDavConfigStore();
    await store.save(const WebDavSyncConfig(baseUrl: 'https://x/'));
    await store.clear();
    final cfg = await store.load();
    expect(cfg.isConfigured, isFalse);
  });

  test('copyWith 只改部分字段', () {
    const a = WebDavSyncConfig(baseUrl: 'https://a/', username: 'u');
    final b = a.copyWith(username: 'u2', syncSalt: 'c2FsdA==');
    expect(b.baseUrl, 'https://a/');
    expect(b.username, 'u2');
    expect(b.syncSalt, 'c2FsdA==');
  });

  group('加密盐（syncSalt）', () {
    test('带 syncSalt 的 round-trip', () async {
      final store = WebDavConfigStore();
      await store.save(const WebDavSyncConfig(
        baseUrl: 'https://dav.example.com/n/',
        username: 'user',
        syncSalt: 'c2FsdDEyMw==',
      ));
      final cfg = await store.load();
      expect(cfg.syncSalt, 'c2FsdDEyMw==');
      expect(cfg.hasSyncSalt, isTrue);
    });

    test('hasSyncSalt：有盐 → true', () {
      const cfg = WebDavSyncConfig(syncSalt: 'c2FsdA==');
      expect(cfg.hasSyncSalt, isTrue);
    });

    test('hasSyncSalt：无盐 → false', () {
      const cfg = WebDavSyncConfig();
      expect(cfg.hasSyncSalt, isFalse);
    });

    test('hasSyncSalt：空串 → false', () {
      const cfg = WebDavSyncConfig(syncSalt: '');
      expect(cfg.hasSyncSalt, isFalse);
    });

    test('toJson 不含机密键', () {
      const cfg = WebDavSyncConfig(
        baseUrl: 'https://x/',
        syncSalt: 'ss',
      );
      final json = cfg.toJson();
      expect(json['baseUrl'], 'https://x/');
      expect(json['syncSalt'], 'ss');
      expect(json.containsKey('password'), isFalse);
      expect(json.containsKey('syncPassphrase'), isFalse);
    });

    test('fromJson 旧 JSON（含 password/syncPassphrase）忽略机密键', () {
      final json = <String, Object?>{
        'baseUrl': 'https://old/',
        'username': 'u',
        'password': 'p',
        'syncPassphrase': 'legacy-pass',
      };
      final cfg = WebDavSyncConfig.fromJson(json);
      expect(cfg.syncSalt, isNull);
      expect(cfg.hasSyncSalt, isFalse);
      // 非机密字段仍正常解析
      expect(cfg.baseUrl, 'https://old/');
      expect(cfg.username, 'u');
    });
  });

  group('旧明文 → 机密存储迁移', () {
    const legacyRaw =
        '{"baseUrl":"https://old/","username":"u","password":"p@ss","syncPassphrase":"legacy-pass"}';

    test('注入 MemorySyncSecretStore：迁移到机密存储并剥离明文键', () async {
      SharedPreferences.setMockInitialValues({
        'webdav_sync_config': legacyRaw,
      });
      final secrets = MemorySyncSecretStore();
      final store = WebDavConfigStore(secrets);

      final cfg = await store.load();
      // 非机密配置正确解析
      expect(cfg.baseUrl, 'https://old/');
      expect(cfg.username, 'u');
      // 机密已迁移
      final migrated = await secrets.read();
      expect(migrated.webdavPassword, 'p@ss');
      expect(migrated.syncPassphrase, 'legacy-pass');
      // 配置 JSON 已剥离明文键（幂等，下次读取不再迁移）
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString('webdav_sync_config')!) as Map;
      expect(stored.containsKey('password'), isFalse);
      expect(stored.containsKey('syncPassphrase'), isFalse);
      // 二次 load 仍正常，且机密不变
      final cfg2 = await store.load();
      expect(cfg2.baseUrl, 'https://old/');
      final migrated2 = await secrets.read();
      expect(migrated2.webdavPassword, 'p@ss');
    });

    test('迁移空机密：不写入机密，密钥被剥离', () async {
      SharedPreferences.setMockInitialValues({
        'webdav_sync_config': '{"baseUrl":"https://old/","username":"u","password":"","syncPassphrase":""}',
      });
      final secrets = MemorySyncSecretStore();
      final store = WebDavConfigStore(secrets);

      final cfg = await store.load();
      expect(cfg.baseUrl, 'https://old/');
      final migrated = await secrets.read();
      expect(migrated.isEmpty, isTrue);
    });

    test('未注入 secretStore：不迁移、不剥离（避免丢数据）', () async {
      SharedPreferences.setMockInitialValues({
        'webdav_sync_config': legacyRaw,
      });
      final store = WebDavConfigStore();
      final cfg = await store.load();
      expect(cfg.baseUrl, 'https://old/');
      // 明文键保留在 prefs（未剥离）
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString('webdav_sync_config')!) as Map;
      expect(stored.containsKey('password'), isTrue);
      expect(stored.containsKey('syncPassphrase'), isTrue);
    });

    test('旧 JSON 不含明文键：load 不触发迁移写入', () async {
      SharedPreferences.setMockInitialValues({
        'webdav_sync_config':
            '{"baseUrl":"https://old/","username":"u","syncSalt":"c2FsdA=="}',
      });
      final secrets = MemorySyncSecretStore();
      final store = WebDavConfigStore(secrets);
      final cfg = await store.load();
      expect(cfg.syncSalt, 'c2FsdA==');
      expect(await secrets.read(), isEmpty);
    });
  });
}
