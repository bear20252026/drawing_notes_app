// ============================================================================
// app_lock_service.dart —— 应用启动锁服务（2026-09-01）
// ============================================================================
//
// 应用级冷启动门 + 切后台回锁的单一事实来源：
// - PIN 永不明文落盘：随机盐 + SHA-256 哈希后存 shared_preferences；
// - 校验用恒定时间比较，避免时序侧信道；
// - 「是否已配置」是唯一持久状态，加锁/解锁的瞬时状态由 UI 层（AppLockGate）
//   持有——存储层不感知「此刻是否锁定」。
//
// 设计决策（用户 2026-09-01 拍板）：
// - 在设置里自设 PIN（4 位数字，iOS 锁屏同款密码盘）；
// - 冷启动 + 切后台回来都要锁（AppLockGate 负责生命周期监听）；
// - 首版无找回机制：忘记 PIN 只能卸载重装（如实提示，不做后门）。

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用启动锁服务。
///
/// 用法（组合根装配一次，向下注入）：
/// ```dart
/// final appLock = AppLockService();
/// await appLock.load();          // 启动时读取已配置状态
/// appLock.isConfigured;          // 是否已设置 PIN
/// await appLock.verify(pin);     // 解锁前校验
/// await appLock.setPin(pin);     // 设置/修改 PIN
/// await appLock.disable();       // 关闭应用锁
/// ```
class AppLockService extends ChangeNotifier {
  AppLockService({Future<SharedPreferences> Function()? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _kPinHashKey = 'app_lock.pin_hash';
  static const _kSaltKey = 'app_lock.salt';

  final Future<SharedPreferences> Function() _preferencesLoader;

  bool _configured = false;

  /// 是否已设置应用锁 PIN。
  bool get isConfigured => _configured;

  /// 启动时读取持久化状态（不读取时 [isConfigured] 恒为 false）。
  Future<void> load() async {
    final prefs = await _preferencesLoader();
    _configured = prefs.getString(_kPinHashKey) != null;
    notifyListeners();
  }

  /// 设置（或覆盖）PIN。调用方需自行保证身份（修改前先 [verify] 旧 PIN）。
  Future<void> setPin(String pin) async {
    assert(pin.isNotEmpty, 'PIN 不能为空');
    final prefs = await _preferencesLoader();
    final salt = _newSalt();
    await prefs.setString(_kSaltKey, salt);
    await prefs.setString(_kPinHashKey, _hash(pin, salt));
    _configured = true;
    notifyListeners();
  }

  /// 校验 PIN；未配置时恒为 false。
  Future<bool> verify(String pin) async {
    if (!_configured) return false;
    final prefs = await _preferencesLoader();
    final salt = prefs.getString(_kSaltKey);
    final stored = prefs.getString(_kPinHashKey);
    if (salt == null || stored == null) return false;
    return _constantTimeEquals(_hash(pin, salt), stored);
  }

  /// 关闭应用锁（清除持久化 PIN）。
  Future<void> disable() async {
    final prefs = await _preferencesLoader();
    await prefs.remove(_kPinHashKey);
    await prefs.remove(_kSaltKey);
    _configured = false;
    notifyListeners();
  }

  /// 16 字节加密安全随机盐（hex 编码）。
  String _newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// 恒定时间字符串比较：无论是否相等耗时一致，防时序侧信道。
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
