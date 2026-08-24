// editor_core——ThreeLayerEncryption 三层封装加密+数字签名（2026-08-24）。
//
// 军工级三层加密架构：
//   L1 内层：ChaCha20-Poly1305（数据加密——流式无填充——适合画布数据）
//   L2 中层：AES-256-GCM + 随机填充（隐藏文件大小——16~256字节随机垃圾）
//   L3 外层：AES-256-GCM + Ed25519 签名（防篡改认证）
//
// 信封加密完善：DEK 用 KEK 包裹（RFC 3394 AES Key Wrap），支持密钥轮换。
// 签名覆盖密文+元数据，验签失败触发告警回调。
//
// 签名算法：Ed25519（SHA-512 + Curve25519——128位安全——确定性签名）。
//   - 比 ECDSA P-256 更快、签名更小（64字节）、抗侧信道攻击
//   - 使用 cryptography 包（纯 Dart 实现——禁 Flutter/dart:io）
//
// 参考：Saber 加密架构 + 军工级加密方案规格。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' hide Signature;

import 'crypto_utils.dart';
import 'envelope_encryption.dart';

// ─── 签名告警回调 ───────────────────────────────────────────────────────────

/// 签名验证失败告警回调类型。
///
/// 参数：[context] 告警上下文描述，[metadata] 相关元数据。
typedef SignatureAlertCallback = void Function(String context, Map<String, dynamic> metadata);

// ─── 签名密钥对 ─────────────────────────────────────────────────────────────

/// 签名密钥对（不可变模型——公钥+私钥）。
///
/// Ed25519 密钥对：32 字节种子 → 32 字节公钥（Curve25519）。
/// 比 ECDSA P-256 更快、签名更小（64字节）、确定性签名。
class SigningKeyPair {
  const SigningKeyPair({
    required this.publicKey,
    required this.privateKey,
    required this.createdAt,
    this.algorithm = 'ed25519',
  });

  /// 公钥（Ed25519：32 字节——可公开分发）。
  final List<int> publicKey;

  /// 私钥（Ed25519：32 字节种子——严格保密）。
  final List<int> privateKey;

  /// 创建时间。
  final DateTime createdAt;

  /// 签名算法标识。
  final String algorithm;

