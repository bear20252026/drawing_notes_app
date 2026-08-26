import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/auth_credentials.dart';
import '../domain/entities/auth_session.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/value_objects/auth_result.dart';

/// 认证仓库实现 — Infrastructure 层。
///
/// 使用 SharedPreferences 持久化认证数据，Argon2id 哈希密码。
class AuthRepositoryImpl implements AuthRepository {
  // ─────────────────── 常量 ───────────────────

  static const String _kHashedPasswordKey = 'auth_hashed_password';
  static const String _kSaltKey = 'auth_salt';
  static const String _kEnabledKey = 'auth_enabled';
  static const String _kFailedAttemptsKey = 'auth_failed_attempts';
  static const String _kLockUntilKey = 'auth_lock_until';
  static const String _kBiometricEnabledKey = 'auth_biometric_enabled';

  /// 锁定延迟阶梯（秒）
  static const List<Duration> _kLockDurations = [
    Duration.zero, // 失败 1 次
    Duration.zero, // 失败 2 次
    Duration(seconds: 30), // 失败 3 次
    Duration(minutes: 5), // 失败 4 次
    Duration(minutes: 30), // 失败 5 次+
  ];

  /// Argon2id 参数
  static const int _kArgon2Iterations = 3;
  static const int _kArgon2MemoryKiB = 65536;
  static const int _kArgon2Parallelism = 1;

  // ─────────────────── 状态 ───────────────────

  SharedPreferences? _prefs;
  bool _initialized = false;
  bool _enabled = false;
  bool _biometricEnabled = false;
  int _failedAttempts = 0;
  int? _lockUntilMs;
  bool _sessionAuthenticated = false;

  // ─────────────────── AuthRepository ───────────────────

  @override
  AuthSession get session {
    if (!_enabled) return const UnauthenticatedSession();
    if (_isLocked) return LockedSession(lockedUntilMs: _lockUntilMs);
    if (_sessionAuthenticated) return const AuthenticatedSession();
    return UnauthenticatedSession(failedAttempts: _failedAttempts);
  }

  @override
  bool get isConfigured => _enabled;

  @override
  Future<AuthResult> setCredentials(AuthCredentials credentials) async {
    await _ensureInitialized();

    if (_enabled) {
      return const AuthFailure(reason: AuthFailureReason.alreadyConfigured);
    }

    final password = _extractPassword(credentials);
    if (password == null || password.length < 6) {
      return const AuthFailure(reason: AuthFailureReason.invalidCredentials);
    }

    try {
      final salt = _generateSalt();
      final hash = await _hashPassword(password, salt);

      await _prefs!.setString(_kHashedPasswordKey, hash);
      await _prefs!.setString(_kSaltKey, base64Encode(salt));
      await _prefs!.setBool(_kEnabledKey, true);
      await _prefs!.setInt(_kFailedAttemptsKey, 0);
      await _prefs!.remove(_kLockUntilKey);

      _enabled = true;
      _failedAttempts = 0;
      _lockUntilMs = null;
      _sessionAuthenticated = true;
      return const AuthSuccess();
    } catch (e) {
      return const AuthFailure(reason: AuthFailureReason.unknown);
    }
  }

  @override
  Future<AuthResult> verifyCredentials(AuthCredentials credentials) async {
    await _ensureInitialized();

    if (!_enabled) {
      return const AuthFailure(reason: AuthFailureReason.notConfigured);
    }

    if (_isLocked) {
      return const AuthFailure(reason: AuthFailureReason.locked);
    }

    final password = _extractPassword(credentials);
    if (password == null) {
      return const AuthFailure(reason: AuthFailureReason.invalidCredentials);
    }

    try {
      final storedHash = _prefs!.getString(_kHashedPasswordKey);
      final saltBase64 = _prefs!.getString(_kSaltKey);
      if (storedHash == null || saltBase64 == null) {
        return const AuthFailure(reason: AuthFailureReason.notConfigured);
      }

      final salt = base64Decode(saltBase64);
      final hash = await _hashPassword(password, salt);

      if (hash == storedHash) {
        // 成功
        await _prefs!.setInt(_kFailedAttemptsKey, 0);
        _failedAttempts = 0;
        _lockUntilMs = null;
        await _prefs!.remove(_kLockUntilKey);
        _sessionAuthenticated = true;
        return const AuthSuccess();
      } else {
        // 失败
        await _recordFailedAttempt();
        return AuthFailure(
          reason: AuthFailureReason.invalidCredentials,
          remainingAttempts: 5 - _failedAttempts,
        );
      }
    } catch (e) {
      return const AuthFailure(reason: AuthFailureReason.unknown);
    }
  }

