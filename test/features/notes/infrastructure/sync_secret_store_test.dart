// P4-C1 同步机密存储测试：Memory 实现 + Secure 实现 + SyncSecrets 纯容器。

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';

/// 注入式假 FlutterSecureStorage：extends 并覆写 read/write/delete 记录调用。
class FakeSecureStorage extends FlutterSecureStorage {
  FakeSecureStorage([Map<String, String>? initial])
    : _store = Map.of(initial ?? {});

  final Map<String, String> _store;

  final List<Map<String, String>> writes = [];
  final List<String> deletes = [];

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async => _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    writes.add({'key': key, 'value': value ?? ''});
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    deletes.add(key);
    _store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async => Map.of(_store);

  @override
  Future<void> deleteAll({
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async => _store.clear();
}

void main() {
  group('SyncSecrets 纯容器', () {
    test('默认构造全 null → isEmpty=true / hasSyncPassphrase=false', () {
      const s = SyncSecrets();
      expect(s.isEmpty, isTrue);
      expect(s.hasSyncPassphrase, isFalse);
      expect(s.webdavPassword, isNull);
      expect(s.syncPassphrase, isNull);
    });

    test('仅设 webdavPassword → isEmpty=false', () {
      const s = SyncSecrets(webdavPassword: 'pw123');
      expect(s.isEmpty, isFalse);
      expect(s.hasSyncPassphrase, isFalse);
    });

    test('设 syncPassphrase → hasSyncPassphrase=true', () {
      const s = SyncSecrets(syncPassphrase: 'passphrase');
      expect(s.hasSyncPassphrase, isTrue);
      expect(s.isEmpty, isFalse);
    });

    test('空串 syncPassphrase 视为未配置', () {
      const s = SyncSecrets(syncPassphrase: '');
      expect(s.hasSyncPassphrase, isFalse);
      expect(s.isEmpty, isTrue);
    });

    test('copyWith 仅变更指定字段', () {
      const a = SyncSecrets(webdavPassword: 'pw', syncPassphrase: 'sp');
      final b = a.copyWith(webdavPassword: 'new');
      expect(b.webdavPassword, 'new');
      expect(b.syncPassphrase, 'sp');
      final c = a.copyWith(syncPassphrase: 'new2');
      expect(c.webdavPassword, 'pw');
      expect(c.syncPassphrase, 'new2');
    });

    test('copyWith 传 null 清空字段', () {
      const a = SyncSecrets(webdavPassword: 'pw', syncPassphrase: 'sp');
      final b = a.copyWith(syncPassphrase: null);
      expect(b.webdavPassword, 'pw');
      expect(b.syncPassphrase, isNull);
      final c = a.copyWith(webdavPassword: null);
      expect(c.webdavPassword, isNull);
      expect(c.syncPassphrase, 'sp');
    });

    test('== / hashCode 基于两个字段', () {
      const a = SyncSecrets(webdavPassword: 'pw', syncPassphrase: 'sp');
      const b = SyncSecrets(webdavPassword: 'pw', syncPassphrase: 'sp');
      const c = SyncSecrets(webdavPassword: 'pw');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('MemorySyncSecretStore', () {
    test('read 默认空', () async {
      final store = MemorySyncSecretStore();
      final s = await store.read();
      expect(s.isEmpty, isTrue);
      expect(s.webdavPassword, isNull);
      expect(s.syncPassphrase, isNull);
    });

    test('write + read 回环', () async {
      final store = MemorySyncSecretStore();
      await store.write(
        const SyncSecrets(webdavPassword: 'pw', syncPassphrase: 'sp'),
      );
      final s = await store.read();
      expect(s.webdavPassword, 'pw');
      expect(s.syncPassphrase, 'sp');
    });

    test('clear 归零', () async {
      final store = MemorySyncSecretStore();
      await store.write(
        const SyncSecrets(webdavPassword: 'pw', syncPassphrase: 'sp'),
      );
      await store.clear();
      final s = await store.read();
      expect(s.isEmpty, isTrue);
    });

    test('两 store 值隔离', () async {
      final a = MemorySyncSecretStore();
      final b = MemorySyncSecretStore();
      await a.write(const SyncSecrets(webdavPassword: 'a-only'));
      expect((await a.read()).webdavPassword, 'a-only');
      expect((await b.read()).isEmpty, isTrue);
    });

    test('初始值构造', () async {
      final store = MemorySyncSecretStore(
        const SyncSecrets(webdavPassword: 'init'),
      );
      expect((await store.read()).webdavPassword, 'init');
    });
  });

  group('SecureSyncSecretStore', () {
    test('write 写入两键 / 键名正确', () async {
      final fake = FakeSecureStorage();
      final store = SecureSyncSecretStore(storage: fake);
      await store.write(
        const SyncSecrets(webdavPassword: 'pw', syncPassphrase: 'sp'),
      );

      expect(fake.writes.length, 2);
      expect(fake.writes[0]['key'], 'webdav_password');
      expect(fake.writes[0]['value'], 'pw');
      expect(fake.writes[1]['key'], 'sync_passphrase');
      expect(fake.writes[1]['value'], 'sp');
    });

    test('read 读两键 / 读取返回正确机密', () async {
      final fake = FakeSecureStorage({
        'webdav_password': 'pw',
        'sync_passphrase': 'sp',
      });
      final store = SecureSyncSecretStore(storage: fake);
      final s = await store.read();

      expect(s.webdavPassword, 'pw');
      expect(s.syncPassphrase, 'sp');
    });

    test('write 传 null → delete 对应键', () async {
      final fake = FakeSecureStorage({
        'webdav_password': 'old',
        'sync_passphrase': 'old',
      });
      final store = SecureSyncSecretStore(storage: fake);
      await store.write(const SyncSecrets()); // 全 null

      expect(fake.deletes, containsAll(['webdav_password', 'sync_passphrase']));
    });

    test('write 传空串 → delete 对应键', () async {
      final fake = FakeSecureStorage({'webdav_password': 'old'});
      final store = SecureSyncSecretStore(storage: fake);
      await store.write(
        const SyncSecrets(webdavPassword: '', syncPassphrase: 'only'),
      );

      expect(fake.deletes, contains('webdav_password'));
      expect(fake.writes.length, 1);
      expect(fake.writes[0]['key'], 'sync_passphrase');
      expect(fake.writes[0]['value'], 'only');
    });

    test('clear 删除两键', () async {
      final fake = FakeSecureStorage();
      final store = SecureSyncSecretStore(storage: fake);
      await store.clear();

      expect(fake.deletes, containsAll(['webdav_password', 'sync_passphrase']));
      expect(fake.deletes.where((k) => k == 'webdav_password').length, 1);
      expect(fake.deletes.where((k) => k == 'sync_passphrase').length, 1);
    });

    test('write 部分字段 null → 仅写有效字段、删 null 字段', () async {
      final fake = FakeSecureStorage({'sync_passphrase': 'keep'});
      final store = SecureSyncSecretStore(storage: fake);
      await store.write(const SyncSecrets(webdavPassword: 'new'));

      expect(fake.writes.length, 1);
      expect(fake.writes[0]['key'], 'webdav_password');
      expect(fake.deletes, contains('sync_passphrase'));
    });
  });
}
