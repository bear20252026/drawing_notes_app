// editor_core——EnvelopeEncryption 信封加密（后量子迁移指南借鉴——2026-08-22）。
//
// 信封加密（Envelope Encryption）本地化——每对象数据密钥（DEK）
// + 主密钥包裹（KEK）——防批量泄露。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// 参考：AWS KMS / Google Cloud KMS 信封加密模式 + pqforge HKDF 信封。
library;

import 'dart:math' as math;

/// 数据信封（Envelope Encryption 本地化——不可变）。
///
/// 信封结构：
/// - [keyId]：包裹密钥（KEK）标识
/// - [wrappedDek]：KEK 包裹的数据密钥（DEK）
/// - [ciphertext]：DEK 加密的内容
/// - [nonce]：加密 nonce（AES-GCM）
/// - [version]：信封格式版本
class DataEnvelope {
  const DataEnvelope({
    required this.keyId,
    required this.wrappedDek,
    required this.ciphertext,
    required this.nonce,
    this.version = 1,
    this.algorithm = 'aes-256-gcm',
  });

  final String keyId;
  final List<int> wrappedDek;
  final List<int> ciphertext;
  final List<int> nonce;
  final int version;
  final String algorithm;

  DataEnvelope copyWith({
    List<int>? wrappedDek,
    List<int>? ciphertext,
    int? version,
  }) {
    return DataEnvelope(
      keyId: keyId,
      wrappedDek: wrappedDek ?? this.wrappedDek,
      ciphertext: ciphertext ?? this.ciphertext,
      nonce: nonce,
      version: version ?? this.version,
      algorithm: algorithm,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DataEnvelope && keyId == other.keyId;

  @override
  int get hashCode => keyId.hashCode;
}

/// 密钥版本（信封加密密钥轮换支持——不可变）。
class KeyVersion {
  const KeyVersion({
    required this.id,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final DateTime createdAt;
  final bool status; // true=active, false=retired。

  KeyVersion copyWith({bool? status}) {
    return KeyVersion(id: id, createdAt: createdAt, status: status ?? this.status);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is KeyVersion && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 信封加密服务（Envelope Encryption 本地化——积木式纯 Dart）。
///
/// 流程：
/// 1. 生成每对象随机 DEK（数据密钥）
/// 2. 用 DEK 加密内容（AES-256-GCM——infrastructure 层执行）
/// 3. 用 KEK（主密钥）包裹 DEK（KeyWrap）
/// 4. 存储：keyId + wrappedDek + ciphertext（信封）
/// 5. 解密：KEK 解包 DEK → DEK 解密内容
///
/// 安全价值：一个 DEK 泄露只影响一个对象（防批量泄露——
/// 攻击者即使拿到一个 DEK 也无法解密其他对象）。
class EnvelopeEncryptionService {
  const EnvelopeEncryptionService();

  /// 生成每对象随机 DEK（32 字节——AES-256）。
  List<int> generateDek() {
    final rng = math.Random.secure();
    return List<int>.generate(32, (_) => rng.nextInt(256));
  }

  /// 生成随机 nonce（12 字节——AES-GCM）。
  List<int> generateNonce() {
    final rng = math.Random.secure();
    return List<int>.generate(12, (_) => rng.nextInt(256));
  }

  /// 包裹 DEK（用 KEK——简化模型：XOR + 校验——实际由 infrastructure 层
  /// 用 AES 密钥封装实现）。
  List<int> wrapDek(List<int> dek, List<int> kek) {
    if (kek.length < dek.length) {
      throw ArgumentError('KEK 长度不足（需 ≥ DEK 长度）');
    }
    final wrapped = List<int>.generate(dek.length, (i) => dek[i] ^ kek[i]);
    return wrapped;
  }

  /// 解包 DEK（用 KEK）。
  List<int> unwrapDek(List<int> wrappedDek, List<int> kek) {
    if (kek.length < wrappedDek.length) {
      throw ArgumentError('KEK 长度不足（需 ≥ wrappedDEK 长度）');
    }
    final dek = List<int>.generate(wrappedDek.length, (i) => wrappedDek[i] ^ kek[i]);
    return dek;
  }

  /// 创建信封（简化模型——封装流程——实际加密由 infrastructure 层）。
  DataEnvelope seal({
    required String keyId,
    required List<int> plain,
    required List<int> dek,
    required List<int> kek,
  }) {
    final nonce = generateNonce();
    // 实际内容加密（AES-256-GCM）由 infrastructure 层执行——
    // 此处模型层简化：plain XOR dek（占位——真实实现用 AES-GCM）。
    final ciphertext = List<int>.generate(plain.length, (i) => plain[i] ^ dek[i % dek.length]);
    final wrappedDek = wrapDek(dek, kek);
    return DataEnvelope(
      keyId: keyId,
      wrappedDek: wrappedDek,
      ciphertext: ciphertext,
      nonce: nonce,
    );
  }

  /// 打开信封（解密内容——模型层简化）。
  List<int> open({
    required DataEnvelope envelope,
    required List<int> kek,
  }) {
    final dek = unwrapDek(envelope.wrappedDek, kek);
    return List<int>.generate(
      envelope.ciphertext.length,
      (i) => envelope.ciphertext[i] ^ dek[i % dek.length],
    );
  }
}
