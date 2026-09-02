// ============================================================================
// quick_unlock_service.dart —— 系统验证快速解锁（批D1 2026-09-02）
// ============================================================================
//
// 开屏锁的第三条解锁通道（用户 2026-09-02 拍板口径）：
//   开屏：密码 ✅ / 系统验证（Windows Hello 人脸·指纹·PIN，可选）✅
//   文件：只认密码 ✅（快速解锁不覆盖文件密码——文件密码是比开屏更高
//         一级的主动隔离，若能刷脸解开第二道锁就名存实亡）
//
// 密钥链设计（LUKS/BitLocker 多保护器语义的第三把钥匙）：
//   保险库 MK --副本(base64)--> flutter_secure_storage
//   Windows 底层 = DPAPI：密文绑定当前 Windows 用户账户，换用户/换机器
//   /偷硬盘都解不开（Chrome/Edge 保存网站密码同款机制）。
//   Android 底层 = Keystore 体系（flutter_secure_storage 默认实现，
//   密钥材料保护在 Android Keystore/TEE 内，App 读不到密钥原文）。
//   - 副本只在「开关打开」时存在；关闭开关立即 clear（关=删，无残留）；
//   - 文件密码（每个文件独立的 KEK）从不进入本存储——口径天然成立；
//   - 修改开屏密码（changePin）不换 MK，副本持续有效；
//   - 开启时先跑一次系统验证确认设备可用，验证不过不落副本。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/vault_key_service.dart';

/// 快速解锁异常（开关流程失败时向上传递可读原因）。
class QuickUnlockException implements Exception {
  const QuickUnlockException(this.reason);

  final String reason;

  @override
  String toString() => 'QuickUnlockException($reason)';
}

/// 系统身份验证后端抽象（测试注入替身用）。
///
/// 生产实现 = local_auth：Windows 走 Windows Hello（人脸/指纹/PIN 由
/// 系统统一弹窗决策，App 不可指定单一方式——微软 API 设计如此）；
/// Android 走 BiometricPrompt（指纹/人脸/系统凭据，同由系统决策）。
abstract class SystemAuthBackend {
  /// 设备/系统是否支持本地身份验证（有硬件且系统已配置）。
  Future<bool> isSupported();

  /// 弹出系统验证对话框；通过返回 true（取消/失败/超时返回 false）。
  Future<bool> authenticate(String reason);
}

