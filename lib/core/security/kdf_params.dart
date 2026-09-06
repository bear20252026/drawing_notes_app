import 'package:meta/meta.dart';

/// KDF 参数描述符（批B Argon2id 升级，2026-09-02 用户批准）。
///
/// 单一事实来源：保险库 PIN 槽 / DNV 文件信封密码槽 / v5 载荷密码槽的
/// 写入与读取，以及 KEK 会话缓存的派生分派，全部经由本类描述与编解码。
///
/// 槽位 JSON 自描述（LUKS2 每槽位独立 KDF 语义）：
/// ```jsonc
/// Argon2id: {"kdf":"argon2id","m":65536,"t":2,"p":2}
/// PBKDF2:   {"kdf":"pbkdf2","iter":600000}
/// ```
/// 读路径 `kdf` 字段缺失 = 批B 之前的旧数据（PBKDF2）——由调用方提供
/// 旧数据默认参数（各层迭代常量不同），本类不做隐式兜底。
///
/// 设计依据（批A 基准实测，本机 2026-09-02）：
/// - Argon2id 64MiB t2 p2 ≈ 348ms（OWASP 首选、内存硬抗 GPU）；
/// - PBKDF2-HMAC-SHA256 600k ≈ 2969ms（旧产线，OWASP 仍合规）。
/// 两者输出均为 32B 标准 KEK，下游 AEAD 全不动。
class KdfParams {
  const KdfParams.pbkdf2(this.iterations)
    : kdf = kdfPbkdf2,
      memoryKiB = null,
      timeCost = null,
      parallelism = null;

  const KdfParams.argon2id({
    required this.memoryKiB,
    required this.timeCost,
    required this.parallelism,
  }) : kdf = kdfArgon2id,
       iterations = null;

  static const String kdfPbkdf2 = 'pbkdf2';
  static const String kdfArgon2id = 'argon2id';

  /// 生产默认（批A 实测定案，用户批准 2026-09-02）：强档抗 GPU，
  /// 耗时远低于 0.5s 体验线。新写入的全部密码槽使用本参数。
  static const KdfParams argon2idProduction = KdfParams.argon2id(
    memoryKiB: 65536,
    timeCost: 2,
    parallelism: 2,
  );

  /// 测试轻量档（**仅限测试注入**，约几十 ms——8MiB t1 p1）。
  static const KdfParams testLight = KdfParams.argon2id(
    memoryKiB: 8192,
    timeCost: 1,
    parallelism: 1,
  );

  /// 读路径上限（P0 安全修复 N-H5：恶意分享文件 `m=1GiB/t=2^31` 触发
  /// OOM/挂起——超限直接 fail-closed 拒绝；`iter=1` 弱槽位仍可读
  /// （历史数据兼容），但新写入永远走 [argon2idProduction]）。
  static const int maxMemoryKiB = 262144; // 256 MiB（生产 64 MiB 的 4 倍）
  static const int maxTimeCost = 8; // 生产 t2 的 4 倍
  static const int maxParallelism = 8; // 生产 p2 的 4 倍
  static const int maxPbkdf2Iterations = 1200000; // 生产 600k 的 2 倍（覆盖 100k 旧产线）

  /// 新槽位 KDF 默认值（生产恒为 [argon2idProduction]）。
  ///
  /// P0 收口：对外只读；测试注入走 [@visibleForTesting] setter——生产
  /// 代码无合法写者（grep 全仓仅两处读）。此前裸可变静态任一代码/
  /// 测试污染即全局降级后续全部槽位。
  static KdfParams _newSlotDefault = argon2idProduction;
  static KdfParams get newSlotDefault => _newSlotDefault;
  @visibleForTesting
  // ignore: avoid_renaming_method_parameters
  static set newSlotDefault(KdfParams v) => _newSlotDefault = v;

  final String kdf;

  /// PBKDF2 迭代次数（argon2id 时为 null）。
  final int? iterations;

  /// Argon2id 内存（KiB，1KiB 块数——RFC 9106 口径）。
  final int? memoryKiB;

  /// Argon2id 时间成本 t。
  final int? timeCost;

  /// Argon2id 并行度 p。
  final int? parallelism;

  /// 槽位 JSON 序列化（仅 KDF 参数字段；盐/密文由调用方拼装）。
  Map<String, dynamic> toSlotJson() => kdf == kdfArgon2id
      ? {'kdf': kdfArgon2id, 'm': memoryKiB, 't': timeCost, 'p': parallelism}
      : {'kdf': kdfPbkdf2, 'iter': iterations};

  /// 槽位 JSON 解析。`kdf` 字段缺失 → 返回 [legacyDefault]（旧数据兼容：
  /// PBKDF2 时代的槽位不带 kdf 字段）；字段存在但畸形 → 抛
  /// [ArgumentError]（fail-closed，上游按「密码错误/数据损坏」处理）。
  static KdfParams fromSlotJson(
    Map<String, dynamic> json, {
    required KdfParams legacyDefault,
  }) {
    final k = json['kdf'];
    if (k == null) return legacyDefault;
    if (k == kdfArgon2id) {
      final m = json['m'];
      final t = json['t'];
      final p = json['p'];
      if (m is int &&
          m > 0 &&
          m <= maxMemoryKiB &&
          t is int &&
          t > 0 &&
          t <= maxTimeCost &&
          p is int &&
          p > 0 &&
          p <= maxParallelism) {
        return KdfParams.argon2id(memoryKiB: m, timeCost: t, parallelism: p);
      }
      throw ArgumentError('Argon2id 槽位参数畸形或超限');
    }
    if (k == kdfPbkdf2) {
      final it = json['iter'];
      if (it is int && it > 0 && it <= maxPbkdf2Iterations) {
        return KdfParams.pbkdf2(it);
      }
      throw ArgumentError('PBKDF2 槽位参数畸形或超限');
    }
    throw ArgumentError('不支持的 KDF 类型: $k');
  }

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.kdf == kdf &&
      other.iterations == iterations &&
      other.memoryKiB == memoryKiB &&
      other.timeCost == timeCost &&
      other.parallelism == parallelism;

  @override
  int get hashCode =>
      Object.hash(kdf, iterations, memoryKiB, timeCost, parallelism);

  @override
  String toString() => kdf == kdfArgon2id
      ? 'Argon2id(m=$memoryKiB,t=$timeCost,p=$parallelism)'
      : 'PBKDF2(iter=$iterations)';
}
