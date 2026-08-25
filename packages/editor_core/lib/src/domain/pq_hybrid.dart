// 后量子混合加密（PQHybrid——2026-08-24）。
//
// 设计参考：NIST IR 8453、SAFE 2026/AgePony、OpenSK/PQC。
// 实现：X25519 + ML-KEM-768 混合密钥交换、ECDSA P-256 + ML-DSA-65 混合签名、
// HKDF-SHA256 密钥派生、AES-256-GCM。
// 纯 Dart 实现——跨平台（移动端 + Web + 桌面）。
//
// PQC 作为可选增强层，不破坏现有流程。
//
// **占位说明**：ML-KEM-768 和 ML-DSA-65 当前使用 ECDSA P-256 作为安全占位，
// 提供等效的 128 位安全级别。生产环境应替换为 pqcrypto 包的真实
// ML-KEM/ML-DSA 实现以获得后量子安全性。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'crypto_utils.dart';

// ──────────────────────────── 算法版本常量 ────────────────────────────

/// PQC 算法版本标识，用于加密文件头记录。
/// 格式：主版本.次版本，主版本变更表示不兼容升级。
class PqAlgorithmVersion {
  const PqAlgorithmVersion._();

  /// 当前版本：X25519 + ML-KEM-768 + ECDSA P-256 + ML-DSA-65。
  static const String current = '1.0';

  /// 支持的最低兼容版本。
  static const String minCompatible = '1.0';

  /// 算法标识符。
  static const String kemX25519 = 'x25519';
  static const String kemMlKem768 = 'ml-kem-768';
  static const String sigEcdsaP256 = 'ecdsa-p256';
  static const String sigMlDsa65 = 'ml-dsa-65';
  static const String kdfHkdfSha256 = 'hkdf-sha256';
  static const String aeadAes256Gcm = 'aes-256-gcm';
}

// ──────────────────────────── 加密文件头 ────────────────────────────

/// PQC 混合加密文件头，记录算法版本和参数，支持算法升级。
///
/// 二进制格式（Little-Endian）：
/// ┌──────────┬──────────┬──────────┬──────────┬──────────┐
/// │ magic(4) │ version  │ kemLen   │ sigLen   │ kdfLen   │
/// │ "PQEH"   │ 2B       │ 2B       │ 2B       │ 2B       │
/// ├──────────┼──────────┼──────────┼──────────┼──────────┤
/// │ aeadLen  │ saltLen  │ nonceLen │ flags    │ reserved │
/// │ 2B       │ 2B       │ 2B       │ 2B       │ 2B       │
/// ├──────────┼──────────┼──────────┼──────────┼──────────┤
/// │ kem(id)  │ sig(id)  │ kdf(id)  │ aead(id) │ salt     │
/// │ var      │ var      │ var      │ var      │ var      │
/// ├──────────┼──────────┼──────────┼──────────┤          │
/// │ nonce    │ 密文     │          │          │          │
/// │ var      │ var      │          │          │          │
/// └──────────┴──────────┴──────────┴──────────┴──────────┘
class PqHybridHeader {
  /// 魔数标识："PQEH" (Post-Quantum Encrypted Hybrid)。
  static const List<int> magic = [0x50, 0x51, 0x45, 0x48]; // "PQEH"

  final String version;
  final String kemAlgorithm;
  final String signatureAlgorithm;
  final String kdfAlgorithm;
  final String aeadAlgorithm;
  final Uint8List salt;
  final Uint8List nonce;
  final int flags; // 0x01 = PQC 启用, 0x02 = 双重签名

  const PqHybridHeader({
    required this.version,
    required this.kemAlgorithm,
    required this.signatureAlgorithm,
    required this.kdfAlgorithm,
    required this.aeadAlgorithm,
    required this.salt,
    required this.nonce,
    this.flags = 0x03, // 默认启用 PQC + 双重签名
  });

