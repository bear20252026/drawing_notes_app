// ============================================================================
// app_lock_guard.dart —— 开屏密码防爆破守卫（批次③ 2026-09-01）
// ============================================================================
//
// 威胁模型：有人拿着已解锁的设备反复试 PIN。对策四层：
//   1. 失败计数持久化（HMAC 签名）——重启不清零；
//   2. 第 10 次失败起指数冷却（1min ×2 递增，封顶 24h）；
//   3. 单调钟 + 时间高水位线——调低系统时钟无法缩短冷却（批次③核心）；
//   4. 签名密钥与记录分储（偏好文件 + 应用支持目录各一份）——
//      只改偏好文件无法伪造合法记录。
//
// 诚实的边界：能同时改写两处存储的本地攻击者总能清空全部记录
// （等价于直接删除 PIN）；本守卫抬高门槛，不承诺绝对防篡改。
// 记录「存在但签名不合法」按 fail-closed 处理：立即进入最长冷却
// （合法场景只有存储损坏，用户知晓 PIN 等待即可恢复）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/vault_key_service.dart';

/// 开屏密码防爆破守卫。
///
/// 由 [AppLockService] 组合持有；测试注入 [clock] 与 [secretLoader]。
class LockoutGuard {
  LockoutGuard({
    this.clock = DateTime.now,
    this.lockoutBase = const Duration(minutes: 1),
    this.lockoutCap = const Duration(hours: 24),
    this.lockoutThreshold = 10,
    Future<List<int>> Function()? secretLoader,
  }) : _secretLoader = secretLoader ?? defaultSecretLoader;

  static const _kRecordKey = 'app_lock.guard.record';
  static const _kSigKey = 'app_lock.guard.sig';

  /// 第 [lockoutThreshold] 次失败起冷却 = base × 2^(n-threshold)，封顶 [lockoutCap]。
  final Duration lockoutBase;
  final Duration lockoutCap;
  final int lockoutThreshold;

  /// 可注入时钟（测试）；生产为系统时间。
  final DateTime Function() clock;

  /// 签名密钥加载器（默认：应用支持目录随机密钥文件，与偏好文件分储）。
  final Future<List<int>> Function() _secretLoader;

  int _count = 0;
  int _untilMs = 0;
  int _highWaterMs = 0;

  /// 会话单调钟：boot 时刻的可信时间 + 已流逝时长（ Stopwatch 不受
  /// 系统时钟调整影响，会话内调钟也无效）。
  final Stopwatch _uptime = Stopwatch()..start();
  int _bootTrustedMs = 0;

  bool _loaded = false;
  List<int>? _secret;

  /// 是否已完成持久化恢复（service.verify 路径会惰性补载）。
  bool get isLoaded => _loaded;

  /// 当前连续失败次数。
  int get failureCount => _count;

  /// 是否处于冷却期。
  bool get isLockedOut => trustedNowMs() < _untilMs;

  /// 冷却剩余时长（不在冷却时为 0）。
  Duration get remaining =>
      Duration(milliseconds: max(0, _untilMs - trustedNowMs()));

  /// 下一次失败将触发的冷却时长（未达阈值时为 0）；设置页/调试展示用。
  Duration get nextLockoutForFailure =>
      _count + 1 >= lockoutThreshold ? _delayFor(_count + 1) : Duration.zero;

  Duration _delayFor(int attempt) {
    final exponent = attempt - lockoutThreshold;
    if (exponent < 0) return Duration.zero;
    final ms = lockoutBase.inMilliseconds * (1 << min(exponent, 20));
    return Duration(milliseconds: min(ms, lockoutCap.inMilliseconds));
  }

  /// 可信当前时间：单调会话钟、系统时钟、持久化高水位线三者取最大。
  /// 任何一路被调低都影响不了结果——冷却只可能「走完」，不可能「绕过」。
  int trustedNowMs() {
    final monotonicMs = _bootTrustedMs + _uptime.elapsedMilliseconds;
    final systemMs = clock().millisecondsSinceEpoch;
    final trusted = max(max(monotonicMs, systemMs), _highWaterMs);
    // 内存高水位线随时推进；落盘时机见 [_persistRecord]。
    _highWaterMs = max(_highWaterMs, trusted);
    return trusted;
  }

