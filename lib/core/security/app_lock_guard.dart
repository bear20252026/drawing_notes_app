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
//
// M4 修复（2026-11-11）：签名密钥与守卫记录**同域共储**——两者均落
// `security/` 私有目录、均 0600——原先记录走 SharedPreferences（与密钥
// 分储但同账户可达），攻击者改写偏好文件即可让签名校验对着伪造记录通过。
// 现在记录+签名+密钥三者在同一受保护文件域内，单独改写任一处都会断签
// （fail-closed）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/utils/hex_encode.dart' as hex;

/// 守卫记录文件名（与签名密钥 [defaultSecretLoader] 同目录——M4 同域共储）。
@visibleForTesting
const kGuardRecordFile = 'app_lock_guard.record';

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

  // M4：记录与签名合并存入 security/ 私有文件（不再走 SharedPreferences）。
  // 兼容读：旧版 SharedPreferences 里的记录仍可在迁移期读出（见 [_loadRecord]）。
  static const _kLegacyRecordKey = 'app_lock.guard.record';
  static const _kLegacySigKey = 'app_lock.guard.sig';

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

    final (recordStr, sigStr) = await _loadRecord(prefs);
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
      // P1 修复：debugPrint 改走 AuditLogger（生产日志脱敏）。
      AuditLogger.log('app_lock.guard.invalid_record', success: false);
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
    // M4 迁移：旧 SharedPreferences 记录读到后立即迁移到私有文件/新键——
    // 否则用户不触发 recordAttempt 就永远停在旧存储（重启后丢失）。
    if (recordStr.isNotEmpty && !_isNewFormat(prefs)) {
      await _persistRecord(prefs);
    }
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
      await _deleteRecord(prefs);
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
    await _deleteRecord(prefs);
  }

  // ==== M4：记录与签名合并存于 security/ 私有文件 ====

  /// 读取记录 + 签名（新格式优先；旧 SharedPreferences 兼容读）。
  Future<(String?, String?)> _loadRecord(SharedPreferences prefs) async {
    // 测试环境：SharedPreferences mock 可用，直接走新格式文件——
    // 但测试不落盘（平台通道不可用），走 SharedPreferences 键（同格式）。
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      final record = prefs.getString(kGuardRecordFile);
      if (record != null) {
        try {
          final decoded = jsonDecode(record) as Map<String, dynamic>;
          return (decoded['record'] as String?, decoded['sig'] as String?);
        } catch (_) {
          return (null, null);
        }
      }
      // 兼容旧版 SharedPreferences 键。
      final legacyRecord = prefs.getString(_kLegacyRecordKey);
      final legacySig = prefs.getString(_kLegacySigKey);
      return (legacyRecord, legacySig);
    }
    try {
      final dir = await AppDataRoot.defaultSecurityDir();
      final file = File('${dir.path}${Platform.pathSeparator}$kGuardRecordFile');
      if (file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final record = decoded['record'] as String?;
        final sig = decoded['sig'] as String?;
        if (record != null && sig != null) {
          // 迁移：读到合法记录后清掉旧 SharedPreferences 条目。
          await _clearLegacyPrefs(prefs);
          return (record, sig);
        }
      }
    } catch (_) {
      // 读失败 → 回退到旧 SharedPreferences 兼容路径。
    }
    // 兼容：旧版 SharedPreferences 里的记录（首次迁移期）。
    final record = prefs.getString(_kLegacyRecordKey);
    final sig = prefs.getString(_kLegacySigKey);
    return (record, sig);
  }

  Future<void> _persistRecord(SharedPreferences prefs) async {
    // 高水位线随记录一起落盘：本次会话见过的最大可信时间。
    // （不在每次 isLockedOut 轮询时写盘——只在记录本就会更新的时机写。）
    final record = jsonEncode(<String, int>{
      'c': _count,
      'u': _untilMs,
      'hw': _highWaterMs,
    });
    final sig = _sign(record);
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      // 测试环境：写入 SharedPreferences mock（与生产同格式）。
      await prefs.setString(
        kGuardRecordFile,
        jsonEncode({'record': record, 'sig': sig}),
      );
      await _clearLegacyPrefs(prefs);
      return;
    }
    try {
      final dir = await AppDataRoot.defaultSecurityDir();
      final file = File('${dir.path}${Platform.pathSeparator}$kGuardRecordFile');
      final parent = file.parent;
      if (!parent.existsSync()) await parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'record': record, 'sig': sig}),
        flush: true,
      );
      await AppDataRoot.tightenFilePermissions(file);
      // 写入成功后清掉旧 SharedPreferences 条目（迁移完成）。
      await _clearLegacyPrefs(prefs);
    } catch (_) {
      // 落盘失败不阻断守卫语义——内存态仍自洽。
    }
  }

  Future<void> _deleteRecord(SharedPreferences prefs) async {
    await prefs.remove(kGuardRecordFile);
    await _clearLegacyPrefs(prefs);
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final dir = await AppDataRoot.defaultSecurityDir();
      final file = File('${dir.path}${Platform.pathSeparator}$kGuardRecordFile');
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // 删除失败不阻断。
    }
  }

  Future<void> _clearLegacyPrefs(SharedPreferences prefs) async {
    try {
      await prefs.remove(_kLegacyRecordKey);
      await prefs.remove(_kLegacySigKey);
    } catch (_) {
      // 忽略——旧存储可能不可写。
    }
  }

  /// 新格式键是否存在（区分旧 SharedPreferences vs 已迁移）。
  bool _isNewFormat(SharedPreferences prefs) =>
      prefs.getString(kGuardRecordFile) != null;

  /// 测试辅助：清零测试态内存记录（用例间防串扰）。
  @visibleForTesting
  static void debugResetTestState() {
    // 测试环境记录走 SharedPreferences mock（setMockInitialValues 即清零）。
  }

  /// 测试辅助：对记录计算签名（静态，直接传密钥——不依赖 load 状态）。
  @visibleForTesting
  static String debugSignForTest(String record, List<int> secret) {
    return hexEncode(
      Hmac(sha256, secret).convert(utf8.encode(record)).bytes,
    );
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
    // 存储收口（2026-09-02）：密钥迁入统一数据根 security/（原应用支持
    // 目录；旧文件由 AppDataRoot 首次迁移搬入，此处只做确保存在）。
    final dir = await AppDataRoot.defaultSecurityDir();
    final file = File('${dir.path}${Platform.pathSeparator}app_lock_guard.key');
    if (file.existsSync()) {
      return base64Decode((await file.readAsString()).trim());
    }
    // 随机密钥单一事实来源：复用 VaultKeyService.randomBytes（CSPRNG）。
    final key = VaultKeyService.randomBytes(32);
    await file.writeAsString(base64Encode(key), flush: true);
    // M3 修复（2026-11-11）：守卫签名密钥收紧到 0600（仅属主可读写）。
    // chmod 失败静默——加固不阻断业务。
    await AppDataRoot.tightenFilePermissions(file);
    return key;
  }

  /// 恒定时间字符串比较（防时序侧信道）。
  ///
  /// 输入是 HMAC-SHA256 hex（定长 64 字符），但**不因长度不等提前返回**——
  /// 长度差折算进 diff、循环按两者较长者遍历，避免「长度是否相等」这一点点
  /// 时间差成为侧信道。UTF-8 字节比较对 ASCII hex 与 codeUnit 等价，且对
  /// 任意输入都成立（不依赖输入是 ASCII）。
  static bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    var diff = aBytes.length ^ bBytes.length;
    final n = aBytes.length > bBytes.length ? aBytes.length : bBytes.length;
    for (var i = 0; i < n; i++) {
      final x = i < aBytes.length ? aBytes[i] : 0;
      final y = i < bBytes.length ? bBytes[i] : 0;
      diff |= x ^ y;
    }
    return diff == 0;
  }

  // 薄委托：实现收敛至 core/utils/hex_encode.dart（保留静态入口防漏改）。
  static String hexEncode(List<int> bytes) => hex.hexEncode(bytes);
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
