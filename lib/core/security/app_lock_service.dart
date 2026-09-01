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
// - 在设置里自设 PIN（iOS 锁屏同款密码盘，批次②起长度可自定义 4–12 位）；
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
/// appLock.pinLength;             // PIN 长度（4–12，批次②自定义）
/// await appLock.verify(pin);     // 解锁前校验
/// await appLock.setPin(pin);     // 设置/修改 PIN（长度随 PIN 记录）
/// await appLock.disable();       // 关闭应用锁
/// ```
class AppLockService extends ChangeNotifier {
  AppLockService({Future<SharedPreferences> Function()? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _kPinHashKey = 'app_lock.pin_hash';
  static const _kSaltKey = 'app_lock.salt';
  static const _kPinLengthKey = 'app_lock.pin_length';

  /// PIN 长度边界（批次②：自定义 4–12 位）。
  static const int minPinLength = 4;
  static const int maxPinLength = 12;
  static const int defaultPinLength = 4;

  final Future<SharedPreferences> Function() _preferencesLoader;

  bool _configured = false;
  int _pinLength = defaultPinLength;

  /// 是否已设置应用锁 PIN。
  bool get isConfigured => _configured;

  /// 当前 PIN 长度（未配置时为默认值 4；密码盘圆点数/桌面输入框
  /// maxLength 均以它为准）。
  int get pinLength => _pinLength;

  /// 启动时读取持久化状态（不读取时 [isConfigured] 恒为 false）。
  Future<void> load() async {
    final prefs = await _preferencesLoader();
    _configured = prefs.getString(_kPinHashKey) != null;
    _pinLength = prefs.getInt(_kPinLengthKey) ?? defaultPinLength;
    notifyListeners();
  }

  /// 设置（或覆盖）PIN，长度随 PIN 记录（批次②：4–12 位）。
  /// 调用方需自行保证身份（修改前先 [verify] 旧 PIN）。
  Future<void> setPin(String pin) async {
    assert(pin.isNotEmpty, 'PIN 不能为空');
    assert(
      pin.length >= minPinLength && pin.length <= maxPinLength,
      'PIN 长度须在 $minPinLength–$maxPinLength 位之间',
    );
    final prefs = await _preferencesLoader();
    final salt = _newSalt();
    await prefs.setString(_kSaltKey, salt);
    await prefs.setString(_kPinHashKey, _hash(pin, salt));
    await prefs.setInt(_kPinLengthKey, pin.length);
    _configured = true;
    _pinLength = pin.length;
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
    await prefs.remove(_kPinLengthKey);
    _configured = false;
    _pinLength = defaultPinLength;
    notifyListeners();
  }

  /// 候选密码是否与开屏密码相同（批次②：单文件密码设置时强制不同——
  /// 哈希加盐不可直接比对，用 verify 探测：能通过校验即同码）。
  ///
  /// 静态便捷入口：内部临时实例直读持久化层，供无法注入 service 的
  /// 页面（笔记本设密对话框等）做同码检测。
  static Future<bool> matchesAppLockPin(String candidate) async {
    final probe = AppLockService();
    await probe.load();
    return probe.verify(candidate);
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