  /// 从持久化层恢复守卫状态（service.load 时调用一次）。
  Future<void> load(Future<SharedPreferences> Function() prefsLoader) async {
    final prefs = await prefsLoader();
    _secret = await _safeSecret();
    _bootTrustedMs = clock().millisecondsSinceEpoch;
    _uptime.reset();

    final recordStr = prefs.getString(_kRecordKey);
    final sigStr = prefs.getString(_kSigKey);
    if (recordStr == null || sigStr == null) {
      // 无记录（首次/合法清零）：从干净状态开始。
      _count = 0;
      _untilMs = 0;
      _highWaterMs = 0;
      _loaded = true;
      return;
    }

    final record = _parseRecord(recordStr);
    final sigValid =
        _secret != null && _constantTimeEquals(_sign(recordStr), sigStr);
    if (record == null || !sigValid) {
      // 记录存在但不合法（被篡改/损坏）→ fail-closed：立即最长冷却。
      debugPrint('LockoutGuard: 检测到无效守卫记录，进入保护性冷却');
      _count = lockoutThreshold;
      _highWaterMs = record?['hw'] ?? clockMs();
      _untilMs = trustedNowMs() + lockoutCap.inMilliseconds;
      _bootTrustedMs = _highWaterMs;
      _uptime.reset();
      await _persistRecord(prefs);
      _loaded = true;
      return;
    }

    _count = record['c'] as int;
    _untilMs = record['u'] as int;
    _highWaterMs = record['hw'] as int;
    _loaded = true;
  }

  /// 记录一次校验结果：成功清零并删除记录；失败计数并按需上锁。
  /// 必须在「校验通过阈值检查之后」调用（冷却期内根本不该走到这）。
  Future<void> recordAttempt(
    bool ok,
    Future<SharedPreferences> Function() prefsLoader,
  ) async {
    assert(_loaded, 'load() 必须先于 recordAttempt 调用');
    final prefs = await prefsLoader();
    if (ok) {
      _count = 0;
      _untilMs = 0;
      _highWaterMs = trustedNowMs();
      await prefs.remove(_kRecordKey);
      await prefs.remove(_kSigKey);
      return;
    }
    _count += 1;
    final delay = _delayFor(_count);
    _untilMs = delay == Duration.zero
        ? 0
        : trustedNowMs() + delay.inMilliseconds;
    await _persistRecord(prefs);
  }

  /// 守卫整体清零（关闭应用锁时随 [AppLockService.disable] 调用）。
  Future<void> reset(Future<SharedPreferences> Function() prefsLoader) async {
    final prefs = await prefsLoader();
    _count = 0;
    _untilMs = 0;
    await prefs.remove(_kRecordKey);
    await prefs.remove(_kSigKey);
  }

  Future<void> _persistRecord(SharedPreferences prefs) async {
    // 高水位线随记录一起落盘：本次会话见过的最大可信时间。
    // （不在每次 isLockedOut 轮询时写盘——只在记录本就会更新的时机写。）
    final record = jsonEncode(<String, int>{
      'c': _count,
      'u': _untilMs,
      'hw': _highWaterMs,
    });
    await prefs.setString(_kRecordKey, record);
    await prefs.setString(_kSigKey, _sign(record));
  }

  Map<String, int>? _parseRecord(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final c = decoded['c'];
      final u = decoded['u'];
      final hw = decoded['hw'];
      if (c is! int || u is! int || hw is! int) return null;
      if (c < 0 || u < 0 || hw < 0) return null;
      return {'c': c, 'u': u, 'hw': hw};
    } catch (_) {
      return null;
    }
  }

  String _sign(String record) => hexEncode(
    Hmac(
      sha256,
      _secret ?? List<int>.filled(32, 0),
    ).convert(utf8.encode(record)).bytes,
  );

  int clockMs() => clock().millisecondsSinceEpoch;

  Future<List<int>?> _safeSecret() async {
    try {
      return await _secretLoader();
    } catch (_) {
      return null; // 密钥不可读 → 签名校验按不合法处理（fail-closed）
    }
  }

  /// 默认密钥存储：应用支持目录下随机 32 字节文件（与偏好文件物理分储——
  /// 只改偏好文件伪造不出合法签名）。
  ///
  /// 测试环境（FLUTTER_TEST）：平台通道不可用（file/pat​h_provider 在
  /// testWidgets 假时钟下永不返回），改用进程内随机密钥——不落盘，
  /// 同一测试进程内签名自洽，真实设备路径不受影响。
  static List<int>? _testSecret;

  static Future<List<int>> defaultSecretLoader() async {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return _testSecret ??= VaultKeyService.randomBytes(32);
    }
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}app_lock_guard.key');
    if (await file.exists()) {
      return base64Decode((await file.readAsString()).trim());
    }
    // 随机密钥单一事实来源：复用 VaultKeyService.randomBytes（CSPRNG）。
    final key = VaultKeyService.randomBytes(32);
    await file.writeAsString(base64Encode(key), flush: true);
    return key;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String hexEncode(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 测试用：内存密钥的守卫构造器（不触碰真实文件系统）。
LockoutGuard memoryGuard({
  DateTime Function()? clock,
  Duration lockoutBase = const Duration(minutes: 1),
  Duration lockoutCap = const Duration(hours: 24),
}) {
  Uint8List? secret;
  return LockoutGuard(
    clock: clock ?? DateTime.now,
    lockoutBase: lockoutBase,
    lockoutCap: lockoutCap,
    secretLoader: () async => secret ??= VaultKeyService.randomBytes(32),
  );
}
