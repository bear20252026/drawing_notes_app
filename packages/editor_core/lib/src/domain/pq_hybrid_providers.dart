// PQC 混合加密提供者抽象层（2026-08-25）
//
// 提供 PQC 算法的可插拔抽象接口，支持：
// 1. ML-KEM-768 密钥封装提供者（KEM Provider）
// 2. ML-DSA-65 数字签名提供者（Signature Provider）
// 3. Ed25519 + ML-DSA-65 双重签名实现
// 4. 未来无缝切换到 pqcrypto 包的真实 ML-KEM/ML-DSA 实现
//
// 设计参考：NIST IR 8453 混合密钥协商框架。
// 当前提供者为 ECDSA/Ed25519 占位实现；生产环境替换为
// pqcrypto 或 libsodium FFI 绑定以获得后量子安全性。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;

import 'pq_hybrid.dart';

// ──────────── PQC 提供者抽象接口 ────────────

/// ML-KEM 密钥封装提供者抽象接口。
///
/// 生产环境替换为 pqcrypto 的 ML-KEM-768 实现：
/// ```dart
/// class PqcryptoMlKemProvider implements PqcKemProvider { ... }
/// ```
abstract class PqcKemProvider {
  /// 生成密钥对。
  MlKem768KeyPair generateKeyPair();

  /// 封装：生成共享秘密和密文。
  MlKem768Encapsulation encapsulate(Uint8List publicKey);

  /// 解封装：从密文恢复共享秘密。
  Uint8List decapsulate({
    required Uint8List ciphertext,
    required Uint8List secretKey,
  });

  /// 算法标识符。
  String get algorithmId;
}

/// ML-DSA 数字签名提供者抽象接口（同步——因为占位实现不涉及异步 I/O）。
///
/// 生产环境替换为 pqcrypto 的 ML-DSA-65 实现：
/// ```dart
/// class PqcryptoMlDsaProvider implements PqcSignatureProvider { ... }
/// ```
abstract class PqcSignatureProvider {
  /// 生成密钥对。
  MlDsa65KeyPair generateKeyPair();

  /// 签名消息。
  Uint8List sign({
    required Uint8List message,
    required Uint8List secretKey,
  });

  /// 验证签名。
  bool verify({
    required Uint8List signature,
    required Uint8List message,
    required Uint8List publicKey,
  });

  /// 算法标识符。
  String get algorithmId;
}

/// 经典签名提供者抽象接口（异步——因为 Ed25519 依赖 cryptography 包异步 API）。
abstract class ClassicalSignatureProvider {
  /// 生成密钥对。返回 [publicKey, secretKey]。
  Future<List<Uint8List>> generateKeyPair();

  /// 签名消息。
  Future<Uint8List> sign({
    required Uint8List message,
    required Uint8List secretKey,
  });

  /// 验证签名。
  Future<bool> verify({
    required Uint8List signature,
    required Uint8List message,
    required Uint8List publicKey,
  });

  /// 算法标识符。
  String get algorithmId;
}

// ──────────── 占位实现：ECDSA P-256 KEM ────────────

/// ECDSA P-256 ECDH 占位 KEM 提供者。
///
/// **安全说明**：提供等效 128 位安全级别。
/// 生产环境应替换为 pqcrypto 的 ML-KEM-768 实现。
class PlaceholderMlKemProvider implements PqcKemProvider {
  const PlaceholderMlKemProvider();

  @override
  String get algorithmId => 'ml-kem-768';

  @override
  MlKem768KeyPair generateKeyPair() => MlKem768.generateKeyPair();

  @override
  MlKem768Encapsulation encapsulate(Uint8List publicKey) =>
      MlKem768.encapsulate(publicKey);

  @override
  Uint8List decapsulate({
    required Uint8List ciphertext,
    required Uint8List secretKey,
  }) =>
      MlKem768.decapsulate(ciphertext: ciphertext, secretKey: secretKey);
}