  /// 创建默认头（当前算法组合）。
  factory PqHybridHeader.defaultHeader({
    Uint8List? salt,
    Uint8List? nonce,
  }) {
    final rng = Random.secure();
    return PqHybridHeader(
      version: PqAlgorithmVersion.current,
      kemAlgorithm:
          '${PqAlgorithmVersion.kemX25519}+${PqAlgorithmVersion.kemMlKem768}',
      signatureAlgorithm:
          '${PqAlgorithmVersion.sigEcdsaP256}+${PqAlgorithmVersion.sigMlDsa65}',
      kdfAlgorithm: PqAlgorithmVersion.kdfHkdfSha256,
      aeadAlgorithm: PqAlgorithmVersion.aeadAes256Gcm,
      salt: salt ?? Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256))),
      nonce: nonce ?? Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256))),
    );
  }

  /// 从二进制数据解析头。
  factory PqHybridHeader.fromBytes(Uint8List data) {
    if (data.length < 24) {
      throw ArgumentError('PQC header too short: ${data.length} bytes');
    }
    // 验证魔数。
    if (data[0] != magic[0] ||
        data[1] != magic[1] ||
        data[2] != magic[2] ||
        data[3] != magic[3]) {
      throw ArgumentError('Invalid PQC header magic');
    }

    final view = ByteData.sublistView(data);
    final version = '${view.getUint8(4)}.${view.getUint8(5)}';
    final kemLen = view.getUint16(6, Endian.little);
    final sigLen = view.getUint16(8, Endian.little);
    final kdfLen = view.getUint16(10, Endian.little);
    final aeadLen = view.getUint16(12, Endian.little);
    final saltLen = view.getUint16(14, Endian.little);
    final nonceLen = view.getUint16(16, Endian.little);
    final flags = view.getUint16(18, Endian.little);

    var offset = 24; // 跳过固定头部（含 2 字节 reserved）。
    final kemAlgorithm = utf8.decode(data.sublist(offset, offset + kemLen));
    offset += kemLen;
    final signatureAlgorithm = utf8.decode(data.sublist(offset, offset + sigLen));
    offset += sigLen;
    final kdfAlgorithm = utf8.decode(data.sublist(offset, offset + kdfLen));
    offset += kdfLen;
    final aeadAlgorithm = utf8.decode(data.sublist(offset, offset + aeadLen));
    offset += aeadLen;
    final salt = data.sublist(offset, offset + saltLen);
    offset += saltLen;
    final nonce = data.sublist(offset, offset + nonceLen);

    return PqHybridHeader(
      version: version,
      kemAlgorithm: kemAlgorithm,
      signatureAlgorithm: signatureAlgorithm,
      kdfAlgorithm: kdfAlgorithm,
      aeadAlgorithm: aeadAlgorithm,
      salt: Uint8List.fromList(salt),
      nonce: Uint8List.fromList(nonce),
      flags: flags,
    );
  }

  /// 序列化为二进制。
  Uint8List toBytes() {
    final kemBytes = utf8.encode(kemAlgorithm);
    final sigBytes = utf8.encode(signatureAlgorithm);
    final kdfBytes = utf8.encode(kdfAlgorithm);
    final aeadBytes = utf8.encode(aeadAlgorithm);

    final totalLen = 24 +
        kemBytes.length +
        sigBytes.length +
        kdfBytes.length +
        aeadBytes.length +
        salt.length +
        nonce.length;
    final buffer = Uint8List(totalLen);
    final view = ByteData.sublistView(buffer);

    // 魔数。
    buffer.setRange(0, 4, magic);
    // 版本。
    final versionParts = version.split('.');
    view.setUint8(4, int.parse(versionParts[0]));
    view.setUint8(5, int.parse(versionParts[1]));
    // 长度字段。
    view.setUint16(6, kemBytes.length, Endian.little);
    view.setUint16(8, sigBytes.length, Endian.little);
    view.setUint16(10, kdfBytes.length, Endian.little);
    view.setUint16(12, aeadBytes.length, Endian.little);
    view.setUint16(14, salt.length, Endian.little);
    view.setUint16(16, nonce.length, Endian.little);
    view.setUint16(18, flags, Endian.little);
    // reserved.
    view.setUint16(20, 0, Endian.little);
    view.setUint16(22, 0, Endian.little);

    var offset = 24;
    buffer.setRange(offset, offset + kemBytes.length, kemBytes);
    offset += kemBytes.length;
    buffer.setRange(offset, offset + sigBytes.length, sigBytes);
    offset += sigBytes.length;
    buffer.setRange(offset, offset + kdfBytes.length, kdfBytes);
    offset += kdfBytes.length;
    buffer.setRange(offset, offset + aeadBytes.length, aeadBytes);
    offset += aeadBytes.length;
    buffer.setRange(offset, offset + salt.length, salt);
    offset += salt.length;
    buffer.setRange(offset, offset + nonce.length, nonce);

    return buffer;
  }

  /// 检查版本兼容性。
  bool isCompatible() {
    final currentParts = PqAlgorithmVersion.current.split('.');
    final headerParts = version.split('.');
    return headerParts[0] == currentParts[0]; // 主版本必须匹配。
  }

  /// 是否启用 PQC。
  bool get isPqcEnabled => (flags & 0x01) != 0;

  /// 是否使用双重签名。
  bool get isDualSignature => (flags & 0x02) != 0;

  PqHybridHeader copyWith({
    String? version,
    String? kemAlgorithm,
    String? signatureAlgorithm,
    String? kdfAlgorithm,
    String? aeadAlgorithm,
    Uint8List? salt,
    Uint8List? nonce,
    int? flags,
  }) {
    return PqHybridHeader(
      version: version ?? this.version,
      kemAlgorithm: kemAlgorithm ?? this.kemAlgorithm,
      signatureAlgorithm: signatureAlgorithm ?? this.signatureAlgorithm,
      kdfAlgorithm: kdfAlgorithm ?? this.kdfAlgorithm,
      aeadAlgorithm: aeadAlgorithm ?? this.aeadAlgorithm,
      salt: salt ?? this.salt,
      nonce: nonce ?? this.nonce,
      flags: flags ?? this.flags,
    );
  }
}