  @override
  Future<AuthResult> changeCredentials({
    required AuthCredentials oldCredentials,
    required AuthCredentials newCredentials,
  }) async {
    // 先验证旧凭证
    final verifyResult = await verifyCredentials(oldCredentials);
    if (verifyResult.isFailure) return verifyResult;

    // 设置新凭证
    return await setCredentials(newCredentials);
  }

  @override
  Future<AuthResult> removeCredentials(AuthCredentials credentials) async {
    // 先验证
    final verifyResult = await verifyCredentials(credentials);
    if (verifyResult.isFailure) return verifyResult;

    // 清除所有数据
    await _prefs!.remove(_kHashedPasswordKey);
    await _prefs!.remove(_kSaltKey);
    await _prefs!.setBool(_kEnabledKey, false);
    await _prefs!.remove(_kFailedAttemptsKey);
    await _prefs!.remove(_kLockUntilKey);
    await _prefs!.setBool(_kBiometricEnabledKey, false);

    _enabled = false;
    _biometricEnabled = false;
    _failedAttempts = 0;
    _lockUntilMs = null;
    _sessionAuthenticated = true;
    return const AuthSuccess();
  }

  @override
  void resetSession() {
    _sessionAuthenticated = false;
  }

  @override
  void markBiometricAuthenticated() {
    _sessionAuthenticated = true;
    _failedAttempts = 0;
    _lockUntilMs = null;
    _prefs?.setInt(_kFailedAttemptsKey, 0);
    _prefs?.remove(_kLockUntilKey);
  }

  // ─────────────────── 内部方法 ───────────────────

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    _prefs = await SharedPreferences.getInstance();
    _enabled = _prefs!.getBool(_kEnabledKey) ?? false;
    _biometricEnabled = _prefs!.getBool(_kBiometricEnabledKey) ?? false;
    _failedAttempts = _prefs!.getInt(_kFailedAttemptsKey) ?? 0;

    final lockUntilMs = _prefs!.getInt(_kLockUntilKey);
    if (lockUntilMs != null) {
      _lockUntilMs = lockUntilMs;
    }

    _initialized = true;
  }

  bool get _isLocked {
    if (_lockUntilMs == null) return false;
    return DateTime.now().millisecondsSinceEpoch < _lockUntilMs!;
  }

  Future<void> _recordFailedAttempt() async {
    _failedAttempts++;
    await _prefs!.setInt(_kFailedAttemptsKey, _failedAttempts);

    final lockIndex = min(_failedAttempts - 1, _kLockDurations.length - 1);
    final lockDuration = _kLockDurations[lockIndex];

    if (lockDuration > Duration.zero) {
      _lockUntilMs = DateTime.now().add(lockDuration).millisecondsSinceEpoch;
      await _prefs!.setInt(_kLockUntilKey, _lockUntilMs!);
    }
  }

  String? _extractPassword(AuthCredentials credentials) {
    if (credentials is PasswordCredentials) return credentials.password;
    if (credentials is PinCredentials) return credentials.pin;
    return null;
  }

  List<int> _generateSalt() {
    final rng = Random.secure();
    return List<int>.generate(32, (_) => rng.nextInt(256));
  }

  Future<String> _hashPassword(String password, List<int> salt) async {
    final algorithm = Argon2id(
      parallelism: _kArgon2Parallelism,
      memory: _kArgon2MemoryKiB,
      iterations: _kArgon2Iterations,
      hashLength: 32,
    );

    final secretKey = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    final hashBytes = await secretKey.extractBytes();
    return '${base64Encode(salt)}:${base64Encode(hashBytes)}';
  }
}