/// ECDSA P-256 占位签名提供者。
///
/// **安全说明**：提供等效 128 位安全级别。
/// 生产环境应替换为 pqcrypto 的 ML-DSA-65 实现。
class PlaceholderMlDsaProvider implements PqcSignatureProvider {
  const PlaceholderMlDsaProvider();

  @override
  String get algorithmId => 'ml-dsa-65';

  @override
  MlDsa65KeyPair generateKeyPair() => MlDsa65.generateKeyPair();

  @override
  Uint8List sign({
    required Uint8List message,
    required Uint8List secretKey,
  }) =>
      MlDsa65.sign(message: message, secretKey: secretKey);

  @override
  bool verify({
    required Uint8List signature,
    required Uint8List message,
    required Uint8List publicKey,
  }) =>
      MlDsa65.verify(
          signature: signature, message: message, publicKey: publicKey);
}

// ──────────── Ed25519 经典签名提供者 ────────────

/// Ed25519 经典签名提供者（基于 cryptography 包异步 API）。
///
/// 使用 Ed25519 (SHA-512 + Curve25519) 提供 128 位安全级别。
/// 确定性签名，快速，适合数字签名场景。
class Ed25519SignatureProvider implements ClassicalSignatureProvider {
  static final crypto.Ed25519 _algorithm = crypto.Ed25519();

  const Ed25519SignatureProvider();

  @override
  String get algorithmId => 'ed25519';

  @override
  Future<List<Uint8List>> generateKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final secretKey = await keyPair.extract();
    return [
      Uint8List.fromList(publicKey.bytes),
      Uint8List.fromList(secretKey.bytes),
    ];
  }

  @override
  Future<Uint8List> sign({
    required Uint8List message,
    required Uint8List secretKey,
  }) async {
    final keyPair = await _algorithm.newKeyPairFromSeed(secretKey);
    final signature = await _algorithm.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  @override
  Future<bool> verify({
    required Uint8List signature,
    required Uint8List message,
    required Uint8List publicKey,
  }) async {
    try {
      final cryptoPublicKey = crypto.SimplePublicKey(
        Uint8List.fromList(publicKey),
        type: crypto.KeyPairType.ed25519,
      );
      final cryptoSignature = crypto.Signature(
        Uint8List.fromList(signature),
        publicKey: cryptoPublicKey,
      );
      return await _algorithm.verify(message, signature: cryptoSignature);
    } catch (_) {
      return false;
    }
  }
}

/// ECDSA P-256 经典签名提供者（同步占位）。
class EcdsaP256SignatureProvider implements ClassicalSignatureProvider {
  const EcdsaP256SignatureProvider();

  @override
  String get algorithmId => 'ecdsa-p256';

  @override
  Future<List<Uint8List>> generateKeyPair() async {
    final keyPair = PqEcdsaKeyPair.generate();
    return [keyPair.publicKey, keyPair.privateKey];
  }

  @override
  Future<Uint8List> sign({
    required Uint8List message,
    required Uint8List secretKey,
  }) async =>
      MlDsa65.sign(message: message, secretKey: secretKey);

  @override
  Future<bool> verify({
    required Uint8List signature,
    required Uint8List message,
    required Uint8List publicKey,
  }) async =>
      MlDsa65.verify(
          signature: signature, message: message, publicKey: publicKey);
}

// ──────────── Ed25519 + ML-DSA-65 混合签名器 ────────────

/// Ed25519 + ML-DSA-65 双重混合签名器。
///
/// 实现任务要求的双重签名策略：
/// 1. Ed25519 经典签名（128 位安全，快速）
/// 2. ML-DSA-65 后量子签名（128 位安全，抗量子）
/// 3. 两个签名均需验证才视为有效。
///
/// 当前 ML-DSA-65 使用 ECDSA P-256 占位，
/// 生产环境替换为 pqcrypto 的 ML-DSA-65 实现。
class PqHybridSignerEd25519 {
  final ClassicalSignatureProvider _classicalProvider;
  final PqcSignatureProvider _pqProvider;

