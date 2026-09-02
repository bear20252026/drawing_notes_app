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
// - 缓存键不含明文密码（密码先过 SHA-256 再入键）；
// - 缓存值 = PBKDF2 派生出的 32B KEK——与会话 DEK 缓存（_sessionDeks、
//   _sessionNotebookPasswords）同口径的内存驻留敏感材料，切后台即清；
// - 命中返回副本（调用方写不进缓存）；clear 后 in-flight 派生结果不回填
//   （generation 校验，防「清后复活」）。
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

  /// 缓存键：`iterations|base64(salt)|base64(sha256(password))`——
  /// 明文密码不驻留缓存键。
  final Map<String, Uint8List> _cache = {};

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
    final inflight = _inflight[key];
    if (inflight != null) return Uint8List.fromList(await inflight);

    final gen = _generation;
    final task = Isolate.run(() => _deriveBytesAsync(password, salt, params));
    _inflight[key] = task;
    try {
      final derived = await task;
      if (gen == _generation) {
        _cache[key] = derived;
        while (_cache.length > _maxEntries) {
          _cache.remove(_cache.keys.first); // 淘汰最旧
        }
      }
      return Uint8List.fromList(derived);
    } finally {
      _inflight.remove(key);
    }
  }

  /// 清空缓存：全部条目 fill(0) 擦除后置空（D-2 内存清理模式）。
  /// 代际 +1——已派发未完成的 isolate 结果不再回填。
  void clear() {
    for (final value in _cache.values) {
      value.fillRange(0, value.length, 0);
    }
    _cache.clear();
    _generation++;
  }

  static String _cacheKey(String password, List<int> salt, KdfParams params) {
    final pwDigest = crypto.sha256.convert(utf8.encode(password)).bytes;
    final kdfTag = params.kdf == KdfParams.kdfArgon2id
        ? '${params.kdf}|${params.memoryKiB}|${params.timeCost}|${params.parallelism}'
        : '${params.kdf}|${params.iterations}';
    return '$kdfTag|${base64Encode(salt)}|${base64Encode(pwDigest)}';
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
      pc.Pbkdf2Parameters(
        Uint8List.fromList(salt),
        iterations,
        32,
      ),
    );
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}
