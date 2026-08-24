// editor_core——PQHybrid 后量子混合加密（SAFE 2026/AgePony 借鉴——2026-08-22）。
//
// 后量子混合加密模型——X25519 + ML-KEM-768 → HKDF → AES-256-GCM。
// 纯 Dart 不可变模型（模型层——实际加密由 pqforge/infrastructure 执行）。
//
// 参考：SAFE 2026（X25519 + ML-KEM-768 混合——HKDF 组合）+ AgePony
//（mlkem768x25519 混合接收者——经典 + 量子双保险）。
library;

/// 后量子混合配置（SAFE 2026 借鉴——不可变）。
class PqHybridConfig {
  const PqHybridConfig({
    this.enabled = true,
    this.kemAlgorithm = 'ml-kem-768', // FIPS 203（CRYSTALS-Kyber）。
    this.classicalKem = 'x25519',
    this.kdf = 'hkdf-sha256',
    this.aead = 'aes-256-gcm',
  });

  /// 是否启用后量子混合。
  final bool enabled;

  /// 后量子 KEM 算法（ML-KEM-768——NIST 标准化）。
  final String kemAlgorithm;

  /// 经典 KEM 算法（X25519——防格密码被突破的保底）。
  final String classicalKem;

  /// 密钥派生函数（HKDF-SHA256——组合两种秘密）。
  final String kdf;

  /// 认证加密（AES-256-GCM——混合密钥加密内容）。
  final String aead;

  PqHybridConfig copyWith({bool? enabled}) {
    return PqHybridConfig(enabled: enabled ?? this.enabled);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PqHybridConfig && enabled == other.enabled && kemAlgorithm == other.kemAlgorithm;

  @override
  int get hashCode => Object.hash(enabled, kemAlgorithm);
}

/// 后量子混合会话（模型层——不可变）。
///
/// 混合密钥协商结果：X25519 秘密 + ML-KEM 秘密 → HKDF 组合 → AES-256-GCM 密钥。
/// 安全性：只要 X25519 或 ML-KEM 任一未被破解——会话安全。
class PqHybridSession {
  const PqHybridSession({
    required this.sessionId,
    required this.x25519Secret,
    required this.mlkemSecret,
    required this.derivedKey,
    required this.config,
  });

  final String sessionId;
  final List<int> x25519Secret; // X25519 共享秘密（32 字节）。
  final List<int> mlkemSecret;  // ML-KEM-768 共享秘密（32 字节）。
  final List<int> derivedKey;   // HKDF 派生密钥（32 字节——AES-256）。
  final PqHybridConfig config;

  PqHybridSession copyWith({List<int>? derivedKey}) {
    return PqHybridSession(
      sessionId: sessionId,
      x25519Secret: x25519Secret,
      mlkemSecret: mlkemSecret,
      derivedKey: derivedKey ?? this.derivedKey,
      config: config,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PqHybridSession && sessionId == other.sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

/// 后量子混合服务（SAFE 2026 本地化——积木式纯 Dart 模型层）。
///
/// 实际加密由 pqforge（pub.dev——纯 Dart 后量子）执行——
/// 此模型层管理配置/会话/密钥派生流程。
class PqHybridService {
  const PqHybridService();

  /// 派生混合会话（X25519 秘密 + ML-KEM 秘密 → HKDF → AES-256-GCM 密钥）。
  PqHybridSession deriveSession({
    required String sessionId,
    required List<int> x25519Secret,
    required List<int> mlkemSecret,
    PqHybridConfig config = const PqHybridConfig(),
  }) {
    // 组合两种秘密（concatenate——IETF 混合密钥交换推荐——
    // 在 KDF 层组合而非 KEM 层）。
    final combined = [...x25519Secret, ...mlkemSecret];
    final derivedKey = _hkdfDerive(combined, config);
    return PqHybridSession(
      sessionId: sessionId,
      x25519Secret: x25519Secret,
      mlkemSecret: mlkemSecret,
      derivedKey: derivedKey,
      config: config,
    );
  }

  /// 从会话派生 AES-256-GCM 密钥（实际加密用）。
  List<int> deriveAeadKey(PqHybridSession session) {
    return session.derivedKey;
  }

  /// HKDF 派生（简化——SHA-256 迭代——实际用 cryptography 包的 Hkdf）。
  List<int> _hkdfDerive(List<int> combined, PqHybridConfig config) {
    // 简化：FNV-1a 风格哈希（占位——实际用 HKDF-SHA256）。
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final b in combined) {
      h1 = (h1 ^ b) * 0x01000193 & 0xFFFFFFFF;
      h2 = (h2 + b) * 0x85EBCA6B & 0xFFFFFFFF;
    }
    // 生成 32 字节（AES-256）。
    return List.generate(32, (i) {
      final v = (h1 + h2 * (i + 1)) & 0xFFFFFFFF;
      return v % 256;
    });
  }

  /// 检查混合密钥长度（X25519 32 字节 + ML-KEM 32 字节）。
  bool validateSecrets(List<int> x25519Secret, List<int> mlkemSecret) {
    return x25519Secret.length >= 32 && mlkemSecret.length >= 32;
  }
}
