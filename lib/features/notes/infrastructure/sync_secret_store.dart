// 同步机密存储（P4-C1）：抽象容器 + 注入式实现。
//
// 把 WebDAV 认证密码与 E2E 同步口令统一收进 OS 凭据库（flutter_secure_storage），
// 与非机密配置（baseUrl/username/syncSalt）分离。
// 机密存储通过接口注入，便于测试替换。

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 同步所需的机密（不可变值类型）。
///
/// 仅承载机密字段；非机密配置（baseUrl/username/syncSalt）留在 WebDavSyncConfig。
class SyncSecrets {
  const SyncSecrets({
    this.webdavPassword,
    this.syncPassphrase,
  });

  /// WebDAV 认证密码。
  final String? webdavPassword;

  /// 端到端加密口令。
  final String? syncPassphrase;

  /// 是否已配置 E2E 同步口令。
  bool get hasSyncPassphrase =>
      syncPassphrase != null && syncPassphrase!.isNotEmpty;

  /// 是否为空（两类机密均未配置）。
  bool get isEmpty =>
      (webdavPassword == null || webdavPassword!.isEmpty) &&
      (syncPassphrase == null || syncPassphrase!.isEmpty);

  /// 不可变更新：返回仅变更指定字段的新实例。
  ///
  /// 传入 `null` 表示清空该字段（配合 store 的 delete 语义清空对应键）。
  SyncSecrets copyWith({
    Object? webdavPassword = _unset,
    Object? syncPassphrase = _unset,
  }) =>
      SyncSecrets(
        webdavPassword: identical(webdavPassword, _unset)
            ? this.webdavPassword
            : webdavPassword as String?,
        syncPassphrase: identical(syncPassphrase, _unset)
            ? this.syncPassphrase
            : syncPassphrase as String?,
      );

  /// copyWith 默认值哨兵：区分「未传参（保留原值）」与「传 null（清空）」。
  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncSecrets &&
          runtimeType == other.runtimeType &&
          webdavPassword == other.webdavPassword &&
          syncPassphrase == other.syncPassphrase;

  @override
  int get hashCode => Object.hash(webdavPassword, syncPassphrase);

  @override
  String toString() =>
      'SyncSecrets(hasPassword: ${webdavPassword != null && webdavPassword!.isNotEmpty}, hasSyncPassphrase: $hasSyncPassphrase)';
}

/// 同步机密存储抽象。
///
/// 实现类负责把机密持久化到 OS 凭据库（或内存）。
abstract class SyncSecretStore {
  /// 读取机密（无配置则返回字段为 null 的实例）。
  Future<SyncSecrets> read();

  /// 写入机密；传入 null 或空串应清空对应字段。
  Future<void> write(SyncSecrets secrets);

  /// 清空全部机密。
  Future<void> clear();
}

/// 基于 FlutterSecureStorage 的机密存储实现。
///
/// 把机密存入 OS 凭据库（iOS Keychain / Android Keystore 等）。
class SecureSyncSecretStore implements SyncSecretStore {
  SecureSyncSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyWebdavPassword = 'webdav_password';
  static const _keySyncPassphrase = 'sync_passphrase';

  @override
  Future<SyncSecrets> read() async {
    final results = await _storage.readAll();
    return SyncSecrets(
      webdavPassword: results[_keyWebdavPassword],
      syncPassphrase: results[_keySyncPassphrase],
    );
  }

  @override
  Future<void> write(SyncSecrets secrets) async {
    // 传 null 或空串 → 删除该键。
    if (secrets.webdavPassword == null || secrets.webdavPassword!.isEmpty) {
      await _storage.delete(key: _keyWebdavPassword);
    } else {
      await _storage.write(key: _keyWebdavPassword, value: secrets.webdavPassword);
    }

    if (secrets.syncPassphrase == null || secrets.syncPassphrase!.isEmpty) {
      await _storage.delete(key: _keySyncPassphrase);
    } else {
      await _storage.write(key: _keySyncPassphrase, value: secrets.syncPassphrase);
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _keyWebdavPassword);
    await _storage.delete(key: _keySyncPassphrase);
  }
}

/// 内存机密存储实现（供测试替身或临时会话）。
class MemorySyncSecretStore implements SyncSecretStore {
  MemorySyncSecretStore([SyncSecrets? initial]) : _secrets = initial ?? const SyncSecrets();

  SyncSecrets _secrets;

  @override
  Future<SyncSecrets> read() async => _secrets;

  @override
  Future<void> write(SyncSecrets secrets) async {
    _secrets = secrets;
  }

  @override
  Future<void> clear() async {
    _secrets = const SyncSecrets();
  }
}
