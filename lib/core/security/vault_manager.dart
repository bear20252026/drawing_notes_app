// vault_manager.dart — Vault 统一管理器：KEK 持久化 + 密钥轮换 + 审计日志（2026-08-24）。
//
// 架构：
// - VaultKeyManager：KEK 持久化（flutter_secure_storage）+ 密钥轮换
// - VaultKeyService：DEK + 签名密钥对加密存储
// - AuditLogStore：Hash chain 审计日志持久化
// - SecureBytes：安全内存管理（Finalizer 清零）
//
// 生命周期：
// 1. initialize(password) — 首次设置密码 → 生成 KEK/DEK/签名密钥对
// 2. unlock(password) — 验证密码 → 解锁 Vault → 获取密钥材料
// 3. rotateKeys(oldPassword, newPassword) — 修改密码 → KEK 轮换 → 重包裹所有密钥
// 4. lock() — 清零内存中的密钥材料
//
// 安全要求：
// - KEK 仅在内存中以 SecureBytes 持有
// - DEK 明文仅在加密/解密操作期间存在
// - 轮换过程原子性：失败时回滚
// - 审计日志防篡改：Hash chain + 加密存储

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'audit_log_store.dart';
import 'secure_bytes.dart';
import 'vault_key_manager.dart';
import 'vault_key_service.dart';

/// Vault 统一管理器。
class VaultManager {
  VaultManager({
    required this.vaultDirectory,
    FlutterSecureStorage? secureStorage,
  }) : _keyManager = VaultKeyManager(secureStorage: secureStorage);

  final Directory vaultDirectory;
  final VaultKeyManager _keyManager;

  VaultKeyService? _keyService;
  AuditLogStore? _auditLog;
  bool _initialized = false;

  /// 是否已初始化。
  bool get isInitialized => _initialized;

  /// 是否已解锁。
  bool get isUnlocked => _keyManager.isUnlocked;

  /// VaultKeyManager 实例。
  VaultKeyManager get keyManager => _keyManager;

  /// 审计日志存储。
  AuditLogStore? get auditLog => _auditLog;

  /// 初始化 Vault（首次设置密码）。
  ///
  /// 流程：
  /// 1. 生成 KEK（Argon2id 从密码派生）
  /// 2. 生成主 DEK + 签名密钥对
  /// 3. 用 KEK 包裹 DEK + 签名私钥
  /// 4. 存储到 flutter_secure_storage（KEK）+ Vault（包裹的密钥）
  /// 5. 初始化审计日志
  Future<void> initialize(String password) async {
    if (_initialized) {
      throw StateError('Vault 已初始化');
    }

    // 创建目录。
    await vaultDirectory.create(recursive: true);

    // 初始化密钥服务。
    final keyStore = _createKeyStore();
    _keyService = VaultKeyService(
      keyManager: _keyManager,
      vaultStore: keyStore,
    );

    // 生成并存储密钥。
    final keySet = await _keyService!.initializeKeys(password);

    // 初始化审计日志（使用 DEK 派生的审计密钥）。
    final auditKey = await _deriveAuditKey(keySet.dek);
    _auditLog = AuditLogStore(
      directory: Directory('${vaultDirectory.path}/audit'),
      encryptionKey: auditKey,
    );
    await _auditLog!.initialize();

    // 记录初始化事件。
    await _auditLog!.append(
      action: 'vault.initialize',
      content: 'Vault 初始化完成',
    );

    keySet.dispose();
    _initialized = true;
  }

  /// 解锁 Vault（验证密码）。
  ///
  /// 流程：
  /// 1. 验证密码 → 解锁 KEK
  /// 2. 解包裹 DEK + 签名密钥对
  /// 3. 加载并验证审计日志 Hash chain
  Future<VaultUnlockResult> unlock(String password) async {
    // 初始化密钥服务（如果尚未初始化）。
    _keyService ??= VaultKeyService(
      keyManager: _keyManager,
      vaultStore: _createKeyStore(),
    );

    // 解锁密钥。
    final keySet = await _keyService!.unlockKeys(password);

    // 初始化审计日志。
    final auditKey = await _deriveAuditKey(keySet.dek);
    _auditLog = AuditLogStore(
      directory: Directory('${vaultDirectory.path}/audit'),
      encryptionKey: auditKey,
    );
    await _auditLog!.initialize();

    // 验证审计日志完整性。
    final chainValid = await _auditLog!.verifyChainIntegrity();

    // 记录解锁事件。
    await _auditLog!.append(
      action: 'vault.unlock',
      content: 'Vault 解锁成功',
    );

    _initialized = true;

    return VaultUnlockResult(
      dek: keySet.dek,
      signingKeyPair: keySet.signingKeyPair,
      auditLogValid: chainValid,
    );
  }

