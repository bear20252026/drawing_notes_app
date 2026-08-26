import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用级密码锁定服务。
///
/// 功能：
/// - 设置/修改/取消应用启动密码
/// - Argon2id 哈希存储（复用 EncryptionService 的 KDF）
/// - 连续失败阶梯锁定（复用 password_disk.dart 的锁定机制）
/// - 支持生物识别（通过 [useBiometric] 标志）
///
/// 设计说明：
/// - 密码哈希存储在 SharedPreferences 中（salt + hash）
/// - 启动时由 AuthGuard 检查是否需要验证
/// - 连续失败次数和锁定结束时间持久化
class AppLockService extends ChangeNotifier {
  AppLockService._();

  static final AppLockService instance = AppLockService._();

  // ─────────────────── 常量 ───────────────────

  /// SharedPreferences keys
  static const String _kHashedPasswordKey = 'app_lock_hashed_password';
  static const String _kSaltKey = 'app_lock_salt';
  static const String _kEnabledKey = 'app_lock_enabled';
  static const String _kFailedAttemptsKey = 'app_lock_failed_attempts';
  static const String _kLockUntilKey = 'app_lock_lock_until';
  static const String _kBiometricEnabledKey = 'app_lock_biometric_enabled';

  /// 连续失败锁定阈值（复用 password_disk.dart 的阶梯锁定机制）
  static const int maxFailedAttempts = 5;

  /// 锁定延迟阶梯（秒）：第 1-2 次不锁，第 3 次锁 30s，第 4 次锁 5min，第 5 次锁 30min
  static const List<Duration> _kLockDurations = [
    Duration.zero,        // 失败 1 次
    Duration.zero,        // 失败 2 次
    Duration(seconds: 30),    // 失败 3 次
    Duration(minutes: 5),     // 失败 4 次
    Duration(minutes: 30),    // 失败 5 次+
  ];

  /// Argon2id 参数（与 EncryptionService 一致）
  static const int _kArgon2Iterations = 3;
  static const int _kArgon2MemoryKiB = 65536; // 64 MiB
  static const int _kArgon2Parallelism = 1;

  // ─────────────────── 状态 ───────────────────

  SharedPreferences? _prefs;
  bool _initialized = false;
  bool _enabled = false;
  bool _biometricEnabled = false;
  int _failedAttempts = 0;
  DateTime? _lockUntil;

  /// 是否已初始化
  bool get initialized => _initialized;

  /// 是否启用了应用锁
  bool get enabled => _enabled;

  /// 是否启用了生物识别
  bool get biometricEnabled => _biometricEnabled;

  /// 当前失败次数
  int get failedAttempts => _failedAttempts;

  /// 锁定截止时间
  DateTime? get lockUntil => _lockUntil;

  /// 当前是否处于锁定状态
  bool get isLocked {
    if (_lockUntil == null) return false;
    return DateTime.now().isBefore(_lockUntil!);
  }

  /// 距离解锁还剩多少时间
  Duration get remainingLockTime {
    if (!isLocked) return Duration.zero;
    return _lockUntil!.difference(DateTime.now());
  }

  /// 是否需要验证（已启用且尚未在本次会话中通过验证）
  bool _sessionAuthenticated = false;
  bool get requiresAuth => _enabled && !_sessionAuthenticated;

  // ─────────────────── 初始化 ───────────────────

  /// 初始化服务，从 SharedPreferences 加载状态
  Future<void> initialize() async {
    if (_initialized) return;

    _prefs = await SharedPreferences.getInstance();
    _enabled = _prefs!.getBool(_kEnabledKey) ?? false;
    _biometricEnabled = _prefs!.getBool(_kBiometricEnabledKey) ?? false;
    _failedAttempts = _prefs!.getInt(_kFailedAttemptsKey) ?? 0;

    final lockUntilMs = _prefs!.getInt(_kLockUntilKey);
    if (lockUntilMs != null) {
      _lockUntil = DateTime.fromMillisecondsSinceEpoch(lockUntilMs);
    }

    // 如果锁定已过期，重置失败计数
    if (!isLocked && _failedAttempts > 0) {
      // 保持失败次数（阶梯机制靠它计算下次延迟）
    }

    _initialized = true;
    notifyListeners();
  }

  // ─────────────────── 密码管理 ───────────────────

  /// 设置应用密码
  ///
  /// [password] 明文密码，至少 6 位
  /// 返回是否设置成功
  Future<bool> setPassword(String password) async {
    if (password.length < 6) {
      throw ArgumentError('密码至少 6 位');
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
      _lockUntil = null;
      _sessionAuthenticated = true; // 设置后立即验证通过
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[AppLockService] setPassword 失败: $e');
      return false;
    }
  }

