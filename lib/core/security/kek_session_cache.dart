// N3 解密提速 B 方案（2026-09-02 用户拍板）：
// isolate 后台计算 + KEK 会话缓存 + 锁屏即清。
// 批B Argon2id 升级（2026-09-02 用户批准）：派生按 KdfParams 分派——
// 新槽位 Argon2id（cryptography 纯 Dart 实现），旧数据 PBKDF2
// （pointycastle，逐字节一致）。
//
// 单例；缓存清除时机定案：AppLifecycleState.hidden 即清（fill(0) 擦除），
// 不做超时等待（AppLockGate 的生命周期钩子调用 [clear]）。
//
// 安全口径：
// - 缓存键 = HMAC(进程 pepper||槽位盐, 密码)——无盐 sha256(口令)已删除；
//   clear() 擦除并轮换 pepper，残留键串永久失效（P0 修复 N39）；
// - 缓存值 = KDF 派生出的 32B KEK——与会话 DEK 缓存（_sessionDeks、
//   _sessionNotebookPasswords）同口径的内存驻留敏感材料，切后台即清；
//   LRU 淘汰同样 fill(0)（P0 修复 N41）；
// - 命中返回副本（调用方写不进缓存）；clear 后 in-flight 派生结果不回填
//   且不交付（generation 校验 + 作废擦除，调用方按失败重试——P0 修复 N40）。
//
// 性能口径：
// - 未命中 → Isolate.run 后台派生（pointycastle 实现）——主 isolate 零
//   阻塞，600k PBKDF2 期间 UI 不再冻结；
// - 同 (密码, 盐, 迭代) 并发调用共享同一 Future（in-flight 去重）；
// - LRU 上限封顶（写路径随机盐条目自动淘汰，防积累）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:meta/meta.dart';
import 'package:pointycastle/export.dart' as pc;

import 'package:drawing_notes_app/core/security/kdf_params.dart';

/// KEK 会话缓存（N3 提速 B 方案）。
class KekSessionCache {
  KekSessionCache._();

  static final KekSessionCache instance = KekSessionCache._();

  /// LRU 容量上限：写路径（随机新盐）的缓存条目无复用价值，靠上限
  /// 自动淘汰，读路径热点（开屏/文件密码/媒体/同步派生）远小于此值。
  static const int _maxEntries = 64;

  /// 缓存键：`kdfTag|base64(salt)|base64(HMAC(pepper||salt, password))`。
  ///
  /// P0 修复（审计 N39/N41）：旧键 `sha256(password)` 是无盐快速哈希——
  /// 堆转储即得 GPU 可爆破的口令验证器，且绕过 Argon2/600k 成本。新键以
  /// 进程级随机 pepper + 槽位盐做 HMAC：
  /// - 会话内存中仍有验证器（缓存本就如此，KEK 明文本就驻留——无回归）；
  /// - `clear()` 同时擦除并轮换 pepper——清屏后的转储/日志残留键串
  ///   永久失效（旧 pepper 已清零，不可再验证任何口令）。
  final Map<String, Uint8List> _cache = {};

  /// 进程级 HMAC pepper（32B CSPRNG）：clear 时 fill(0) 擦除并轮换。
  /// 用 dart:math 不经 VaultKeyService，避免模块循环依赖。
  Uint8List _pepper = _newPepper();

