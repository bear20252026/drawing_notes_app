// editor_core——加密工具集（pointycastle 实现——2026-08-24）。
//
// 提供 HKDF-SHA256、AES-256-GCM、AES-256 Key Wrap (RFC 3394) 的纯 Dart 实现。
// 用于替换 EnvelopeEncryptionService 和 PQHybridService 中的占位符。
library;

import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// HKDF-SHA256 密钥派生（RFC 5869）。
///
/// [ikm] 输入密钥材料（Input Keying Material）。
/// [salt] 盐值（可选——为空时使用全零）。
/// [info] 上下文信息。
/// [outputLength] 输出长度（字节）。
Uint8List hkdfSha256({
  required List<int> ikm,
  List<int> salt = const [],
  required List<int> info,
  required int outputLength,
}) {
  final hmac = HMac(SHA256Digest(), 64);

  // ── Extract ──
  final saltBytes = salt.isEmpty ? Uint8List(hmac.macSize) : Uint8List.fromList(salt);
  hmac.init(KeyParameter(saltBytes));
  final prk = hmac.process(Uint8List.fromList(ikm));

  // ── Expand ──
  hmac.init(KeyParameter(prk));
  final okm = Uint8List(outputLength);
  var offset = 0;
  var counter = 1;
  var t = Uint8List(0);

  while (offset < outputLength) {
    final input = Uint8List(t.length + info.length + 1);
    input.setRange(0, t.length, t);
    input.setRange(t.length, t.length + info.length, info);
    input[t.length + info.length] = counter;
    t = hmac.process(input);
    final copyLen = (outputLength - offset).clamp(0, t.length);
    okm.setRange(offset, offset + copyLen, t);
    offset += copyLen;
    counter++;
  }

  return okm;
}

/// AES-256-GCM 加密（NIST SP 800-38D）。
///
/// [plaintext] 明文。
/// [key] 256 位密钥（32 字节）。
/// [nonce] 96 位 nonce（12 字节——每次加密必须唯一）。
/// [aad] 附加认证数据（可选）。
///
/// 返回密文 + 128 位认证标签（tag 在密文末尾）。
Uint8List aes256GcmEncrypt({
  required List<int> plaintext,
  required List<int> key,
  required List<int> nonce,
  List<int> aad = const [],
}) {
  assert(key.length == 32, 'AES-256 密钥必须 32 字节');
  assert(nonce.length == 12, 'GCM nonce 必须 12 字节');

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true, // encrypt
      AEADParameters(
        KeyParameter(Uint8List.fromList(key)),
        128, // tag length in bits
        Uint8List.fromList(nonce),
        Uint8List.fromList(aad),
      ),
    );

  return cipher.process(Uint8List.fromList(plaintext));
}

/// AES-256-GCM 解密 + 认证验证。
///
/// [ciphertextWithTag] 密文 + 认证标签（tag 在密文末尾）。
/// [key] 256 位密钥（32 字节）。
/// [nonce] 96 位 nonce（12 字节）。
/// [aad] 附加认证数据（可选）。
///
/// 认证失败时抛出 [InvalidCipherTextException]。
Uint8List aes256GcmDecrypt({
  required List<int> ciphertextWithTag,
  required List<int> key,
  required List<int> nonce,
  List<int> aad = const [],
}) {
  assert(key.length == 32, 'AES-256 密钥必须 32 字节');
  assert(nonce.length == 12, 'GCM nonce 必须 12 字节');

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false, // decrypt
      AEADParameters(
        KeyParameter(Uint8List.fromList(key)),
        128,
        Uint8List.fromList(nonce),
        Uint8List.fromList(aad),
      ),
    );

  return cipher.process(Uint8List.fromList(ciphertextWithTag));
}