  /// 修改应用密码
  ///
  /// 需要先验证旧密码
  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 6) {
      throw ArgumentError('新密码至少 6 位');
    }

    // 先验证旧密码
    if (!await verifyPassword(oldPassword)) {
      return false;
    }

    // 设置新密码
    return await setPassword(newPassword);
  }

  /// 取消应用密码
  ///
  /// 需要验证当前密码
  Future<bool> removePassword(String password) async {
    if (!await verifyPassword(password)) {
      return false;
    }

    await _prefs!.remove(_kHashedPasswordKey);
    await _prefs!.remove(_kSaltKey);
    await _prefs!.setBool(_kEnabledKey, false);
    await _prefs!.remove(_kFailedAttemptsKey);
    await _prefs!.remove(_kLockUntilKey);

    _enabled = false;
    _biometricEnabled = false;
    _failedAttempts = 0;
    _lockUntil = null;
    _sessionAuthenticated = true;
    await _prefs!.setBool(_kBiometricEnabledKey, false);
    notifyListeners();
    return true;
  }

  /// 验证密码
  ///
  /// 返回 true 表示密码正确，false 表示错误
  /// 错误时自动增加失败计数并可能触发锁定
  Future<bool> verifyPassword(String password) async {
    if (isLocked) return false;

    final storedHash = _prefs!.getString(_kHashedPasswordKey);
    final saltBase64 = _prefs!.getString(_kSaltKey);
    if (storedHash == null || saltBase64 == null) return false;

    try {
      final salt = base64Decode(saltBase64);
      final hash = await _hashPassword(password, salt);

      if (hash == storedHash) {
        // 成功：重置失败计数
        await _prefs!.setInt(_kFailedAttemptsKey, 0);
        _failedAttempts = 0;
        _lockUntil = null;
        await _prefs!.remove(_kLockUntilKey);
        _sessionAuthenticated = true;
        notifyListeners();
        return true;
      } else {
        // 失败：增加计数并可能触发锁定
        await _recordFailedAttempt();
        return false;
      }
    } catch (e) {
      debugPrint('[AppLockService] verifyPassword 异常: $e');
      return false;
    }
  }

  /// 通过生物识别验证（标记为已验证）
  ///
  /// 调用方负责实际的生物识别弹窗
  void markBiometricAuthenticated() {
    _sessionAuthenticated = true;
    // 重置失败计数
    _failedAttempts = 0;
    _lockUntil = null;
    _prefs?.setInt(_kFailedAttemptsKey, 0);
    _prefs?.remove(_kLockUntilKey);
    notifyListeners();
  }

  /// 重置本次会话验证状态（用于应用回到前台等场景）
  void resetSession() {
    _sessionAuthenticated = false;
    notifyListeners();
  }

  // ─────────────────── 生物识别 ───────────────────

  /// 切换生物识别
  Future<void> setBiometricEnabled(bool enabled) async {
    _biometricEnabled = enabled;
    await _prefs!.setBool(_kBiometricEnabledKey, enabled);
    notifyListeners();
  }

  // ─────────────────── 内部方法 ───────────────────

  /// 记录失败尝试并触发阶梯锁定
  Future<void> _recordFailedAttempt() async {
    _failedAttempts++;
    await _prefs!.setInt(_kFailedAttemptsKey, _failedAttempts);

    // 计算锁定时间
    final lockIndex = min(_failedAttempts - 1, _kLockDurations.length - 1);
    final lockDuration = _kLockDurations[lockIndex];

    if (lockDuration > Duration.zero) {
      _lockUntil = DateTime.now().add(lockDuration);
      await _prefs!.setInt(
        _kLockUntilKey,
        _lockUntil!.millisecondsSinceEpoch,
      );
    }

    notifyListeners();
  }

  /// 生成 32 字节随机盐
  List<int> _generateSalt() {
    final rng = Random.secure();
    return List<int>.generate(32, (_) => rng.nextInt(256));
  }

  /// 使用 Argon2id 哈希密码（与 EncryptionService 参数一致）
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

    // 输出格式：base64(salt):base64(hash)
    return '${base64Encode(salt)}:${base64Encode(hashBytes)}';
  }

  /// 检查生物识别是否可用（平台级别）
  static Future<bool> isBiometricAvailable() async {
    try {
      // 使用 local_auth 的 canCheckBiometrics
      // 如果未集成 local_auth 则返回 false
      // 注意：需要在 pubspec.yaml 中添加 local_auth 依赖
      return false; // 暂时返回 false，后续集成 local_auth 后启用
    } catch (e) {
      return false;
    }
  }
}