  static Uint8List _newPepper() {
    final r = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => r.nextInt(256)),
    );
  }

  /// 测试旁路：为 true 时跳过 `Isolate.run`，在当前 isolate 直接派生。
  /// testWidgets 跑在 FakeAsync zone，后台 isolate 结果永不回投导致挂起；
  /// 纯单测与生产恒走 isolate（性能与隔离语义不变）。
  @visibleForTesting
  static bool bypassIsolateForTests = false;

  /// in-flight 去重：同键并发派生共享同一 Future。
  final Map<String, Future<Uint8List>> _inflight = {};

  /// 清除代际：clear 后 in-flight 结果不回填（防清后复活）。
  int _generation = 0;

  /// 当前缓存条数（测试观察用）。
  @visibleForTesting
  int get entryCount => _cache.length;

  /// 派生 KEK：按 [params] 分派 KDF（批B Argon2id / 旧 PBKDF2）→ 32B。
  ///
  /// 命中缓存零重算；未命中在后台 isolate 派生（主 isolate 不阻塞）。
  /// 缓存键含完整 KDF 参数——同 (密码, 盐) 不同 KDF 派生的键互不串缓存。
  Future<Uint8List> deriveKek(
    String password,
    List<int> salt,
    KdfParams params,
  ) async {
    final key = _cacheKey(password, salt, params);
    final cached = _cache[key];
    if (cached != null) {
      // LRU touch：命中移到最新（LinkedHashMap 保插入序，重插即 touch）。
      _cache.remove(key);
      _cache[key] = cached;
      return Uint8List.fromList(cached);
    }
    final gen = _generation;
    final inflight = _inflight[key];
    if (inflight != null) {
      // 并发加入：等待共享结果；等待期间被 clear 则 fail-closed（不交付
      // 锁后 KEK——P0 修复 N40 后半段；调用方按解锁失败处理，用户重试）。
      final shared = await inflight;
      _checkGen(gen);
      return Uint8List.fromList(shared);
    }

    // 测试旁路（见字段注释）：同 Future 契约，仅换执行位置。
    final Future<Uint8List> task = bypassIsolateForTests
        ? _deriveBytesAsync(password, salt, params)
        : Isolate.run(() => _deriveBytesAsync(password, salt, params));
    _inflight[key] = task;
    try {
      final derived = await task;
      if (gen != _generation) {
        // 派生期间被 clear：结果作废并擦除，不回填、不交付（P0 修复 N40）。
        derived.fillRange(0, derived.length, 0);
        throw StateError('KEK 会话已清除（锁屏后派生结果作废）');
      }
      _cache[key] = derived;
      while (_cache.length > _maxEntries) {
        // P0 修复 N41：淘汰条目同样 fill(0)（此前直接丢弃，明文驻留堆）。
        final evicted = _cache.remove(_cache.keys.first);
        evicted?.fillRange(0, evicted.length, 0);
      }
      return Uint8List.fromList(derived);
    } finally {
      _inflight.remove(key);
    }
  }

  void _checkGen(int gen) {
    if (gen != _generation) {
      throw StateError('KEK 会话已清除（锁屏后派生结果作废）');
    }
  }

  /// 清空缓存：全部条目 fill(0) 擦除后置空（D-2 内存清理模式）。
  /// 代际 +1（在途派生作废）+ pepper 擦除并轮换（残留键串永久失效）。
  void clear() {
    for (final value in _cache.values) {
      value.fillRange(0, value.length, 0);
    }
    _cache.clear();
    _pepper.fillRange(0, _pepper.length, 0);
    _pepper = _newPepper();
    _generation++;
  }

  String _cacheKey(String password, List<int> salt, KdfParams params) {
    // P0 修复 N39：pepper 化 HMAC 取代无盐 sha256(口令)。
    final mac = crypto.Hmac(crypto.sha256, [..._pepper, ...salt]);
    final digest = mac.convert(utf8.encode(password)).bytes;
    final kdfTag = params.kdf == KdfParams.kdfArgon2id
        ? '${params.kdf}|${params.memoryKiB}|${params.timeCost}|${params.parallelism}'
        : '${params.kdf}|${params.iterations}';
    return '$kdfTag|${base64Encode(salt)}|${base64Encode(digest)}';
  }
}

/// 派生分派（在后台 isolate 执行）——按槽位声明的 KDF 计算 32B KEK。
Future<Uint8List> _deriveBytesAsync(
  String password,
  List<int> salt,
  KdfParams params,
) async {
  switch (params.kdf) {
    case KdfParams.kdfPbkdf2:
      return _pbkdf2DeriveBytes(password, salt, params.iterations!);
    case KdfParams.kdfArgon2id:
      return _argon2idDeriveBytes(
        password,
        salt,
        params.memoryKiB!,
        params.timeCost!,
        params.parallelism!,
      );
    default:
      throw ArgumentError('不支持的 KDF: ${params.kdf}');
  }
}

/// Argon2id（RFC 9106，package:cryptography 纯 Dart 实现）——批B 新槽位。
///
/// 输出与 PBKDF2 路径同为 32B；确定性由 argon2id_benchmark_test 保证
/// （同 (密码,盐,参数) 同输出——缓存键成立的前提）。
Future<Uint8List> _argon2idDeriveBytes(
  String password,
  List<int> salt,
  int memoryKiB,
  int timeCost,
  int parallelism,
) async {
  final algo = DartArgon2id(
    parallelism: parallelism,
    memory: memoryKiB, // 单位 = 1 KiB 块数（65536 = 64 MiB）
    iterations: timeCost,
    hashLength: 32,
  );
  final key = await algo.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: Uint8List.fromList(salt), // Argon2 的盐走 nonce 参数
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// PBKDF2-HMAC-SHA256 派生（pointycastle）——在后台 isolate 执行。
///
/// 与 package:cryptography 的 Pbkdf2(macAlgorithm: Hmac.sha256(),
/// iterations: N, bits: 256) 逐字节一致（标准算法实现；一致性由
/// kek_session_cache_test 保证）。HMac 块长 SHA-256 = 64 字节。
Uint8List _pbkdf2DeriveBytes(String password, List<int> salt, int iterations) {
  final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
    ..init(
      // Pbkdf2Parameters 的 keyLength 单位是**字节**（32 = 256 位）。
      pc.Pbkdf2Parameters(Uint8List.fromList(salt), iterations, 32),
    );
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}