  /// KEK 轮换（修改密码）。
  ///
  /// 流程：
  /// 1. 验证旧密码
  /// 2. 从新密码派生新 KEK
  /// 3. 用旧 KEK 解包裹所有密钥，用新 KEK 重新包裹
  /// 4. 原子提交：更新 flutter_secure_storage
  /// 5. 清零旧 KEK
  Future<void> rotateKeys({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (_keyService == null) {
      throw StateError('Vault 未解锁——先调用 unlock');
    }

    // 记录轮换开始。
    await _auditLog?.append(
      action: 'vault.rotate.begin',
      content: 'KEK 轮换开始',
    );

    try {
      await _keyService!.rotateKeys(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );

      // 记录轮换成功。
      await _auditLog?.append(
        action: 'vault.rotate.success',
        content: 'KEK 轮换完成',
      );
    } catch (e) {
      // 记录轮换失败。
      await _auditLog?.append(
        action: 'vault.rotate.failed',
        content: 'KEK 轮换失败: $e',
      );
      rethrow;
    }
  }

  /// 锁定 Vault（清零内存中的密钥材料）。
  void lock() {
    _auditLog?.append(
      action: 'vault.lock',
      content: 'Vault 锁定',
    ).then((_) {
      _auditLog?.dispose();
      _auditLog = null;
    });

    _keyManager.lock();
    _initialized = false;
  }

  /// 重置 Vault（清除所有持久化数据——危险操作）。
  Future<void> reset() async {
    lock();
    await _keyManager.reset();

    // 删除 Vault 目录。
    if (await vaultDirectory.exists()) {
      await vaultDirectory.delete(recursive: true);
    }
  }

  /// 获取审计日志条目。
  Future<List<AuditLogEntry>> getAuditEntries({
    int? startTime,
    int? endTime,
    int? limit,
  }) async {
    if (_auditLog == null) {
      throw StateError('Vault 未解锁——审计日志不可用');
    }
    return _auditLog!.getEntries(
      startTime: startTime,
      endTime: endTime,
      limit: limit,
    );
  }

  /// 验证审计日志完整性。
  Future<bool> verifyAuditIntegrity() async {
    if (_auditLog == null) {
      throw StateError('Vault 未解锁——审计日志不可用');
    }
    return _auditLog!.verifyChainIntegrity();
  }

  /// 从 DEK 派生审计日志加密密钥（HKDF-SHA256）。
  Future<SecureBytes> _deriveAuditKey(SecureBytes dek) async {
    return dek.withBytes((dekBytes) async {
      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
      final auditKey = await hkdf.deriveKey(
        secretKey: SecretKey(dekBytes),
        info: utf8.encode('vault|audit|v1'),
      );
      final bytes = await auditKey.extractBytes();
      return SecureBytes(bytes);
    });
  }

  /// 创建密钥存储实例。
  VaultKeyStore _createKeyStore() {
    // 使用内存存储作为临时实现——实际应使用 EncryptedVault。
    // EncryptedVault 需要密钥才能初始化，形成循环依赖。
    // 解决方案：使用独立的加密存储或延迟初始化。
    return _InMemoryVaultKeyStore();
  }
}

/// Vault 解锁结果。
class VaultUnlockResult {
  const VaultUnlockResult({
    required this.dek,
    required this.signingKeyPair,
    required this.auditLogValid,
  });

  final SecureBytes dek;
  final SimpleKeyPair signingKeyPair;
  final bool auditLogValid;

  /// 清零密钥材料。
  void dispose() {
    dek.dispose();
  }
}

/// 内存中的密钥存储（临时实现——用于测试和初始化阶段）。
class _InMemoryVaultKeyStore implements VaultKeyStore {
  final Map<String, Uint8List> _store = {};

  @override
  Future<void> storeKey(String keyId, List<int> data) async {
    _store[keyId] = Uint8List.fromList(data);
  }

  @override
  Future<Uint8List?> readKey(String keyId) async {
    return _store[keyId];
  }

  @override
  Future<void> deleteKey(String keyId) async {
    _store.remove(keyId);
  }
}
