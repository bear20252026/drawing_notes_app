// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 配置存储测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('保存/读取回环', () async {
    final store = WebDavConfigStore();
    await store.save(const WebDavSyncConfig(
      baseUrl: 'https://dav.example.com/n/',
      username: 'user',
      password: 'p@ss',
    ));
    final cfg = await store.load();
    expect(cfg.baseUrl, 'https://dav.example.com/n/');
    expect(cfg.username, 'user');
    expect(cfg.password, 'p@ss');
    expect(cfg.isConfigured, isTrue);
  });

  test('无配置时返回默认空配置', () async {
    final cfg = await WebDavConfigStore().load();
    expect(cfg.isConfigured, isFalse);
    expect(cfg.baseUrl, '');
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
    final b = a.copyWith(password: 'p');
    expect(b.baseUrl, 'https://a/');
    expect(b.username, 'u');
    expect(b.password, 'p');
  });

  group('E2E 加密字段（syncPassphrase / syncSalt）', () {
    test('带 syncPassphrase/syncSalt 的 round-trip', () async {
      final store = WebDavConfigStore();
      await store.save(const WebDavSyncConfig(
        baseUrl: 'https://dav.example.com/n/',
        username: 'user',
        password: 'p@ss',
        syncPassphrase: 'my-secret-passphrase',
        syncSalt: 'c2FsdDEyMw==',
      ));
      final cfg = await store.load();
      expect(cfg.syncPassphrase, 'my-secret-passphrase');
      expect(cfg.syncSalt, 'c2FsdDEyMw==');
      expect(cfg.hasSyncSecret, isTrue);
    });

    test('hasSyncSecret：两者齐全 → true', () {
      const cfg = WebDavSyncConfig(
        syncPassphrase: 'pass',
        syncSalt: 'c2FsdA==',
      );
      expect(cfg.hasSyncSecret, isTrue);
    });

    test('hasSyncSecret：仅口令无盐 → false', () {
      const cfg = WebDavSyncConfig(syncPassphrase: 'pass');
      expect(cfg.hasSyncSecret, isFalse);
    });

    test('hasSyncSecret：仅盐无口令 → false', () {
      const cfg = WebDavSyncConfig(syncSalt: 'c2FsdA==');
      expect(cfg.hasSyncSecret, isFalse);
    });

    test('hasSyncSecret：均 null → false', () {
      const cfg = WebDavSyncConfig();
      expect(cfg.hasSyncSecret, isFalse);
    });

    test('hasSyncSecret：口令为空串 → false', () {
      const cfg = WebDavSyncConfig(
        syncPassphrase: '',
        syncSalt: 'c2FsdA==',
      );
      expect(cfg.hasSyncSecret, isFalse);
    });

    test('copyWith 新增两字段生效', () {
      const a = WebDavSyncConfig(baseUrl: 'https://a/');
      final b = a.copyWith(
        syncPassphrase: 'new-pass',
        syncSalt: 'bmV3LXNhbHQ=',
      );
      expect(b.syncPassphrase, 'new-pass');
      expect(b.syncSalt, 'bmV3LXNhbHQ=');
      // 未改字段保持不变
      expect(b.baseUrl, 'https://a/');
    });

    test('旧 JSON（无新键）fromJson → 字段 null、hasSyncSecret false', () {
      final json = <String, Object?>{
        'baseUrl': 'https://old/',
        'username': 'u',
        'password': 'p',
      };
      final cfg = WebDavSyncConfig.fromJson(json);
      expect(cfg.syncPassphrase, isNull);
      expect(cfg.syncSalt, isNull);
      expect(cfg.hasSyncSecret, isFalse);
      // 旧字段仍正常解析
      expect(cfg.baseUrl, 'https://old/');
    });

    test('toJson 含新字段键', () {
      const cfg = WebDavSyncConfig(
        baseUrl: 'https://x/',
        syncPassphrase: 'pp',
        syncSalt: 'ss',
      );
      final json = cfg.toJson();
      expect(json['syncPassphrase'], 'pp');
      expect(json['syncSalt'], 'ss');
    });
  });
}