  List<Uint8List> _classicalKeyPair = [];
  MlDsa65KeyPair _pqKeyPair =
      MlDsa65KeyPair(publicKey: Uint8List(0), secretKey: Uint8List(0));

  PqHybridSignerEd25519({
    ClassicalSignatureProvider? classicalProvider,
    PqcSignatureProvider? pqProvider,
  })  : _classicalProvider =
            classicalProvider ?? const Ed25519SignatureProvider(),
        _pqProvider = pqProvider ?? const PlaceholderMlDsaProvider() {
    _classicalKeyPair = [Uint8List(0), Uint8List(0)];
    _pqKeyPair = _pqProvider.generateKeyPair();
  }

  /// 使用现有密钥对构造。
  PqHybridSignerEd25519.withKeyPairs({
    required List<Uint8List> classicalKeyPair,
    required MlDsa65KeyPair pqKeyPair,
    ClassicalSignatureProvider? classicalProvider,
    PqcSignatureProvider? pqProvider,
  })  : _classicalProvider =
            classicalProvider ?? const Ed25519SignatureProvider(),
        _pqProvider = pqProvider ?? const PlaceholderMlDsaProvider(),
        _classicalKeyPair = classicalKeyPair,
        _pqKeyPair = pqKeyPair;

  /// 初始化并生成经典密钥对（异步）。
  Future<void> initialize() async {
    _classicalKeyPair = await _classicalProvider.generateKeyPair();
  }

  /// 经典签名公钥（Ed25519：32 字节）。
  Uint8List get classicalPublicKey => _classicalKeyPair[0];

  /// 经典签名私钥。
  Uint8List get classicalSecretKey => _classicalKeyPair[1];

  /// PQ 签名公钥。
  Uint8List get pqPublicKey => _pqKeyPair.publicKey;

  /// PQ 签名私钥。
  Uint8List get pqSecretKey => _pqKeyPair.secretKey;

  /// 经典签名算法标识。
  String get classicalAlgorithmId => _classicalProvider.algorithmId;

  /// PQ 签名算法标识。
  String get pqAlgorithmId => _pqProvider.algorithmId;

  /// 双重签名（异步——Ed25519 需要异步操作）。
  ///
  /// 返回 [PqHybridSignatureResult]，包含两个独立签名和合并格式。
  Future<PqHybridSignatureResult> sign(Uint8List message) async {
    // Ed25519 签名。
    final classicalSig = await _classicalProvider.sign(
      message: message,
      secretKey: _classicalKeyPair[1],
    );

    // ML-DSA-65 签名（占位——使用 ECDSA P-256）。
    final pqSig = _pqProvider.sign(
      message: message,
      secretKey: _pqKeyPair.secretKey,
    );

    // 合并签名：[classicalLen(4B)][classicalSig][pqLen(4B)][pqSig]。
    final combined = BytesBuilder();
    final classicalLen =
        ByteData(4)..setUint32(0, classicalSig.length, Endian.little);
    combined.add(classicalLen.buffer.asUint8List());
    combined.add(classicalSig);
    final pqLen =
        ByteData(4)..setUint32(0, pqSig.length, Endian.little);
    combined.add(pqLen.buffer.asUint8List());
    combined.add(pqSig);

    return PqHybridSignatureResult(
      classicalSignature: classicalSig,
      pqSignature: pqSig,
      combinedSignature: combined.toBytes(),
    );
  }

