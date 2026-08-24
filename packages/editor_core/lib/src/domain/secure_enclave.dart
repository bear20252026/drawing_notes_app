// editor_core——SecureEnclave（中文平台 TEE 调研借鉴——2026-08-22）。
//
// 可信执行环境（TEE）模型本地化——硬件隔离的密钥存储。
// 纯 Dart 不可变模型（模型层——实际硬件集成在移动端 Secure Enclave）——不搞崩。
//
// 参考：中文平台调研——《基于可信执行环境的层次角色基分级加密方案》
//（信息网络安全 2026——Intel SGX）+ 鲲鹏 TrustZone 套件（国密 SM4 硬件加速
// + 远程证明）——加密操作/密钥管理置于 TEE 硬件隔离。
library;

/// 硬件密钥（SecureEnclave/TEE 本地化——不可变）。
///
/// 密钥存储在硬件隔离环境（Secure Enclave/TrustZone/SGX）——
/// 操作系统/应用层无法读取密钥明文（防内存窃取/进程注入）。
class SecureEnclaveKey {
  const SecureEnclaveKey({
    required this.keyId,
    this.hardwareBacked = true,
    this.exportable = false,
    this.attestation = '',
    this.wrappedKey = const [],
  });

  final String keyId;

  /// 是否硬件备份（TEE 内生成/存储——不可被应用层读取）。
  final bool hardwareBacked;

  /// 是否可导出（false = 密钥永不离开硬件——最强保护）。
  final bool exportable;

  /// 远程证明数据（Attestation——证明密钥确实在硬件中——TEE 特性）。
  final String attestation;

  /// 包裹密钥（KEK 包裹——防硬件迁移泄露）。
  final List<int> wrappedKey;

  SecureEnclaveKey copyWith({
    bool? exportable,
    String? attestation,
    List<int>? wrappedKey,
  }) {
    return SecureEnclaveKey(
      keyId: keyId,
      hardwareBacked: hardwareBacked,
      exportable: exportable ?? this.exportable,
      attestation: attestation ?? this.attestation,
      wrappedKey: wrappedKey ?? this.wrappedKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SecureEnclaveKey && keyId == other.keyId;

  @override
  int get hashCode => keyId.hashCode;
}

/// Secure Enclave 服务（TEE 模型——积木式纯 Dart 模型层）。
///
/// 实际硬件集成在移动端（iOS Secure Enclave / Android StrongBox——
/// 或 ARM TrustZone）——此模型层管理密钥生命周期/远程证明/导出策略。
class SecureEnclaveService {
  const SecureEnclaveService();

  /// 在 TEE 内生成密钥（硬件备份——不可导出）。
  SecureEnclaveKey generateKey(String keyId) {
    // 实际在硬件内生成（Secure Enclave KeyPair）——
    // 模型层返回密钥元数据（密钥明文永不出硬件）。
    return SecureEnclaveKey(
      keyId: keyId,
      hardwareBacked: true,
      exportable: false,
      attestation: _generateAttestation(keyId),
    );
  }

  /// 存储外部密钥到 TEE（包裹后存入——防硬件迁移泄露）。
  SecureEnclaveKey importKey({
    required String keyId,
    required List<int> keyMaterial,
    required List<int> kek,
  }) {
    // 实际用 KEK 包裹后存入硬件——模型层简化 XOR。
    final wrapped = List<int>.generate(
      keyMaterial.length,
      (i) => keyMaterial[i] ^ kek[i % kek.length],
    );
    return SecureEnclaveKey(
      keyId: keyId,
      hardwareBacked: true,
      exportable: false,
      wrappedKey: wrapped,
    );
  }

  /// 检查密钥是否硬件备份。
  bool isHardwareBacked(SecureEnclaveKey key) => key.hardwareBacked;

  /// 检查密钥是否可导出（安全审计——不可导出 = 最强保护）。
  bool canExport(SecureEnclaveKey key) => key.exportable;

  /// 生成远程证明（Attestation——证明密钥在硬件中——TEE 特性）。
  String _generateAttestation(String keyId) {
    // 简化：keyId 派生证明标识（实际为硬件签名证明）。
    return 'attest-$keyId-${DateTime.now().millisecondsSinceEpoch}';
  }
}
