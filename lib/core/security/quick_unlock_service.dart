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
import 'package:drawing_notes_app/core/utils/error_code.dart';

/// 系统验证结果（H1 安全修复 2026-11-11）：不只回 bool，还须携带**实际
/// 验证方式**——`local_auth` 在 Windows 上 `biometricOnly: true` 可能被
/// 平台忽略（Windows Hello 不支持该开关），此时系统可能回退到设备 PIN；
/// 而设备 PIN 通常 4 位、强度远低于保险库口令。若只看 bool 就落 MK 副本，
/// 等于把「高熵口令保护的副本」降级成「4 位 PIN 保护的副本」。
///
/// [biometric] 为 true 表示系统**确实**用了生物识别（人脸/指纹/虹膜/
/// strong/weak）；为 false 表示只用了设备凭据（PIN/密码/图案）。
class SystemAuthResult {
  const SystemAuthResult({required this.success, required this.biometric});

  /// 用户是否通过验证（false = 取消/失败/超时）。
  final bool success;

  /// 是否确实经过生物识别验证。仅 [success] 为 true 时有意义。
  final bool biometric;
}

/// 快速解锁异常（开关流程失败时向上传递可读原因）。
class QuickUnlockException implements Exception, CodedFailure {
  @override
  String get errorCode => 'quick_unlock';
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

  /// 弹出系统验证对话框；通过返回 [SystemAuthResult]（取消/失败/超时
  /// 返回 `success: false`）。
  Future<SystemAuthResult> authenticate(String reason);
}