/// AES-256 Key Wrap (RFC 3394)。
///
/// [plaintext] 待包装数据（必须是 64 位的倍数——通常 32 字节 DEK）。
/// [key] 256 位 KEK（Key Encryption Key）。
///
/// 返回包装后的数据（长度 = plaintext.length + 8）。
Uint8List aes256KeyWrap({
  required List<int> plaintext,
  required List<int> key,
}) {
  assert(key.length == 32, 'AES-256 KEK 必须 32 字节');
  assert(plaintext.length >= 8 && plaintext.length % 8 == 0,
      '明文必须是 8 字节的倍数');

  // RFC 3394 标准实现——6 轮 XOR + AES-ECB。
  final aes = AESEngine()..init(true, KeyParameter(Uint8List.fromList(key)));
  final n = plaintext.length ~/ 8;

  // 初始化：A = IV (0xA6*8)，R = plaintext blocks
  var a = Uint8List.fromList([0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6]);
  final r = List.generate(n, (i) {
    return Uint8List.fromList(plaintext.sublist(i * 8, i * 8 + 8));
  });

  final block = Uint8List(16);

  for (var j = 0; j < 6; j++) {
    for (var i = 0; i < n; i++) {
      // B = AES(A || R[i])
      block.setRange(0, 8, a);
      block.setRange(8, 16, r[i]);
      final b = aes.process(block);
      // A = MSB(B) XOR t (t = n*j + i + 1)
      a = Uint8List(8);
      for (var k = 0; k < 8; k++) {
        a[k] = b[k];
      }
      var t = n * j + i + 1;
      // XOR t into A (big-endian)
      for (var k = 7; k >= 0 && t > 0; k--) {
        a[k] ^= t & 0xFF;
        t >>= 8;
      }
      // R[i] = LSB(B)
      r[i] = Uint8List.fromList(b.sublist(8, 16));
    }
  }

  // 输出：A || R[0] || R[1] || ... || R[n-1]
  final output = Uint8List(8 + plaintext.length);
  output.setRange(0, 8, a);
  for (var i = 0; i < n; i++) {
    output.setRange(8 + i * 8, 8 + i * 8 + 8, r[i]);
  }
  return output;
}

/// AES-256 Key Unwrap (RFC 3394)。
///
/// [ciphertext] 包装后的数据。
/// [key] 256 位 KEK。
///
/// 返回解包装的数据。认证失败时抛出 [StateError]。
Uint8List aes256KeyUnwrap({
  required List<int> ciphertext,
  required List<int> key,
}) {
  assert(key.length == 32, 'AES-256 KEK 必须 32 字节');
  assert(ciphertext.length >= 16 && ciphertext.length % 8 == 0,
      '密文必须是 8 字节的倍数且 ≥ 16 字节');

  final aes = AESEngine()..init(false, KeyParameter(Uint8List.fromList(key)));
  final n = (ciphertext.length ~/ 8) - 1;

  // 初始化：A = 密文前 8 字节，R = 剩余 blocks
  var a = Uint8List.fromList(ciphertext.sublist(0, 8));
  final r = List.generate(n, (i) {
    return Uint8List.fromList(ciphertext.sublist(8 + i * 8, 8 + i * 8 + 8));
  });

  final block = Uint8List(16);

  for (var j = 5; j >= 0; j--) {
    for (var i = n - 1; i >= 0; i--) {
      // B = AES-1((A XOR t) || R[i])  —— RFC 3394 要求先 XOR 再 AES_inv
      var t = n * j + i + 1;
      for (var k = 7; k >= 0 && t > 0; k--) {
        a[k] ^= t & 0xFF;
        t >>= 8;
      }
      block.setRange(0, 8, a);
      block.setRange(8, 16, r[i]);
      final b = aes.process(block);
      // A = MSB(B)
      a = Uint8List.fromList(b.sublist(0, 8));
      // R[i] = LSB(B)
      r[i] = Uint8List.fromList(b.sublist(8, 16));
    }
  }

  // 验证 A == 0xA6*8
  const expectedA = [0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6];
  for (var k = 0; k < 8; k++) {
    if (a[k] != expectedA[k]) {
      throw StateError('AES Key Unwrap 认证失败：A 值不匹配');
    }
  }

  // 输出：R[0] || R[1] || ... || R[n-1]
  final output = Uint8List(n * 8);
  for (var i = 0; i < n; i++) {
    output.setRange(i * 8, i * 8 + 8, r[i]);
  }
  return output;
}