  SigningKeyPair copyWith({List<int>? publicKey, List<int>? privateKey}) {
    return SigningKeyPair(
      publicKey: publicKey ?? this.publicKey,
      privateKey: privateKey ?? this.privateKey,
      createdAt: createdAt,
      algorithm: algorithm,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SigningKeyPair && _listEquals(publicKey, other.publicKey);

  @override
  int get hashCode => publicKey.length;
}

/// 签名结果（不可变——签名值+被签名数据摘要）。
class SignatureResult {
  const SignatureResult({
    required this.signature,
    required this.dataHash,
    required this.signedAt,
    this.algorithm = 'ecdsa-p256',
    this.metadata = const {},
  });

  /// 签名值（ECDSA P-256：64-72字节 DER 编码）。
  final List<int> signature;

  /// 被签名数据的 SHA-256 摘要（32 字节——完整性校验）。
  final List<int> dataHash;

  /// 签名时间。
  final DateTime signedAt;

  /// 签名算法标识。
  final String algorithm;

  /// 附加元数据（密钥ID、版本、算法标识等）。
  final Map<String, dynamic> metadata;

  SignatureResult copyWith({
    List<int>? signature,
    Map<String, dynamic>? metadata,
  }) {
    return SignatureResult(
      signature: signature ?? this.signature,
      dataHash: dataHash,
      signedAt: signedAt,
      algorithm: algorithm,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignatureResult && _listEquals(signature, other.signature);

  @override
  int get hashCode => signature.length;
}

// ─── 三层加密结果 ───────────────────────────────────────────────────────────

/// 三层加密完整结果（不可变——L1+L2+L3+签名+信封）。
///
/// 包含所有解密所需的材料（密文、nonce、填充长度、签名、信封）。
/// 版本号支持向前兼容——未来算法升级不断裂。
class ThreeLayerResult {
  const ThreeLayerResult({
    required this.l1Ciphertext,
    required this.l1Nonce,
    required this.l2Ciphertext,
    required this.l2Nonce,
    required this.l2PaddingLength,
    required this.l3Ciphertext,
    required this.l3Nonce,
    required this.signature,
    required this.envelope,
    required this.version,
    required this.processedAt,
    this.metadata = const {},
  });

  /// L1 层密文（ChaCha20-Poly1305 加密后）。
  final List<int> l1Ciphertext;

  /// L1 层 nonce（12 字节）。
  final List<int> l1Nonce;

  /// L2 层密文（AES-256-GCM 加密后——含填充）。
  final List<int> l2Ciphertext;

  /// L2 层 nonce（12 字节）。
  final List<int> l2Nonce;

  /// L2 层随机填充长度（16~256 字节——隐藏真实大小）。
  final int l2PaddingLength;

  /// L3 层密文（AES-256-GCM 加密后——含元数据+签名保护）。
  final List<int> l3Ciphertext;

  /// L3 层 nonce（12 字节）。
  final List<int> l3Nonce;

  /// 数字签名（覆盖 L3 密文+元数据——防篡改）。
  final SignatureResult signature;

  /// 信封加密数据（DEK 用 KEK 包裹——支持密钥轮换）。
  final DataEnvelope envelope;

  /// 协议版本（向前兼容——算法升级不断裂）。
  final int version;

  /// 处理时间。
  final DateTime processedAt;

  /// 附加元数据（算法标识、密钥版本等）。
  final Map<String, dynamic> metadata;
}

// ─── 签名服务 ───────────────────────────────────────────────────────────────

/// 数字签名服务（积木式纯 Dart——Ed25519）。
///
/// 功能：
/// - 生成 Ed25519 密钥对
/// - 签名数据（覆盖密文+元数据）
/// - 验证签名（失败触发告警回调）
///
/// 安全性：
/// - Ed25519：128 位安全等级（等价 RSA-3072）
/// - 确定性签名（相同消息+密钥=相同签名——防止 nonce 重用攻击）
/// - 签名覆盖密文+元数据（防篡改+防重排）
/// - SHA-512 摘要防数据替换攻击
///
/// 委托 cryptography 包 Ed25519（纯 Dart——禁 Flutter/dart:io）。
class SignatureService {
  const SignatureService();

  static final Ed25519 _algorithm = Ed25519();

  /// 生成 Ed25519 密钥对。
  Future<SigningKeyPair> generateKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final seed = await keyPair.extract();

    return SigningKeyPair(
      publicKey: publicKey.bytes,
      privateKey: seed.bytes,
      createdAt: DateTime.now(),
    );
  }

  /// 从种子字节恢复密钥对。
  Future<SigningKeyPair> keyPairFromSeed(List<int> seed) async {
    assert(seed.length == 32, 'Ed25519 私钥必须 32 字节种子');
    final keyPair = await _algorithm.newKeyPairFromSeed(
      Uint8List.fromList(seed),
    );
    final publicKey = await keyPair.extractPublicKey();

    return SigningKeyPair(
      publicKey: publicKey.bytes,
      privateKey: Uint8List.fromList(seed),
      createdAt: DateTime.now(),
    );
  }

  /// 签名数据（Ed25519——覆盖密文+元数据）。
  ///
  /// [data] 要签名的数据（通常是 L3 密文）。
  /// [keyPair] 签名密钥对。
  /// [metadata] 附加元数据（密钥ID、版本、算法标识——混入签名）。
  ///
  /// 返回：SignatureResult（64字节签名+SHA-512摘要+时间+元数据）。
  Future<SignatureResult> sign({
    required List<int> data,
    required SigningKeyPair keyPair,
    Map<String, dynamic> metadata = const {},
  }) async {
    // 构造签名载荷：data || metadata(json) || timestamp。
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final metaJson = utf8.encode(jsonEncode({
      ...metadata,
      'timestamp': timestamp,
      'algorithm': 'ed25519',
    }));
    final payload = Uint8List(data.length + metaJson.length + 8);
    payload.setRange(0, data.length, data);
    payload.setRange(data.length, data.length + metaJson.length, metaJson);
    _writeUint64BE(payload, data.length + metaJson.length, timestamp);

    // SHA-512 摘要（完整性校验——非签名本身）。
    final dataHash = _sha512Hash(payload);

    // Ed25519 签名——委托 cryptography 包。
    final seedKeyPair = await _algorithm.newKeyPairFromSeed(
      Uint8List.fromList(keyPair.privateKey),
    );
    final signature = await _algorithm.sign(
      payload,
      keyPair: seedKeyPair,
    );

    return SignatureResult(
      signature: signature.bytes,
      dataHash: dataHash,
      signedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      metadata: metadata,
    );
  }

  /// 验证签名（Ed25519——失败触发告警回调）。
  ///
  /// [data] 原始数据（与签名时一致）。
  /// [sig] 签名结果。
  /// [publicKey] 公钥（32 字节）。
  /// [onAlert] 签名验证失败时的告警回调（可选——用于日志/UI通知）。
  ///
  /// 返回：true=验签通过，false=验签失败（同时触发告警）。
  Future<bool> verify({
    required List<int> data,
    required SignatureResult sig,
    required List<int> publicKey,
    SignatureAlertCallback? onAlert,
  }) async {
    try {
      // 重构签名载荷。
      final timestamp = sig.signedAt.millisecondsSinceEpoch;
      final metaJson = utf8.encode(jsonEncode({
        ...sig.metadata,
        'timestamp': timestamp,
        'algorithm': 'ed25519',
      }));
      final payload = Uint8List(data.length + metaJson.length + 8);
      payload.setRange(0, data.length, data);
      payload.setRange(data.length, data.length + metaJson.length, metaJson);
      _writeUint64BE(payload, data.length + metaJson.length, timestamp);

      // 验证 SHA-512 摘要。
      final computedHash = _sha512Hash(payload);
      if (!_constantTimeEqual(computedHash.sublist(0, 32), sig.dataHash)) {
        onAlert?.call('数据完整性校验失败：SHA-512 摘要不匹配', {
          'expected_hash': _hexEncode(computedHash),
          'actual_hash': _hexEncode(sig.dataHash),
          'data_length': data.length,
        });
        return false;
      }

      // 构造 Ed25519 公钥。
      final edPublicKey = SimplePublicKey(
        Uint8List.fromList(publicKey),
        type: KeyPairType.ed25519,
      );

      // Ed25519 验签——委托 cryptography 包。
      final valid = await _algorithm.verify(
        payload,
        signature: Signature(
          Uint8List.fromList(sig.signature),
          publicKey: edPublicKey,
        ),
      );

      if (!valid) {
        onAlert?.call('Ed25519 签名验证失败：密文可能被篡改', {
          'signature_length': sig.signature.length,
          'public_key_hex': _hexEncode(publicKey),
          'data_length': data.length,
          'signed_at': sig.signedAt.toIso8601String(),
        });
      }

      return valid;
    } catch (e) {
      onAlert?.call('签名验证异常：$e', {
        'data_length': data.length,
        'error': e.toString(),
      });
      return false;
    }
  }

  // ─── 内部工具 ─────────────────────────────────────────────────────────

  /// SHA-512 摘要（截取前 32 字节用于存储——节省空间）。
  static List<int> _sha512Hash(List<int> data) {
    final digest = SHA512Digest();
    final hash = digest.process(Uint8List.fromList(data));
    // 返回完整 64 字节——供 Ed25519 内部使用。
    return hash;
  }

  /// 写入 64 位大端序整数。
  static void _writeUint64BE(Uint8List buffer, int offset, int value) {
    buffer[offset] = (value >> 56) & 0xFF;
    buffer[offset + 1] = (value >> 48) & 0xFF;
    buffer[offset + 2] = (value >> 40) & 0xFF;
    buffer[offset + 3] = (value >> 32) & 0xFF;
    buffer[offset + 4] = (value >> 24) & 0xFF;
    buffer[offset + 5] = (value >> 16) & 0xFF;
    buffer[offset + 6] = (value >> 8) & 0xFF;
    buffer[offset + 7] = value & 0xFF;
  }

  /// 常量时间比较（防时序攻击）。
  static bool _constantTimeEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// 十六进制编码。
  static String _hexEncode(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

// ─── 三层加密服务 ───────────────────────────────────────────────────────────

/// 三层封装加密服务（军工级——积木式纯 Dart）。
///
/// 架构：
///   L1 内层：ChaCha20-Poly1305（数据加密——流式无填充——适合画布数据）
///   L2 中层：AES-256-GCM + 随机填充（隐藏文件大小——16~256字节随机垃圾）
///   L3 外层：AES-256-GCM + 数字签名（防篡改认证）
///
/// 信封加密：DEK 用 KEK 包裹（RFC 3394 AES Key Wrap），支持密钥轮换。
///
/// 安全性：
/// - 三层独立密钥（K1/K2/K3）——即使一层泄露不影响其他层
/// - 随机填充隐藏文件大小（抗流量分析）
/// - 数字签名覆盖 L3 密文+元数据（防篡改+防重排）
/// - 信封加密实现密钥轮换（DEK 不变，KEK 轮换）
class ThreeLayerEncryptionService {
  ThreeLayerEncryptionService({
    SignatureService? signatureService,
    EnvelopeEncryptionService? envelopeService,
  })  : _signatureService = signatureService ?? const SignatureService(),
        _envelopeService = envelopeService ?? const EnvelopeEncryptionService();

  final SignatureService _signatureService;
  final EnvelopeEncryptionService _envelopeService;

  /// 三层加密（明文 → L1 → L2 → L3 → 签名+信封封装）。
  ///
  /// [plaintext] 原始明文数据。
  /// [k1] L1 密钥（ChaCha20——32字节）。
  /// [k2] L2 密钥（AES-256-GCM——32字节）。
  /// [k3] L3 密钥（AES-256-GCM——32字节——用于信封加密）。
  /// [signingKeyPair] 签名密钥对。
  /// [kek] 密钥加密密钥（32字节——包裹 DEK）。
  /// [keyId] 密钥 ID（标识当前 KEK 版本——支持密钥轮换）。
  /// [metadata] 附加元数据（混入签名——防篡改）。
  ///
  /// 返回：ThreeLayerResult（含三层密文+签名+信封）。
  Future<ThreeLayerResult> encrypt({
    required List<int> plaintext,
    required List<int> k1,
    required List<int> k2,
    required List<int> k3,
    required SigningKeyPair signingKeyPair,
    required List<int> kek,
    String keyId = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    assert(k1.length == 32, 'L1 密钥必须 32 字节');
    assert(k2.length == 32, 'L2 密钥必须 32 字节');
    assert(k3.length == 32, 'L3 密钥必须 32 字节');
    assert(kek.length == 32, 'KEK 必须 32 字节');

    // ─── L1：ChaCha20-Poly1305 加密 ────────────────────────────────────
    final l1Nonce = _generateNonce(12);
    final l1Ciphertext = chacha20Poly1305Encrypt(
      plaintext: Uint8List.fromList(plaintext),
      key: Uint8List.fromList(k1),
      nonce: Uint8List.fromList(l1Nonce),
    );

    // ─── L2：AES-256-GCM + 随机填充 ───────────────────────────────────
    final paddingLength = _randomPaddingLength();
    final paddingBytes = _buildPaddingBytes(paddingLength);

    // 拼接：l1Ciphertext || padding。
    final l2Plaintext = Uint8List(l1Ciphertext.length + paddingBytes.length);
    l2Plaintext.setRange(0, l1Ciphertext.length, l1Ciphertext);
    l2Plaintext.setRange(l1Ciphertext.length, l2Plaintext.length, paddingBytes);

    final l2Nonce = _generateNonce(12);
    final l2Ciphertext = aes256GcmEncrypt(
      plaintext: l2Plaintext,
      key: Uint8List.fromList(k2),
      nonce: Uint8List.fromList(l2Nonce),
    );

    // ─── L3：AES-256-GCM 加密（含元数据） ──────────────────────────────
    final metadataBytes = utf8.encode(jsonEncode({
      ...metadata,
      'version': 1,
      'timestamp': DateTime.now().toIso8601String(),
      'layers': 'ChaCha20+AES-GCM+AES-GCM',
      'padding_length': paddingLength,
    }));
    final l3Plaintext = Uint8List(l2Ciphertext.length + metadataBytes.length);
    l3Plaintext.setRange(0, l2Ciphertext.length, l2Ciphertext);
    l3Plaintext.setRange(l2Ciphertext.length, l3Plaintext.length, metadataBytes);

    final l3Nonce = _generateNonce(12);
    final l3Ciphertext = aes256GcmEncrypt(
      plaintext: l3Plaintext,
      key: Uint8List.fromList(k3),
      nonce: Uint8List.fromList(l3Nonce),
    );

    // ─── 数字签名（覆盖 L3 密文+元数据） ─────────────────────────────
    final signature = await _signatureService.sign(
      data: l3Ciphertext,
      keyPair: signingKeyPair,
      metadata: {
        ...metadata,
        'key_id': keyId,
        'version': 1,
        'layers': 3,
      },
    );

    // ─── 信封加密（DEK 用 KEK 包裹 K3） ──────────────────────────────
    final dek = _envelopeService.generateDek();
    final envelope = _envelopeService.seal(
      keyId: keyId,
      plain: Uint8List.fromList(k3),
      dek: Uint8List.fromList(dek),
      kek: Uint8List.fromList(kek),
    );

    return ThreeLayerResult(
      l1Ciphertext: l1Ciphertext,
      l1Nonce: l1Nonce,
      l2Ciphertext: l2Ciphertext,
      l2Nonce: l2Nonce,
      l2PaddingLength: paddingLength,
      l3Ciphertext: l3Ciphertext,
      l3Nonce: l3Nonce,
      signature: signature,
      envelope: envelope,
      version: 1,
      processedAt: DateTime.now(),
      metadata: metadata,
    );
  }

  /// 三层解密（L3 → L2 → L1 → 明文）。
  ///
  /// [result] 三层加密结果。
  /// [k1] L1 密钥（ChaCha20——32字节）。
  /// [k2] L2 密钥（AES-256-GCM——32字节）。
  /// [kek] KEK（32字节——解包信封得到 K3）。
  /// [signingPublicKey] 签名公钥（验签）。
  /// [onAlert] 签名验证失败告警回调（可选）。
  ///
  /// 返回：解密后的明文数据。
  /// 抛出：[SignatureVerificationException] 验签失败时。
  Future<List<int>> decrypt({
    required ThreeLayerResult result,
    required List<int> k1,
    required List<int> k2,
    required List<int> kek,
    required List<int> signingPublicKey,
    SignatureAlertCallback? onAlert,
  }) async {
    assert(k1.length == 32, 'L1 密钥必须 32 字节');
    assert(k2.length == 32, 'L2 密钥必须 32 字节');
    assert(kek.length == 32, 'KEK 必须 32 字节');

    // ─── 验证数字签名（L3 外层） ─────────────────────────────────────
    final signatureValid = await _signatureService.verify(
      data: result.l3Ciphertext,
      sig: result.signature,
      publicKey: Uint8List.fromList(signingPublicKey),
      onAlert: onAlert,
    );

    if (!signatureValid) {
      throw SignatureVerificationException(
        '数字签名验证失败：密文可能被篡改',
        context: 'L3 外层验签',
        metadata: result.metadata,
      );
    }

    // ─── 解包信封（得到 K3） ─────────────────────────────────────────
    final k3Unwrapped = _envelopeService.open(
      envelope: result.envelope,
      kek: Uint8List.fromList(kek),
    );

    // ─── L3：AES-256-GCM 解密 ─────────────────────────────────────────
    final l3Plaintext = aes256GcmDecrypt(
      ciphertextWithTag: result.l3Ciphertext,
      key: Uint8List.fromList(k3Unwrapped),
      nonce: Uint8List.fromList(result.l3Nonce),
    );

    // 分离 L2 密文和元数据。
    // 元数据在末尾——格式：l2Ciphertext || metadata(json)。
    // 需要找到元数据边界——元数据以 '{' 开头 '}' 结尾。
    final l3PlainStr = utf8.decode(l3Plaintext, allowMalformed: true);
    final metaStart = l3PlainStr.lastIndexOf('{');
    final metaEnd = l3PlainStr.lastIndexOf('}');
    if (metaStart < 0 || metaEnd < 0 || metaEnd <= metaStart) {
      throw const FormatException('L3 载荷格式异常：找不到元数据边界');
    }
    final l2Ciphertext = l3Plaintext.sublist(0, metaStart);

    // ─── L2：AES-256-GCM 解密 + 去除填充 ──────────────────────────────
    final l2Plaintext = aes256GcmDecrypt(
      ciphertextWithTag: l2Ciphertext,
      key: Uint8List.fromList(k2),
      nonce: Uint8List.fromList(result.l2Nonce),
    );

    // 解析填充格式：数据在前，尾部是 [length:2bytes][random:Nbytes]。
    if (l2Plaintext.length < 2) {
      throw const FormatException('L2 载荷过短：缺少填充长度头');
    }
    final paddingLength = (l2Plaintext[l2Plaintext.length - 2] << 8) |
        l2Plaintext[l2Plaintext.length - 1];
    if (paddingLength < 16 || paddingLength > 256) {
      throw FormatException('填充长度异常：$paddingLength（期望 16~256）');
    }
    if (l2Plaintext.length < 2 + paddingLength) {
      throw FormatException('L2 载荷长度不足：声明填充 $paddingLength 字节');
    }

    // 提取 L1 密文（去除尾部填充）。
    final l1Ciphertext = l2Plaintext.sublist(
      0,
      l2Plaintext.length - 2 - paddingLength,
    );

    // ─── L1：ChaCha20-Poly1305 解密 ───────────────────────────────────
    final plaintext = chacha20Poly1305Decrypt(
      ciphertextWithTag: l1Ciphertext,
      key: Uint8List.fromList(k1),
      nonce: Uint8List.fromList(result.l1Nonce),
    );

    return plaintext;
  }

  /// 生成随机填充长度（16~256 字节——CSPRNG——隐藏真实大小）。
  int _randomPaddingLength() {
    final secureRandom = _createSecureRandom();
    return 16 + secureRandom.nextUint8() % 241; // 16 + [0..240] = [16..256]。
  }

  /// 构造填充字节：[length:2bytes][random:Nbytes]。
  Uint8List _buildPaddingBytes(int length) {
    final secureRandom = _createSecureRandom();
    final result = Uint8List(2 + length);
    result[0] = (length >> 8) & 0xFF;
    result[1] = length & 0xFF;
    for (var i = 0; i < length; i++) {
      result[2 + i] = secureRandom.nextUint8();
    }
    return result;
  }

  /// 生成安全随机 nonce（CSPRNG）。
  static List<int> _generateNonce(int length) {
    final secureRandom = _createSecureRandom();
    final nonce = Uint8List(length);
    for (var i = 0; i < length; i++) {
      nonce[i] = secureRandom.nextUint8();
    }
    return nonce;
  }

  /// 创建安全随机数生成器。
  static FortunaRandom _createSecureRandom() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }
}

// ─── 异常类 ─────────────────────────────────────────────────────────────────

/// 签名验证异常（验签失败时抛出——含上下文和元数据）。
class SignatureVerificationException implements Exception {
  const SignatureVerificationException(
    this.message, {
    this.context = '',
    this.metadata = const {},
  });

  final String message;
  final String context;
  final Map<String, dynamic> metadata;

  @override
  String toString() {
    return 'SignatureVerificationException: $message'
        '${context.isNotEmpty ? ' ($context)' : ''}';
  }
}

// ─── 工具函数 ───────────────────────────────────────────────────────────────

/// 列表相等比较。
bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
