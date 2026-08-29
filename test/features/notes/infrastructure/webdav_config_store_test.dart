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
}
