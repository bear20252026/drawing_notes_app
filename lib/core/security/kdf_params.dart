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

  /// 新槽位 KDF 默认值（生产恒为 [argon2idProduction]）。
  ///
  /// 可变量唯一目的是测试注入（[testLight] / pbkdf2 小迭代），把派生成本
  /// 从 348ms 降到几十 ms——**生产代码禁止改写**。消费者：VaultFileCodec
  /// v3 写路径、EncryptionService v5 槽位；保险库走 VaultKeyService
  /// 构造参数（newSlotKdf），不读本字段。
  // ignore: avoid_renaming_method_parameters
  static KdfParams newSlotDefault = argon2idProduction;

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
      if (m is int && m > 0 && t is int && t > 0 && p is int && p > 0) {
        return KdfParams.argon2id(memoryKiB: m, timeCost: t, parallelism: p);
      }
      throw ArgumentError('Argon2id 槽位参数畸形');
    }
    if (k == kdfPbkdf2) {
      final it = json['iter'];
      if (it is int && it > 0) return KdfParams.pbkdf2(it);
      throw ArgumentError('PBKDF2 槽位参数畸形');
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