/// local_auth 生产实现。
class LocalAuthBackend implements SystemAuthBackend {
  LocalAuthBackend({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isSupported() async {
    // canCheckBiometrics 只代表有硬件；isDeviceSupported 覆盖
    // 「无生物识别硬件但可走系统 PIN」的设备（Windows Hello PIN /
    // Android 系统凭据同样算）。
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return await _auth.canCheckBiometrics || true;
    } catch (_) {
      // 插件未注册（测试环境）/平台异常：视为不支持，快速解锁自动隐藏。
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}

/// 主密钥副本安全存储抽象（测试注入替身用）。
abstract class SystemUnlockKeyStore {
  /// 读取副本（base64；不存在返回 null）。
  Future<String?> read();

  /// 写入副本（覆盖语义）。
  Future<void> write(String value);

  /// 删除副本（幂等）。
  Future<void> clear();

  /// 是否存在副本。
  Future<bool> contains();
}

/// flutter_secure_storage 实现（Windows = DPAPI 绑定当前用户账户）。
class SecureSystemUnlockKeyStore implements SystemUnlockKeyStore {
  SecureSystemUnlockKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyMkCopy = 'quick_unlock.master_key_copy';

  @override
  Future<String?> read() => _storage.read(key: _keyMkCopy);

  @override
  Future<void> write(String value) => _storage.write(key: _keyMkCopy, value: value);

  @override
  Future<void> clear() => _storage.delete(key: _keyMkCopy);

  @override
  Future<bool> contains() => _storage.containsKey(key: _keyMkCopy);
}

/// 内存实现（测试替身）。
class MemorySystemUnlockKeyStore implements SystemUnlockKeyStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }

  @override
  Future<bool> contains() async => _value != null;
}

/// 系统验证快速解锁服务——本功能的单一事实来源。
///
/// 职责：开关持久化（shared_preferences）+ 主密钥副本生命周期（OS 凭据库）
/// + 系统验证编排。UI 层（设置页/锁屏门）只调用本类，不直触底层。
///
/// 用法：
/// ```dart
/// final quickUnlock = QuickUnlockService();
/// await quickUnlock.isReady();            // 锁屏是否显示快速解锁按钮
/// await quickUnlock.enable(pin: pin, vault: vault);   // 设置页开启
/// await quickUnlock.disable();            // 设置页关闭（副本即删）
/// await quickUnlock.authenticateAndUnlock(vault: vault); // 锁屏一键解锁
/// ```
class QuickUnlockService {
  QuickUnlockService({
    SystemAuthBackend? backend,
    SystemUnlockKeyStore? keyStore,
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _backend = backend ?? LocalAuthBackend(),
       _keyStore = keyStore ?? SecureSystemUnlockKeyStore(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  /// 开关持久化键（与 AppLockService 键前缀同族，便于审计）。
  static const _kEnabledKey = 'app_lock.quick_unlock_enabled';

  /// 主密钥副本长度（与保险库 _mkBytes 一致：32 字节）。
  static const _mkBytes = 32;

  final SystemAuthBackend _backend;
  final SystemUnlockKeyStore _keyStore;
  final Future<SharedPreferences> Function() _preferencesLoader;

  /// 平台是否支持（Windows = Windows Hello；Android = BiometricPrompt，
  /// 批D2 接入——指纹/人脸/系统凭据由系统弹窗决策）。
  Future<bool> isPlatformSupported() async {
    if (Platform.isWindows || Platform.isAndroid) return _backend.isSupported();
    return false;
  }

  /// 开关是否处于打开状态（持久化值，不代表副本可用）。
  Future<bool> isEnabled() async {
    final prefs = await _preferencesLoader();
    return prefs.getBool(_kEnabledKey) ?? false;
  }

  /// 快速解锁当前是否可用（锁屏按钮显示的唯一判据）：
  /// 平台支持 + 开关打开 + 副本存在。任一不满足都不显示（fail-closed）。
  Future<bool> isReady() async {
    if (!await isEnabled()) return false;
    if (!await isPlatformSupported()) return false;
    return _keyStore.contains();
  }

  /// 开启快速解锁：系统验证 → 确保保险库解锁 → 存 MK 副本 → 持久化开关。
  ///
  /// [pin] 须已通过 AppLockService.verify（调用方负责，失败计入防爆破）。
  /// 本方法内仍会做系统验证——设备不支持/验证不过就不落任何副本。
  Future<void> enable({
    required String pin,
    required VaultKeyService vault,
  }) async {
    if (pin.isEmpty) throw ArgumentError('PIN 不能为空');
    if (!await isPlatformSupported()) {
      throw const QuickUnlockException('当前设备不支持系统验证');
    }
    // 系统验证一次：确认硬件/系统就绪，同时让用户确认预期行为。
    if (!await _backend.authenticate('验证身份以开启系统验证快速解锁')) {
      throw const QuickUnlockException('系统验证未通过');
    }
    // 确保保险库解锁（与 AppLockGate._unlockVault 同链路：已配置解锁、
    // 未配置补建——老用户升级首解场景）。
    try {
      if (await vault.isConfigured()) {
        if (!vault.isUnlocked) await vault.unlock(pin);
      } else {
        await vault.initialize(pin);
      }
    } on VaultUnlockException {
      rethrow;
    }
    // 存副本（base64 的 32B MK）。DPAPI 保证：只有当前 Windows 用户能解。
    final mk = vault.masterKey;
    await _keyStore.write(base64Encode(mk));
    final prefs = await _preferencesLoader();
    await prefs.setBool(_kEnabledKey, true);
  }

  /// 关闭快速解锁：**副本立即删除** + 开关持久化为关（关=删，无残留）。
  Future<void> disable() async {
    await _keyStore.clear();
    final prefs = await _preferencesLoader();
    await prefs.setBool(_kEnabledKey, false);
  }

  /// 锁屏一键解锁：系统验证 → 取副本 → 注入保险库。
  ///
  /// fail-closed：开关未开 / 设备不支持 / 验证未过 / 副本缺失或损坏 /
  /// 长度异常，一律返回 false（锁屏保持原状，PIN 通道永远可用）。
  Future<bool> authenticateAndUnlock({required VaultKeyService vault}) async {
    if (!await isReady()) return false;
    if (!await _backend.authenticate('验证身份以解锁绘图笔记')) return false;
    final String? encoded;
    try {
      encoded = await _keyStore.read();
    } catch (_) {
      return false;
    }
    if (encoded == null) return false;
    final Uint8List mk;
    try {
      mk = base64Decode(encoded);
    } on FormatException {
      return false;
    }
    if (mk.length != _mkBytes) return false;
    try {
      vault.adoptMasterKey(mk);
    } catch (_) {
      return false;
    }
    return true;
  }
}