/// local_auth 生产实现。
class LocalAuthBackend implements SystemAuthBackend {
  LocalAuthBackend({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isSupported() async {
    // P0 安全修复（审计 N-H1）：删除 `|| true` 恒真式；要求设备已注册
    // 生物识别（人脸/指纹）——纯设备 PIN 回退不再计为“支持”，防止 4 位
    // 设备 PIN 绕过高熵保险库口令。fail-closed：任何异常视为不支持。
    try {
      if (!await _auth.isDeviceSupported()) return false;
      try {
        final enrolled = await _auth.getAvailableBiometrics();
        return enrolled.isNotEmpty;
      } catch (_) {
        return false;
      }
    } catch (_) {
      // 插件未注册（测试环境）/平台异常：视为不支持，快速解锁自动隐藏。
      return false;
    }
  }

  @override
  Future<SystemAuthResult> authenticate(String reason) async {
    try {
      // P0 安全修复（审计 N-H1）：biometricOnly 强制生物识别，禁止回退
      // 到设备 PIN / 系统凭据（否则保险库口令强度降级为设备 PIN 强度）。
      // local_auth 3.0.2 API：biometricOnly 为 bool 直参（无 options 包裹）。
      //
      // H1 修复（2026-11-11）：Windows Hello 平台忽略 `biometricOnly`，
      // 因此**验证后回查 getAvailableBiometrics**——若设备有已注册生物识别
      // 但 authenticate 只认设备凭据（PIN），说明系统回退了，必须如实上报
      // `biometric: false`，由调用方拒绝落副本。
      //
      // 回查失败（插件异常）按最坏情况处理：视为非生物识别（fail-closed）。
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
      if (!ok) return const SystemAuthResult(success: false, biometric: false);
      var biometric = false;
      try {
        biometric = (await _auth.getAvailableBiometrics()).isNotEmpty;
      } catch (_) {
        biometric = false;
      }
      return SystemAuthResult(success: true, biometric: biometric);
    } catch (_) {
      return const SystemAuthResult(success: false, biometric: false);
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

/// H1 安全修复（2026-11-11）：副本元数据——写入时刻 + TTL 过期时刻。
///
/// 攻击场景：DPAPI 副本在「开关打开」期间一直可读；若用户离开电脑但没关
/// 开关，任何以同一用户身份运行的进程都能读回 MK 并解锁。TTL 让副本
/// 在写入 [ttl] 后自动失效——`authenticateAndUnlock` 读到过期副本即拒，
/// 必须重新走 `enable`（再次生物识别验证）才能刷新。
///
/// 载荷格式（JSON）：`{"mk": "<base64 32B>", "issuedAtMs": <int>, "ttlMs": <int>}`。
/// 兼容旧格式：纯 base64 字符串按「无 TTL」处理（仍可读，但新写入恒带 TTL）。
class QuickUnlockCopyEnvelope {
  const QuickUnlockCopyEnvelope({
    required this.masterKeyBase64,
    required this.issuedAtMs,
    required this.ttlMs,
  });

  /// 编码后的 MK（base64 32B）。
  final String masterKeyBase64;

  /// 写入时刻（epoch ms）。
  final int issuedAtMs;

  /// 存活时长（ms）；<= 0 视为无 TTL（仅旧格式回退）。
  final int ttlMs;

  String encode() => jsonEncode({
    'mk': masterKeyBase64,
    'issuedAtMs': issuedAtMs,
    'ttlMs': ttlMs,
  });

  /// 解析副本载荷；畸形返回 null（调用方按副本损坏处理，fail-closed）。
  static QuickUnlockCopyEnvelope? tryDecode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    // 旧格式：纯 base64 MK（无 TTL）——兼容读取。
    if (!trimmed.startsWith('{')) {
      return QuickUnlockCopyEnvelope(
        masterKeyBase64: trimmed,
        issuedAtMs: 0,
        ttlMs: 0,
      );
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;
      final mk = decoded['mk'];
      final issuedAt = decoded['issuedAtMs'];
      final ttl = decoded['ttlMs'];
      if (mk is! String || mk.isEmpty) return null;
      if (issuedAt is! int || ttl is! int) return null;
      return QuickUnlockCopyEnvelope(
        masterKeyBase64: mk,
        issuedAtMs: issuedAt,
        ttlMs: ttl,
      );
    } catch (_) {
      return null;
    }
  }

  /// 副本是否已过期（fail-closed：时钟异常按未过期处理，但 TTL 已到点仍拒）。
  bool isExpired(DateTime now) {
    if (ttlMs <= 0 || issuedAtMs <= 0) return false; // 无 TTL（旧格式）
    final expiresAtMs = issuedAtMs + ttlMs;
    return now.millisecondsSinceEpoch >= expiresAtMs;
  }
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
  Future<void> write(String value) =>
      _storage.write(key: _keyMkCopy, value: value);

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
    bool Function()? platformSupported,
  }) : _backend = backend ?? LocalAuthBackend(),
       _keyStore = keyStore ?? SecureSystemUnlockKeyStore(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _platformSupported = platformSupported ?? _defaultPlatformSupported;

  /// 生产平台门：Windows / Android（其余平台不支持快速解锁）。
  /// 抽成可注入函数：CI 的 Linux runner 上 Platform 判断恒 false，
  /// 测试须注入 () => true 与运行 OS 解耦（沿用 KdfParams 注入先例）。
  static bool _defaultPlatformSupported() =>
      Platform.isWindows || Platform.isAndroid;

  /// 开关持久化键（与 AppLockService 键前缀同族，便于审计）。
  static const _kEnabledKey = 'app_lock.quick_unlock_enabled';

  /// 主密钥副本长度（与保险库 _mkBytes 一致：32 字节）。
  static const _mkBytes = 32;

  final SystemAuthBackend _backend;
  final SystemUnlockKeyStore _keyStore;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final bool Function() _platformSupported;

  /// 平台是否支持（Windows = Windows Hello；Android = BiometricPrompt，
  /// 指纹/人脸/系统凭据由系统弹窗决策）。
  Future<bool> isPlatformSupported() async {
    if (!_platformSupported()) return false;
    return _backend.isSupported();
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

  /// 开启快速解锁：系统验证（须生物识别）→ 确保保险库解锁 → 存 MK 副本（带 TTL）→ 持久化开关。
  ///
  /// [pin] 须已通过 AppLockService.verify（调用方负责，失败计入防爆破）。
  /// 本方法内仍会做系统验证——设备不支持/验证不过/系统回退到设备 PIN
  /// 都不落任何副本（H1 fail-closed）。
  Future<void> enable({
    required String pin,
    required VaultKeyService vault,
  }) async {
    if (pin.isEmpty) throw ArgumentError('PIN 不能为空');
    if (!await isPlatformSupported()) {
      throw const QuickUnlockException('当前设备不支持系统验证');
    }
    // 系统验证一次：确认硬件/系统就绪，同时让用户确认预期行为。
    // H1 修复：回查实际验证方式——系统若回退到设备 PIN 则拒绝落副本
    // （否则 4 位 PIN 即等价于保险库主密钥的「保护器」，强度降级）。
    final auth = await _backend.authenticate('验证身份以开启系统验证快速解锁');
    if (!auth.success) {
      throw const QuickUnlockException('系统验证未通过');
    }
    if (!auth.biometric) {
      throw const QuickUnlockException('系统未使用生物识别验证（可能回退到设备 PIN），已拒绝开启快速解锁');
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
    // 存副本（base64 的 32B MK + TTL 信封）。DPAPI 保证：只有当前
    // Windows 用户能解；TTL 保证：写入后 [copyTtl] 即失效，
    // 必须重新生物识别验证才能刷新。
    final mk = vault.masterKey;
    final envelope = QuickUnlockCopyEnvelope(
      masterKeyBase64: base64Encode(mk),
      issuedAtMs: DateTime.now().millisecondsSinceEpoch,
      ttlMs: copyTtl.inMilliseconds,
    );
    await _keyStore.write(envelope.encode());
    final prefs = await _preferencesLoader();
    await prefs.setBool(_kEnabledKey, true);
  }

  /// 关闭快速解锁：**副本立即删除** + 开关持久化为关（关=删，无残留）。
  Future<void> disable() async {
    await _keyStore.clear();
    final prefs = await _preferencesLoader();
    await prefs.setBool(_kEnabledKey, false);
  }

  /// 锁屏一键解锁：系统验证 → 取副本（校验 TTL）→ 注入保险库。
  ///
  /// fail-closed：开关未开 / 设备不支持 / 验证未过 / 副本缺失或损坏 /
  /// 长度异常 / 副本已过期，一律返回 false（锁屏保持原状，PIN 通道
  /// 永远可用）。
  Future<bool> authenticateAndUnlock({required VaultKeyService vault}) async {
    if (!await isReady()) return false;
    final auth = await _backend.authenticate('验证身份以解锁绘图笔记');
    if (!auth.success) return false;
    // H1 修复：解锁侧同样回查实际验证方式——设备 PIN 回退即拒
    // （与 enable 同一口径，防「开启时生物识别、解锁时 PIN」绕过）。
    if (!auth.biometric) return false;
    final String? encoded;
    try {
      encoded = await _keyStore.read();
    } catch (_) {
      return false;
    }
    if (encoded == null) return false;
    final envelope = QuickUnlockCopyEnvelope.tryDecode(encoded);
    if (envelope == null) return false;
    // H1 修复：TTL 过期即拒（副本写入后 copyTtl 即失效，必须重新
    // 生物识别验证才能刷新——防「开关长期开着」被同用户进程捡漏）。
    if (envelope.isExpired(DateTime.now())) return false;
    final Uint8List mk;
    try {
      mk = base64Decode(envelope.masterKeyBase64);
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

  /// 副本 TTL（H1 修复 2026-11-11）：写入后在该时长内可读，过期即拒。
  ///
  /// 取值 7 天：覆盖「周末关开关、周一回来」这类常见间隔，又不至于让
  /// 副本长期驻留。到期后 `authenticateAndUnlock` 返回 false，锁屏提示
  /// 重新输入 PIN；用户可在设置页重新开启快速解锁（再次生物识别验证）
  /// 以刷新副本。
  static const Duration copyTtl = Duration(days: 7);
}