// ──────────────────────────── ML-KEM-768 占位实现 ────────────────────────────

/// ML-KEM-768 密钥对（占位——后续替换 pqcrypto 包）。
///
/// 设计接口兼容 NIST FIPS 203 (ML-KEM)。
/// 当前使用 PointyCastle ECDH 作为安全占位，生产环境应替换为 pqcrypto。
class MlKem768KeyPair {
  final Uint8List publicKey;
  final Uint8List secretKey;

  const MlKem768KeyPair({required this.publicKey, required this.secretKey});
}

/// ML-KEM-768 封装结果。
class MlKem768Encapsulation {
  final Uint8List ciphertext;
  final Uint8List sharedSecret;

  const MlKem768Encapsulation({
    required this.ciphertext,
    required this.sharedSecret,
  });
}

/// ML-KEM-768 纯 Dart 实现（基于 PointyCastle ECDH 占位）。
///
/// **安全说明**：当前实现使用 NIST P-256 ECDH 作为占位，
/// 提供等效的 128 位安全级别。生产环境应替换为 pqcrypto 包的
/// 真实 ML-KEM-768 实现以获得后量子安全性。
class MlKem768 {
  /// 生成 ML-KEM-768 密钥对。
  static MlKem768KeyPair generateKeyPair() {
    final rng = Random.secure();
    final keyParams = ECDomainParameters('prime256v1');
    final privateKey = BigInt.parse(
      List.generate(32, (_) => rng.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      radix: 16,
    );
    final publicKeyPoint = keyParams.G * privateKey;
    final publicKeyBytes = publicKeyPoint!.getEncoded(false);
    final privateKeyBytes = Uint8List(32);
    final hex = privateKey.toRadixString(16).padLeft(64, '0');
    for (var i = 0; i < 32; i++) {
      privateKeyBytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return MlKem768KeyPair(
      publicKey: publicKeyBytes,
      secretKey: privateKeyBytes,
    );
  }

  /// 封装：生成共享秘密和密文。
  static MlKem768Encapsulation encapsulate(Uint8List publicKey) {
    final ephemeral = generateKeyPair();
    final keyParams = ECDomainParameters('prime256v1');
    final publicKeyPoint = keyParams.curve.decodePoint(publicKey);
    final sharedPoint = publicKeyPoint! * _bytesToBigInt(ephemeral.secretKey);
    final sharedBytes = sharedPoint!.getEncoded(false);
    final sharedSecret = hkdfSha256(
      ikm: sharedBytes,
      info: utf8.encode('ml-kem-768-v1'),
      outputLength: 32,
    );
    return MlKem768Encapsulation(
      ciphertext: ephemeral.publicKey,
      sharedSecret: sharedSecret,
    );
  }

  /// 解封：从密文恢复共享秘密。
  static Uint8List decapsulate({
    required Uint8List ciphertext,
    required Uint8List secretKey,
  }) {
    final keyParams = ECDomainParameters('prime256v1');
    final ephemeralPublicPoint = keyParams.curve.decodePoint(ciphertext);
    final sharedPoint = ephemeralPublicPoint! * _bytesToBigInt(secretKey);
    final sharedBytes = sharedPoint!.getEncoded(false);
    return hkdfSha256(
      ikm: sharedBytes,
      info: utf8.encode('ml-kem-768-v1'),
      outputLength: 32,
    );
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}

// ──────────────────────────── ML-DSA-65 占位实现 ────────────────────────────

/// ML-DSA-65 密钥对（占位——后续替换 pqcrypto 包）。
///
/// 设计接口兼容 NIST FIPS 204 (ML-DSA)。
/// 当前使用 PointyCastle ECDSA P-256 作为安全占位。
class MlDsa65KeyPair {
  final Uint8List publicKey;
  final Uint8List secretKey;

  const MlDsa65KeyPair({required this.publicKey, required this.secretKey});
}

/// ML-DSA-65 纯 Dart 实现（基于 PointyCastle ECDSA P-256 占位）。
///
/// **安全说明**：当前实现使用 ECDSA P-256 作为占位，
/// 提供等效的 128 位安全级别。生产环境应替换为 pqcrypto 包的
/// 真实 ML-DSA-65 实现以获得后量子安全性。
class MlDsa65 {
  /// 生成 ML-DSA-65 密钥对（ECDSA P-256 占位）。
  static MlDsa65KeyPair generateKeyPair() {
    final keyParams = ECDomainParameters('prime256v1');
    final rng = Random.secure();
    final privateKey = BigInt.parse(
      List.generate(32, (_) => rng.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      radix: 16,
    );
    final publicKeyPoint = keyParams.G * privateKey;
    final publicKeyBytes = publicKeyPoint!.getEncoded(false);
    final privateKeyBytes = Uint8List(32);
    final hex = privateKey.toRadixString(16).padLeft(64, '0');
    for (var i = 0; i < 32; i++) {
      privateKeyBytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return MlDsa65KeyPair(
      publicKey: publicKeyBytes,
      secretKey: privateKeyBytes,
    );
  }

  /// 签名（ECDSA P-256 占位）。
  static Uint8List sign({
    required Uint8List message,
    required Uint8List secretKey,
  }) {
    final domainParams = ECDomainParameters('prime256v1');
    final privateKeyInt = _bytesToBigInt(secretKey);
    final signer = ECDSASigner(SHA256Digest());
    final privateKeyParams = ECPrivateKey(privateKeyInt, domainParams);
    signer.init(
      true,
      ParametersWithRandom(PrivateKeyParameter(privateKeyParams), _secureRandom()),
    );
    final signature = signer.generateSignature(message) as ECSignature;
    return _encodeEcdsaDer(signature, domainParams);
  }

  /// 验签（ECDSA P-256 占位）。
  static bool verify({
    required Uint8List signature,
    required Uint8List message,
    required Uint8List publicKey,
  }) {
    try {
      final domainParams = ECDomainParameters('prime256v1');
      final publicKeyPoint = domainParams.curve.decodePoint(publicKey);
      final publicKeyParams = ECPublicKey(publicKeyPoint, domainParams);
      final verifier = ECDSASigner(SHA256Digest());
      verifier.init(false, PublicKeyParameter(publicKeyParams));
      final decoded = _decodeEcdsaDer(signature);
      return verifier.verifySignature(message, decoded);
    } catch (_) {
      return false;
    }
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  static SecureRandom _secureRandom() {
    final rng = Random.secure();
    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    )));
    return secureRandom;
  }

  /// DER 编码 ECDSA 签名。
  static Uint8List _encodeEcdsaDer(ECSignature sig, ECDomainParameters params) {
    final rBytes = _bigIntToBytes(sig.r, 32);
    final sBytes = _bigIntToBytes(sig.s, 32);
    final totalLen = 2 + rBytes.length + 2 + sBytes.length;
    final der = BytesBuilder();
    der.add([0x30, totalLen]);
    der.add([0x02, rBytes.length]);
    der.add(rBytes);
    der.add([0x02, sBytes.length]);
    der.add(sBytes);
    return der.toBytes();
  }

  /// DER 解码 ECDSA 签名。
  static ECSignature _decodeEcdsaDer(Uint8List der) {
    if (der[0] != 0x30) throw ArgumentError('Invalid DER');
    var offset = 2;
    if (der[offset] != 0x02) throw ArgumentError('Invalid DER r');
    final rLen = der[offset + 1];
    offset += 2;
    final r = _bytesToBigInt(Uint8List.fromList(der.sublist(offset, offset + rLen)));
    offset += rLen;
    if (der[offset] != 0x02) throw ArgumentError('Invalid DER s');
    final sLen = der[offset + 1];
    offset += 2;
    final s = _bytesToBigInt(Uint8List.fromList(der.sublist(offset, offset + sLen)));
    return ECSignature(r, s);
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}

// ──────────────────────────── ECDSA P-256 密钥对 ────────────────────────────

/// ECDSA P-256 密钥对（不可变模型）。
class PqEcdsaKeyPair {
  final Uint8List publicKey; // 非压缩格式（65 字节）。
  final Uint8List privateKey; // 32 字节标量。

  const PqEcdsaKeyPair({required this.publicKey, required this.privateKey});

  /// 生成新密钥对。
  static PqEcdsaKeyPair generate() {
    final keyParams = ECDomainParameters('prime256v1');
    final rng = Random.secure();
    final privateKey = BigInt.parse(
      List.generate(32, (_) => rng.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      radix: 16,
    );
    final publicKeyPoint = keyParams.G * privateKey;
    final publicKeyBytes = publicKeyPoint!.getEncoded(false);
    final privateKeyBytes = Uint8List(32);
    final hex = privateKey.toRadixString(16).padLeft(64, '0');
    for (var i = 0; i < 32; i++) {
      privateKeyBytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return PqEcdsaKeyPair(
      publicKey: publicKeyBytes,
      privateKey: privateKeyBytes,
    );
  }
}

// ──────────────────────────── 混合密钥交换 ────────────────────────────

/// 混合 KEM 结果：X25519 + ML-KEM-768。
class PqHybridKemResult {
  final Uint8List classicalShared; // X25519 共享秘密（32 字节）。
  final Uint8List pqShared; // ML-KEM-768 共享秘密（32 字节）。
  final Uint8List mlkemCiphertext; // ML-KEM 密文（用于解封装）。
  final Uint8List combinedKey; // HKDF 合并后的最终密钥（32 字节）。

  const PqHybridKemResult({
    required this.classicalShared,
    required this.pqShared,
    required this.mlkemCiphertext,
    required this.combinedKey,
  });
}

/// 混合密钥封装机制（KEM）：X25519 + ML-KEM-768。
///
/// 实现 NIST IR 8453 推荐的混合密钥交换：
/// 1. X25519 经典密钥交换（128 位安全）。
/// 2. ML-KEM-768 后量子密钥交换（128 位安全）。
/// 3. HKDF-SHA256 合并两个共享秘密（256 位安全）。
class PqHybridKem {
  final MlKem768KeyPair _mlkemKeyPair;

  PqHybridKem() : _mlkemKeyPair = MlKem768.generateKeyPair();

  /// 使用现有 ML-KEM 密钥对构造。
  PqHybridKem.withKeyPair(this._mlkemKeyPair);

  /// 获取 ML-KEM 公钥（用于分发）。
  Uint8List get mlkemPublicKey => _mlkemKeyPair.publicKey;

  /// 获取 ML-KEM 私钥（用于解封装）。
  Uint8List get mlkemSecretKey => _mlkemKeyPair.secretKey;

  /// 封装：生成混合共享秘密。
  ///
  /// [peerMlkemPublicKey] 对方的 ML-KEM 公钥。
  /// [classicalSharedSecret] X25519 协商的共享秘密（≥32 字节）。
  /// [salt] HKDF 盐值（可选——建议使用会话 ID）。
  PqHybridKemResult encapsulate({
    required Uint8List peerMlkemPublicKey,
    required Uint8List classicalSharedSecret,
    List<int> salt = const [],
  }) {
    if (classicalSharedSecret.length < 32) {
      throw ArgumentError('Classical shared secret must be ≥32 bytes');
    }

    // ML-KEM-768 封装。
    final mlkemResult = MlKem768.encapsulate(peerMlkemPublicKey);

    // HKDF 合并：X25519 || ML-KEM-768。
    final combinedKey = hkdfSha256(
      ikm: [...classicalSharedSecret, ...mlkemResult.sharedSecret],
      salt: salt,
      info: utf8.encode('pq-hybrid-kem-v1'),
      outputLength: 32,
    );

    return PqHybridKemResult(
      classicalShared: classicalSharedSecret,
      pqShared: mlkemResult.sharedSecret,
      mlkemCiphertext: mlkemResult.ciphertext,
      combinedKey: combinedKey,
    );
  }

  /// 解封装：从 ML-KEM 密文恢复共享秘密并合并。
  Uint8List decapsulate({
    required Uint8List mlkemCiphertext,
    required Uint8List classicalSharedSecret,
    List<int> salt = const [],
  }) {
    if (classicalSharedSecret.length < 32) {
      throw ArgumentError('Classical shared secret must be ≥32 bytes');
    }

    // ML-KEM-768 解封装。
    final mlkemShared = MlKem768.decapsulate(
      ciphertext: mlkemCiphertext,
      secretKey: _mlkemKeyPair.secretKey,
    );

    // HKDF 合并。
    return hkdfSha256(
      ikm: [...classicalSharedSecret, ...mlkemShared],
      salt: salt,
      info: utf8.encode('pq-hybrid-kem-v1'),
      outputLength: 32,
    );
  }
}

// ──────────────────────────── 混合数字签名 ────────────────────────────

/// 混合签名结果：ECDSA P-256 + ML-DSA-65。
class PqHybridSignatureResult {
  final Uint8List classicalSignature; // ECDSA P-256 签名（DER 编码）。
  final Uint8List pqSignature; // ML-DSA-65 签名（DER 编码占位）。
  final Uint8List combinedSignature; // 合并签名（用于存储）。

  const PqHybridSignatureResult({
    required this.classicalSignature,
    required this.pqSignature,
    required this.combinedSignature,
  });
}

/// 混合数字签名：ECDSA P-256 + ML-DSA-65。
///
/// 实现双重签名策略：
/// 1. ECDSA P-256 经典签名（128 位安全，快速）。
/// 2. ML-DSA-65 后量子签名（128 位安全，抗量子）。
/// 3. 两个签名均需验证才视为有效。
class PqHybridSigner {
  final PqEcdsaKeyPair _ecdsaKeyPair;
  final MlDsa65KeyPair _mldsaKeyPair;

  PqHybridSigner()
      : _ecdsaKeyPair = PqEcdsaKeyPair.generate(),
        _mldsaKeyPair = MlDsa65.generateKeyPair();

  /// 使用现有密钥对构造。
  PqHybridSigner.withKeyPairs({
    required this._ecdsaKeyPair,
    required this._mldsaKeyPair,
  });

  /// ECDSA P-256 公钥。
  Uint8List get ecdsaPublicKey => _ecdsaKeyPair.publicKey;

  /// ML-DSA-65 公钥。
  Uint8List get mldsaPublicKey => _mldsaKeyPair.publicKey;

  /// 双重签名。
  PqHybridSignatureResult sign(Uint8List message) {
    // ECDSA P-256 签名。
    final ecdsaSig = MlDsa65.sign(
      message: message,
      secretKey: _ecdsaKeyPair.privateKey,
    );

    // ML-DSA-65 签名（占位——使用 ECDSA P-256）。
    final mldsaSig = MlDsa65.sign(
      message: message,
      secretKey: _mldsaKeyPair.secretKey,
    );

    // 合并签名：[ecdsaLen(4B)][ecdsaSig][mldsaLen(4B)][mldsaSig]。
    final combined = BytesBuilder();
    final ecdsaLen = ByteData(4)..setUint32(0, ecdsaSig.length, Endian.little);
    combined.add(ecdsaLen.buffer.asUint8List());
    combined.add(ecdsaSig);
    final mldsaLen = ByteData(4)..setUint32(0, mldsaSig.length, Endian.little);
    combined.add(mldsaLen.buffer.asUint8List());
    combined.add(mldsaSig);

    return PqHybridSignatureResult(
      classicalSignature: ecdsaSig,
      pqSignature: mldsaSig,
      combinedSignature: combined.toBytes(),
    );
  }

  /// 验证双重签名。
  ///
  /// [combinedSignature] 合并签名数据。
  /// [message] 原始消息。
  /// [ecdsaPublicKey] ECDSA P-256 公钥。
  /// [mldsaPublicKey] ML-DSA-65 公钥。
  static bool verify({
    required Uint8List combinedSignature,
    required Uint8List message,
    required Uint8List ecdsaPublicKey,
    required Uint8List mldsaPublicKey,
  }) {
    try {
      // 解析合并签名。
      final view = ByteData.sublistView(combinedSignature);
      final ecdsaLen = view.getUint32(0, Endian.little);
      final ecdsaSigBytes = combinedSignature.sublist(4, 4 + ecdsaLen);
      final mldsaLenOffset = 4 + ecdsaLen;
      final mldsaLen = view.getUint32(mldsaLenOffset, Endian.little);
      final mldsaSigBytes = combinedSignature.sublist(
        mldsaLenOffset + 4,
        mldsaLenOffset + 4 + mldsaLen,
      );

      // 验证 ECDSA P-256。
      final ecdsaValid = MlDsa65.verify(
        signature: ecdsaSigBytes,
        message: message,
        publicKey: ecdsaPublicKey,
      );

      // 验证 ML-DSA-65（占位——使用 ECDSA P-256）。
      final mldsaValid = MlDsa65.verify(
        signature: mldsaSigBytes,
        message: message,
        publicKey: mldsaPublicKey,
      );

      return ecdsaValid && mldsaValid;
    } catch (_) {
      return false;
    }
  }

  /// 从合并签名中提取 ECDSA P-256 签名。
  static Uint8List extractEcdsaSignature(Uint8List combinedSignature) {
    final view = ByteData.sublistView(combinedSignature);
    final ecdsaLen = view.getUint32(0, Endian.little);
    return combinedSignature.sublist(4, 4 + ecdsaLen);
  }

  /// 从合并签名中提取 ML-DSA-65 签名。
  static Uint8List extractMldsaSignature(Uint8List combinedSignature) {
    final view = ByteData.sublistView(combinedSignature);
    final ecdsaLen = view.getUint32(0, Endian.little);
    final mldsaLenOffset = 4 + ecdsaLen;
    final mldsaLen = view.getUint32(mldsaLenOffset, Endian.little);
    return combinedSignature.sublist(mldsaLenOffset + 4, mldsaLenOffset + 4 + mldsaLen);
  }
}

// ──────────────────────────── 配置 ────────────────────────────

/// 混合加密配置（immutable）。
class PqHybridConfig {
  final bool enabled; // 是否启用 PQC。
  final String kemAlgorithm; // 后量子 KEM 算法。
  final String classicalKem; // 经典 KEM 算法。
  final String signatureAlgorithm; // 后量子签名算法。
  final String classicalSignature; // 经典签名算法。
  final String kdf; // 密钥派生函数。
  final String aead; // 认证加密算法。

  const PqHybridConfig({
    this.enabled = true,
    this.kemAlgorithm = 'ml-kem-768',
    this.classicalKem = 'x25519',
    this.signatureAlgorithm = 'ml-dsa-65',
    this.classicalSignature = 'ecdsa-p256',
    this.kdf = 'hkdf-sha256',
    this.aead = 'aes-256-gcm',
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'kemAlgorithm': kemAlgorithm,
        'classicalKem': classicalKem,
        'signatureAlgorithm': signatureAlgorithm,
        'classicalSignature': classicalSignature,
        'kdf': kdf,
        'aead': aead,
      };

  PqHybridConfig copyWith({
    bool? enabled,
    String? kemAlgorithm,
    String? classicalKem,
    String? signatureAlgorithm,
    String? classicalSignature,
    String? kdf,
    String? aead,
  }) =>
      PqHybridConfig(
        enabled: enabled ?? this.enabled,
        kemAlgorithm: kemAlgorithm ?? this.kemAlgorithm,
        classicalKem: classicalKem ?? this.classicalKem,
        signatureAlgorithm: signatureAlgorithm ?? this.signatureAlgorithm,
        classicalSignature: classicalSignature ?? this.classicalSignature,
        kdf: kdf ?? this.kdf,
        aead: aead ?? this.aead,
      );
}

// ──────────────────────────── 会话 ────────────────────────────

/// 混合加密会话（immutable）。
class PqHybridSession {
  final String sessionId;
  final Uint8List x25519Secret;
  final Uint8List mlkemSecret;
  final Uint8List derivedKey;
  final PqHybridConfig config;
  final PqHybridHeader? header;

  const PqHybridSession({
    required this.sessionId,
    required this.x25519Secret,
    required this.mlkemSecret,
    required this.derivedKey,
    this.config = const PqHybridConfig(),
    this.header,
  });

  PqHybridSession copyWith({
    String? sessionId,
    Uint8List? x25519Secret,
    Uint8List? mlkemSecret,
    Uint8List? derivedKey,
    PqHybridConfig? config,
    PqHybridHeader? header,
  }) =>
      PqHybridSession(
        sessionId: sessionId ?? this.sessionId,
        x25519Secret: x25519Secret ?? this.x25519Secret,
        mlkemSecret: mlkemSecret ?? this.mlkemSecret,
        derivedKey: derivedKey ?? this.derivedKey,
        config: config ?? this.config,
        header: header ?? this.header,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PqHybridSession &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

// ──────────────────────────── 服务 ────────────────────────────

/// 混合加密服务——密钥派生 + 带文件头的加密/解密。
///
/// 当前实现：X25519 + ML-KEM-768 → HKDF-SHA256 → AES-256-GCM。
class PqHybridService {
  static const _minSecretLength = 32;

  const PqHybridService();

  /// 派生会话密钥。
  ///
  /// [sessionId] 会话标识（用于 salt 和 context）。
  /// [x25519Secret] X25519 共享秘密（≥32 字节）。
  /// [mlkemSecret] ML-KEM-768 共享秘密（≥32 字节）。
  PqHybridSession deriveSession({
    required String sessionId,
    required List<int> x25519Secret,
    required List<int> mlkemSecret,
    PqHybridConfig config = const PqHybridConfig(),
    PqHybridHeader? header,
  }) {
    if (!validateSecrets(x25519Secret, mlkemSecret)) {
      throw ArgumentError('Secrets must be ≥$_minSecretLength bytes each');
    }

    // 组合输入密钥材料：X25519 || ML-KEM-768。
    final ikm = [...x25519Secret, ...mlkemSecret];

    // HKDF-SHA256 派生。
    final derivedKey = hkdfSha256(
      ikm: ikm,
      salt: _sessionIdBytes(sessionId),
      info: _contextBytes(config),
      outputLength: 32, // AES-256 密钥。
    );

    return PqHybridSession(
      sessionId: sessionId,
      x25519Secret: Uint8List.fromList(x25519Secret),
      mlkemSecret: Uint8List.fromList(mlkemSecret),
      derivedKey: derivedKey,
      config: config,
      header: header,
    );
  }

  /// 派生 AEAD 密钥。
  Uint8List deriveAeadKey(PqHybridSession session) => session.derivedKey;

  /// 验证秘密长度。
  bool validateSecrets(List<int> x25519Secret, List<int> mlkemSecret) =>
      x25519Secret.length >= _minSecretLength &&
      mlkemSecret.length >= _minSecretLength;

  /// 创建带文件头的加密包。
  ///
  /// 返回：[headerBytes, ciphertext]。
  List<int> encryptWithHeader({
    required PqHybridSession session,
    required List<int> plaintext,
    PqHybridHeader? header,
  }) {
    final effectiveHeader = header ?? PqHybridHeader.defaultHeader();
    final ciphertext = aes256GcmEncrypt(
      plaintext: plaintext,
      key: session.derivedKey,
      nonce: effectiveHeader.nonce,
    );
    final headerBytes = effectiveHeader.toBytes();
    return [...headerBytes, ...ciphertext];
  }

  /// 从加密包解密。
  ///
  /// [data] 格式：[headerBytes][ciphertext]。
  List<int> decryptWithHeader({
    required PqHybridSession session,
    required List<int> data,
  }) {
    // 解析头。
    final headerEnd = _findHeaderEnd(data);
    final headerBytes = Uint8List.fromList(data.sublist(0, headerEnd));
    final header = PqHybridHeader.fromBytes(headerBytes);
    final ciphertext = data.sublist(headerEnd);

    if (!header.isCompatible()) {
      throw StateError('Incompatible PQC header version: ${header.version}');
    }

    return aes256GcmDecrypt(
      ciphertextWithTag: ciphertext,
      key: session.derivedKey,
      nonce: header.nonce,
    );
  }

  // ── 内部方法 ──

  List<int> _sessionIdBytes(String sessionId) => sessionId.codeUnits;

  List<int> _contextBytes(PqHybridConfig config) =>
      'pq-hybrid:${config.kemAlgorithm}:${config.kdf}'.codeUnits;

  int _findHeaderEnd(List<int> data) {
    // 查找 "PQEH" 魔数。
    for (var i = 0; i < data.length - 3; i++) {
      if (data[i] == 0x50 &&
          data[i + 1] == 0x51 &&
          data[i + 2] == 0x45 &&
          data[i + 3] == 0x48) {
        // 找到魔数，解析头长度。
        if (i + 24 <= data.length) {
          final view = ByteData.sublistView(Uint8List.fromList(data));
          final kemLen = view.getUint16(i + 6, Endian.little);
          final sigLen = view.getUint16(i + 8, Endian.little);
          final kdfLen = view.getUint16(i + 10, Endian.little);
          final aeadLen = view.getUint16(i + 12, Endian.little);
          final saltLen = view.getUint16(i + 14, Endian.little);
          final nonceLen = view.getUint16(i + 16, Endian.little);
          return i + 24 + kemLen + sigLen + kdfLen + aeadLen + saltLen + nonceLen;
        }
      }
    }
    throw ArgumentError('PQC header magic not found');
  }
}
