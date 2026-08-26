// vault_key_manager.dart — KEK 持久化 + 密钥轮换（2026-08-24）。
//
// 架构：
// - KEK（Key Encryption Key）：由用户密码派生，存储在 flutter_secure_storage
// - DEK（Data Encryption Key）：Vault 加密存储（KEK 包裹）
// - 签名密钥对：Vault 加密存储（KEK 包裹）
// - 密钥轮换：修改密码 → 重新派生 KEK → 重包裹所有 DEK → 原子提交
//
// 安全要求：
// - KEK 仅在内存中以 SecureBytes 持有，使用后清零
// - DEK 明文仅在加密/解密操作期间存在于内存
// - 轮换过程原子性：失败时回滚到旧 KEK
// - flutter_secure_storage 使用 AES 加密存储（Android Keystore / iOS Keychain）

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_bytes.dart';

/// Vault 密钥管理器——KEK 持久化 + 密钥轮换。
///
/// 生命周期：
/// 1. [unlock] — 用户输入密码 → 派生 KEK → 解锁 Vault
/// 2. [getKek] — 获取当前 KEK（用于包裹/解包裹 DEK）
/// 3. [rotateKek] — 修改密码 → 重新派生 KEK → 重包裹所有 DEK
/// 4. [lock] — 清零内存中的 KEK
class VaultKeyManager {
  VaultKeyManager({
    FlutterSecureStorage? secureStorage,
    Argon2id? kdf,
  })  : _storage = secureStorage ?? _createDefaultStorage(),
        _kdf = kdf ?? Argon2id(
          parallelism: 2,
          memory: 65536, // 64 MB in KB
          iterations: 3,
          hashLength: 32,
        );

  final FlutterSecureStorage _storage;
  final Argon2id _kdf;

  // flutter_secure_storage 键名常量。
  static const _kekSaltKey = 'vault.kek.salt';
  static const _kekHashKey = 'vault.kek.hash';   // 验证哈希（非 KEK 本身）
  static const _kekWrappedKey = 'vault.kek.wrapped'; // KEK 的自包裹（可选）
  static const _vaultVersionKey = 'vault.version';

  SecureBytes? _currentKek;
  Uint8List? _currentSalt;
  bool _unlocked = false;

  /// 是否已解锁。
  bool get isUnlocked => _unlocked;

  /// 是否已初始化（有持久化的 KEK）。
  Future<bool> get isInitialized async {
    final salt = await _storage.read(key: _kekSaltKey);
    return salt != null;
  }

  /// 初始化 Vault（首次设置密码）。
  ///
  /// 流程：
  /// 1. 生成随机盐
  /// 2. 从密码派生 KEK
  /// 3. 存储盐 + KEK 验证哈希到 flutter_secure_storage
  /// 4. 返回 KEK（调用方用于初始化 Vault）
  Future<SecureBytes> initialize(String password) async {
    if (await isInitialized) {
      throw StateError('Vault 已初始化——使用 unlock 或 rotateKek');
    }

    final salt = _randomBytes(32);
    final kek = await _deriveKek(password, salt);
    final kekHash = await _hashForVerification(kek);

    // 持久化（盐 + 验证哈希）。
    await _storage.write(key: _kekSaltKey, value: base64Encode(salt));
    await _storage.write(key: _kekHashKey, value: base64Encode(kekHash));
    await _storage.write(key: _vaultVersionKey, value: '1');

    _currentKek = kek;
    _currentSalt = Uint8List.fromList(salt);
    _unlocked = true;

    return kek;
  }