  /// 验证双重签名（异步）。
  ///
  /// [combinedSignature] 合并签名数据。
  /// [message] 原始消息。
  /// [classicalPublicKey] 经典签名公钥。
  /// [pqPublicKey] PQ 签名公钥。
  static Future<bool> verify({
    required Uint8List combinedSignature,
    required Uint8List message,
    required Uint8List classicalPublicKey,
    required Uint8List pqPublicKey,
    ClassicalSignatureProvider? classicalProvider,
    PqcSignatureProvider? pqProvider,
  }) async {
    final cp = classicalProvider ?? const Ed25519SignatureProvider();
    final pp = pqProvider ?? const PlaceholderMlDsaProvider();

    try {
      // 解析合并签名。
      final view = ByteData.sublistView(combinedSignature);
      final classicalLen = view.getUint32(0, Endian.little);
      final classicalSigBytes =
          combinedSignature.sublist(4, 4 + classicalLen);
      final pqLenOffset = 4 + classicalLen;
      final pqLen = view.getUint32(pqLenOffset, Endian.little);
      final pqSigBytes = combinedSignature.sublist(
        pqLenOffset + 4,
        pqLenOffset + 4 + pqLen,
      );

      // 验证经典签名（异步）。
      final classicalValid = await cp.verify(
        signature: classicalSigBytes,
        message: message,
        publicKey: classicalPublicKey,
      );

      // 验证 PQ 签名。
      final pqValid = pp.verify(
        signature: pqSigBytes,
        message: message,
        publicKey: pqPublicKey,
      );

      return classicalValid && pqValid;
    } catch (_) {
      return false;
    }
  }

  /// 从合并签名中提取经典签名。
  static Uint8List extractClassicalSignature(Uint8List combinedSignature) {
    final view = ByteData.sublistView(combinedSignature);
    final classicalLen = view.getUint32(0, Endian.little);
    return combinedSignature.sublist(4, 4 + classicalLen);
  }

  /// 从合并签名中提取 PQ 签名。
  static Uint8List extractPqSignature(Uint8List combinedSignature) {
    final view = ByteData.sublistView(combinedSignature);
    final classicalLen = view.getUint32(0, Endian.little);
    final pqLenOffset = 4 + classicalLen;
    final pqLen = view.getUint32(pqLenOffset, Endian.little);
    return combinedSignature.sublist(
      pqLenOffset + 4,
      pqLenOffset + 4 + pqLen,
    );
  }
}

// ──────────── 算法版本协商 v2.0 ────────────

/// PQC 算法版本 v2.0 常量。
///
/// v2.0 使用 Ed25519 替代 ECDSA P-256 作为经典签名算法，
/// 同时保持向后兼容（v1.0 文件仍可解密）。
class PqAlgorithmVersionV2 {
  const PqAlgorithmVersionV2._();

  /// v2.0 版本：Ed25519 + ML-KEM-768 + ML-DSA-65。
  static const String current = '2.0';

  /// v1.0 版本：ECDSA P-256 + ML-KEM-768 + ML-DSA-65。
  static const String v1 = '1.0';

  /// v2.0 签名算法标识。
  static const String sigEd25519 = 'ed25519';
  static const String sigMlDsa65 = 'ml-dsa-65';
  static const String kemX25519 = 'x25519';
  static const String kemMlKem768 = 'ml-kem-768';
  static const String kdfHkdfSha256 = 'hkdf-sha256';
  static const String aeadAes256Gcm = 'aes-256-gcm';

  /// 创建 v2.0 默认头。
  static PqHybridHeader defaultHeaderV2({
    Uint8List? salt,
    Uint8List? nonce,
  }) {
    final rng = Random.secure();
    return PqHybridHeader(
      version: current,
      kemAlgorithm: '$kemX25519+$kemMlKem768',
      signatureAlgorithm: '$sigEd25519+$sigMlDsa65',
      kdfAlgorithm: kdfHkdfSha256,
      aeadAlgorithm: aeadAes256Gcm,
      salt: salt ??
          Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256))),
      nonce: nonce ??
          Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256))),
      flags: 0x03, // PQC + Dual Signature
    );
  }

  /// 检查版本兼容性（v1.x 和 v2.x 兼容）。
  static bool isCompatible(String version) {
    final parts = version.split('.');
    if (parts.length != 2) return false;
    final major = int.tryParse(parts[0]);
    // v1.x 和 v2.x 都兼容（同一大版本系列内）。
    return major != null && major >= 1 && major <= 2;
  }

  /// 检查是否为 v2.0 算法（Ed25519）。
  static bool isV2(String version) => version == current;

  /// 检查是否为 v1.0 算法（ECDSA P-256）。
  static bool isV1(String version) => version == v1;
}