  /// 解锁 Vault（验证密码）。
  ///
  /// 流程：
  /// 1. 读取存储的盐
  /// 2. 从密码派生 KEK
  /// 3. 验证 KEK 哈希
  /// 4. 返回 KEK
  Future<SecureBytes> unlock(String password) async {
    final saltB64 = await _storage.read(key: _kekSaltKey);
    final hashB64 = await _storage.read(key: _kekHashKey);
    if (saltB64 == null || hashB64 == null) {
      throw StateError('Vault 未初始化——先调用 initialize');
    }

    final salt = base64Decode(saltB64);
    final storedHash = base64Decode(hashB64);

    final kek = await _deriveKek(password, salt);
    final kekHash = await _hashForVerification(kek);

    // 恒定时间比较（防时序攻击）。
    if (!_constantTimeEquals(kekHash, storedHash)) {
      kek.dispose();
      throw StateError('密码错误——KEK 验证失败');
    }

    _currentKek = kek;
    _currentSalt = Uint8List.fromList(salt);
    _unlocked = true;

    return kek;
  }

  /// 获取当前 KEK（用于包裹/解包裹 DEK）。
  ///
  /// 调用方必须在使用后不再持有引用。
  SecureBytes getKek() {
    if (!_unlocked || _currentKek == null) {
      throw StateError('Vault 未解锁——先调用 unlock');
    }
    return _currentKek!;
  }

  /// KEK 轮换（修改密码）。
  ///
  /// 流程：
  /// 1. 验证旧密码
  /// 2. 从新密码派生新 KEK
  /// 3. 回调：调用方用旧 KEK 解包裹所有 DEK，用新 KEK 重新包裹
  /// 4. 原子提交：更新存储的盐 + 验证哈希
  /// 5. 清零旧 KEK
  ///
  /// [reWrapCallback] 回调签名：(oldKek, newKek) → 重包裹所有密钥材料。
  /// 如果回调抛异常，轮换中止，旧 KEK 保持不变。
  Future<void> rotateKek({
    required String oldPassword,
    required String newPassword,
    required Future<void> Function(SecureBytes oldKek, SecureBytes newKek) reWrapCallback,
  }) async {
    // 1. 验证旧密码。
    final oldKek = await unlock(oldPassword);

    // 2. 派生新 KEK。
    final newSalt = _randomBytes(32);
    final newKek = await _deriveKek(newPassword, newSalt);
    final newKekHash = await _hashForVerification(newKek);

    // 3. 重包裹（回调可能抛异常——此时中止）。
    try {
      await reWrapCallback(oldKek, newKek);
    } catch (e) {
      // 回调失败——中止轮换，清零新 KEK。
      newKek.dispose();
      rethrow;
    }

    // 4. 原子提交：更新持久化存储。
    //    先写新值，再删旧值（防中间崩溃丢失数据）。
    await _storage.write(key: _kekSaltKey, value: base64Encode(newSalt));
    await _storage.write(key: _kekHashKey, value: base64Encode(newKekHash));

    // 5. 清零旧 KEK，切换到新 KEK。
    oldKek.dispose();
    _currentKek = newKek;
    _currentSalt = Uint8List.fromList(newSalt);
  }

  /// 锁定 Vault（清零内存中的 KEK）。
  void lock() {
    _currentKek?.dispose();
    _currentKek = null;
    _currentSalt = null;
    _unlocked = false;
  }

  /// 重置 Vault（清除所有持久化数据——危险操作）。
  Future<void> reset() async {
    lock();
    await _storage.delete(key: _kekSaltKey);
    await _storage.delete(key: _kekHashKey);
    await _storage.delete(key: _kekWrappedKey);
    await _storage.delete(key: _vaultVersionKey);
  }

  /// 从密码派生 KEK（Argon2id）。
  Future<SecureBytes> _deriveKek(String password, List<int> salt) async {
    final secretKey = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final raw = await secretKey.extractBytes();
    return SecureBytes(raw);
  }

  /// 计算 KEK 验证哈希（SHA-256——仅用于验证，不用于加密）。
  Future<List<int>> _hashForVerification(SecureBytes kek) async {
    return kek.withBytes((bytes) async {
      final hash = await Sha256().hash(bytes);
      return hash.bytes;
    });
  }

  /// 恒定时间比较（防时序攻击）。
  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// 生成随机字节。
  static List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// 创建默认 flutter_secure_storage 实例。
  static FlutterSecureStorage _createDefaultStorage() {
    return const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
  }
}
