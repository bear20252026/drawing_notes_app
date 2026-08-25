// editor_core——加密工具集（pointycastle 实现——2026-08-24）。
//
// 提供 HKDF-SHA256、AES-256-GCM、AES-256 Key Wrap (RFC 3394)、
// ChaCha20-Poly1305 (RFC 8439)、XChaCha20-Poly1305 的纯 Dart 实现。
// 用于替换 EnvelopeEncryptionService 和 PQHybridService 中的占位符。
library;

import 'dart:convert';
import 'dart:math' as math;
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

// ═══════════════════════════════════════════════════════════════════════════════
// ChaCha20-Poly1305 (RFC 8439) & XChaCha20-Poly1305 AEAD
// ═══════════════════════════════════════════════════════════════════════════════

/// ChaCha20-Poly1305 加密（RFC 8439 §2.8）。
///
/// [plaintext] 明文。
/// [key] 256 位密钥（32 字节）。
/// [nonce] 96 位 nonce（12 字节——每次加密必须唯一）。
/// [aad] 附加认证数据（可选）。
///
/// 返回密文 + 128 位 Poly1305 认证标签（tag 在密文末尾，共 plaintext.length + 16）。
Uint8List chacha20Poly1305Encrypt({
  required List<int> plaintext,
  required List<int> key,
  required List<int> nonce,
  List<int> aad = const [],
}) {
  assert(key.length == 32, 'ChaCha20 密钥必须 32 字节');
  assert(nonce.length == 12, 'ChaCha20-Poly1305 nonce 必须 12 字节');

  final k = Uint8List.fromList(key);
  final n = Uint8List.fromList(nonce);
  final pt = Uint8List.fromList(plaintext);
  final ad = Uint8List.fromList(aad);

  return _aeadEncrypt(
    key: k,
    nonce: n,
    plaintext: pt,
    aad: ad,
    deriveSubkey: false,
  );
}

/// ChaCha20-Poly1305 解密 + 认证验证（RFC 8439 §2.8）。
///
/// [ciphertextWithTag] 密文 + Poly1305 认证标签（tag 在密文末尾）。
/// [key] 256 位密钥（32 字节）。
/// [nonce] 96 位 nonce（12 字节）。
/// [aad] 附加认证数据（可选）。
///
/// 认证失败时抛出 [InvalidCipherTextException]。
Uint8List chacha20Poly1305Decrypt({
  required List<int> ciphertextWithTag,
  required List<int> key,
  required List<int> nonce,
  List<int> aad = const [],
}) {
  assert(key.length == 32, 'ChaCha20 密钥必须 32 字节');
  assert(nonce.length == 12, 'ChaCha20-Poly1305 nonce 必须 12 字节');

  final k = Uint8List.fromList(key);
  final n = Uint8List.fromList(nonce);
  final ct = Uint8List.fromList(ciphertextWithTag);
  final ad = Uint8List.fromList(aad);

  return _aeadDecrypt(
    key: k,
    nonce: n,
    ciphertextWithTag: ct,
    aad: ad,
    deriveSubkey: false,
  );
}

/// XChaCha20-Poly1305 加密（扩展 nonce——192 位/24 字节）。
///
/// XChaCha20 使用 HChaCha20 从 24 字节 nonce 派生 32 字节子密钥，
/// 再用 ChaCha20-Poly1305 加密——适合 nonce 管理困难的场景
/// （如随机 nonce 而非计数器）。
///
/// [plaintext] 明文。
/// [key] 256 位密钥（32 字节）。
/// [nonce] 192 位 nonce（24 字节——可安全使用随机值）。
/// [aad] 附加认证数据（可选）。
///
/// 返回密文 + 128 位 Poly1305 认证标签（tag 在密文末尾，共 plaintext.length + 16）。
Uint8List xchacha20Poly1305Encrypt({
  required List<int> plaintext,
  required List<int> key,
  required List<int> nonce,
  List<int> aad = const [],
}) {
  assert(key.length == 32, 'XChaCha20 密钥必须 32 字节');
  assert(nonce.length == 24, 'XChaCha20-Poly1305 nonce 必须 24 字节');

  // HChaCha20: key + nonce[0:16] → 32-byte subkey
  final subkey = _hchacha20(
    Uint8List.fromList(key),
    Uint8List.fromList(nonce.sublist(0, 16)),
  );

  // ChaCha20 nonce: 4 zero bytes + nonce[16:24] = 12 bytes
  final chachaNonce = Uint8List(12);
  chachaNonce.setRange(4, 12, nonce.sublist(16, 24));

  return _aeadEncrypt(
    key: subkey,
    nonce: chachaNonce,
    plaintext: Uint8List.fromList(plaintext),
    aad: Uint8List.fromList(aad),
    deriveSubkey: false,
  );
}

/// XChaCha20-Poly1305 解密 + 认证验证。
///
/// [ciphertextWithTag] 密文 + Poly1305 认证标签（tag 在密文末尾）。
/// [key] 256 位密钥（32 字节）。
/// [nonce] 192 位 nonce（24 字节）。
/// [aad] 附加认证数据（可选）。
///
/// 认证失败时抛出 [InvalidCipherTextException]。
Uint8List xchacha20Poly1305Decrypt({
  required List<int> ciphertextWithTag,
  required List<int> key,
  required List<int> nonce,
  List<int> aad = const [],
}) {
  assert(key.length == 32, 'XChaCha20 密钥必须 32 字节');
  assert(nonce.length == 24, 'XChaCha20-Poly1305 nonce 必须 24 字节');

  final subkey = _hchacha20(
    Uint8List.fromList(key),
    Uint8List.fromList(nonce.sublist(0, 16)),
  );

  final chachaNonce = Uint8List(12);
  chachaNonce.setRange(4, 12, nonce.sublist(16, 24));

  return _aeadDecrypt(
    key: subkey,
    nonce: chachaNonce,
    ciphertextWithTag: Uint8List.fromList(ciphertextWithTag),
    aad: Uint8List.fromList(aad),
    deriveSubkey: false,
  );
}

// ─── RFC 8439 AEAD 内部实现 ──────────────────────────────────────────────────

/// RFC 8439 AEAD 加密核心（ChaCha20-Poly1305）。
///
/// 步骤：
/// 1. 从 ChaCha20 keystream (counter=0) 派生 Poly1305 密钥
/// 2. 用 ChaCha20 (counter=1) 加密明文
/// 3. 计算 Poly1305 MAC 覆盖：AAD || pad || ciphertext || pad || len(AAD) || len(ciphertext)
/// 4. 返回 ciphertext || tag
Uint8List _aeadEncrypt({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List plaintext,
  required Uint8List aad,
  required bool deriveSubkey,
}) {
  // Step 1: Poly1305 key = ChaCha20(key, nonce, counter=0)[0..31]
  final chacha = ChaCha7539Engine();
  chacha.init(
    true,
    ParametersWithIV(KeyParameter(key), nonce),
  );

  // Generate Poly1305 key (32 bytes from counter=0)
  final poly1305Key = Uint8List(32);
  final zeros32 = Uint8List(32);
  chacha.processBytes(zeros32, 0, 32, poly1305Key, 0);

  // Step 2: Encrypt plaintext with ChaCha20 (counter=1, already advanced)
  final ciphertext = Uint8List(plaintext.length);
  if (plaintext.isNotEmpty) {
    chacha.processBytes(plaintext, 0, plaintext.length, ciphertext, 0);
  }

  // Step 3: Compute Poly1305 MAC
  final tag = _computePoly1305Tag(
    poly1305Key: poly1305Key,
    aad: aad,
    ciphertext: ciphertext,
  );

  // Step 4: Return ciphertext || tag
  final result = Uint8List(ciphertext.length + 16);
  result.setRange(0, ciphertext.length, ciphertext);
  result.setRange(ciphertext.length, result.length, tag);
  return result;
}

/// RFC 8439 AEAD 解密核心（ChaCha20-Poly1305）。
///
/// 步骤：
/// 1. 分离密文和 tag
/// 2. 从 ChaCha20 keystream (counter=0) 派生 Poly1305 密钥
/// 3. 验证 Poly1305 tag
/// 4. 用 ChaCha20 (counter=1) 解密密文
Uint8List _aeadDecrypt({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List ciphertextWithTag,
  required Uint8List aad,
  required bool deriveSubkey,
}) {
  // Step 1: Split ciphertext and tag
  if (ciphertextWithTag.length < 16) {
    throw InvalidCipherTextException('密文太短——至少需要 16 字节 tag');
  }
  final ctLen = ciphertextWithTag.length - 16;
  final ciphertext = Uint8List(ctLen);
  final receivedTag = Uint8List(16);
  ciphertext.setRange(0, ctLen, ciphertextWithTag);
  receivedTag.setRange(0, 16, ciphertextWithTag.sublist(ctLen));

  // Step 2: Derive Poly1305 key
  final chacha = ChaCha7539Engine();
  chacha.init(
    true,
    ParametersWithIV(KeyParameter(key), nonce),
  );
  final poly1305Key = Uint8List(32);
  final zeros32 = Uint8List(32);
  chacha.processBytes(zeros32, 0, 32, poly1305Key, 0);

  // Step 3: Verify tag (constant-time comparison)
  final expectedTag = _computePoly1305Tag(
    poly1305Key: poly1305Key,
    aad: aad,
    ciphertext: ciphertext,
  );
  if (!_constantTimeEqual(receivedTag, expectedTag)) {
    throw InvalidCipherTextException('Poly1305 认证失败——密文或 AAD 被篡改');
  }

  // Step 4: Decrypt
  final plaintext = Uint8List(ctLen);
  if (ctLen > 0) {
    // Re-init ChaCha20 (counter=0, same key+nonce)
    final chacha2 = ChaCha7539Engine();
    chacha2.init(
      true,
      ParametersWithIV(KeyParameter(key), nonce),
    );
    // Skip 32 bytes (Poly1305 key generation, counter=0→1)
    final skip = Uint8List(32);
    final skipOut = Uint8List(32);
    chacha2.processBytes(skip, 0, 32, skipOut, 0);
    // Now at counter=1, decrypt
    chacha2.processBytes(ciphertext, 0, ctLen, plaintext, 0);
  }
  return plaintext;
}

/// 计算 Poly1305 标签（RFC 8439 §2.8）。
///
/// MAC 覆盖：AAD || pad16 || ciphertext || pad16 || len(AAD) || len(ciphertext)
Uint8List _computePoly1305Tag({
  required Uint8List poly1305Key,
  required Uint8List aad,
  required Uint8List ciphertext,
}) {
  final poly = Poly1305();
  poly.init(KeyParameter(poly1305Key));

  // AAD
  if (aad.isNotEmpty) {
    poly.update(aad, 0, aad.length);
    // Pad to 16-byte boundary
    final aadPad = (16 - (aad.length % 16)) % 16;
    if (aadPad > 0) {
      poly.update(Uint8List(aadPad), 0, aadPad);
    }
  }

  // Ciphertext
  if (ciphertext.isNotEmpty) {
    poly.update(ciphertext, 0, ciphertext.length);
    // Pad to 16-byte boundary
    final ctPad = (16 - (ciphertext.length % 16)) % 16;
    if (ctPad > 0) {
      poly.update(Uint8List(ctPad), 0, ctPad);
    }
  }

  // Lengths (little-endian 64-bit)
  final lenBlock = Uint8List(16);
  final lenData = ByteData.view(lenBlock.buffer);
  lenData.setUint64(0, aad.length, Endian.little);
  lenData.setUint64(8, ciphertext.length, Endian.little);
  poly.update(lenBlock, 0, 16);

  // Finalize and get tag
  final tag = Uint8List(16);
  poly.doFinal(tag, 0);
  return tag;
}

/// 常量时间比较（防时序攻击）。
bool _constantTimeEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// HChaCha20 密钥派生（XChaCha20 基础——draft-irtf-cfrg-xchacha）。
///
/// 从 32 字节密钥 + 16 字节 nonce 派生 32 字节子密钥。
/// 使用 ChaCha20 quarter-round 操作但不进行 XOR 输出。
Uint8List _hchacha20(Uint8List key, Uint8List nonce) {
  assert(key.length == 32);
  assert(nonce.length == 16);

  // 初始化 ChaCha20 状态矩阵
  // "expand 32-byte k" = 0x61707865, 0x3320646e, 0x79622d32, 0x6b206574
  final state = Uint32List(16);
  state[0] = 0x61707865;
  state[1] = 0x3320646e;
  state[2] = 0x79622d32;
  state[3] = 0x6b206574;

  // key → state[4..11]
  final keyData = ByteData.view(key.buffer, key.offsetInBytes, 32);
  for (var i = 0; i < 8; i++) {
    state[4 + i] = keyData.getUint32(i * 4, Endian.little);
  }

  // nonce → state[12..15]
  final nonceData = ByteData.view(nonce.buffer, nonce.offsetInBytes, 16);
  for (var i = 0; i < 4; i++) {
    state[12 + i] = nonceData.getUint32(i * 4, Endian.little);
  }

  // 20 rounds (10 double-rounds)
  for (var i = 0; i < 10; i++) {
    // Column rounds
    _quarterRound(state, 0, 4, 8, 12);
    _quarterRound(state, 1, 5, 9, 13);
    _quarterRound(state, 2, 6, 10, 14);
    _quarterRound(state, 3, 7, 11, 15);
    // Diagonal rounds
    _quarterRound(state, 0, 5, 10, 15);
    _quarterRound(state, 1, 6, 11, 12);
    _quarterRound(state, 2, 7, 8, 13);
    _quarterRound(state, 3, 4, 9, 14);
  }

  // 输出: state[0..3] || state[12..15]（共 32 字节）
  final out = Uint8List(32);
  final outData = ByteData.view(out.buffer);
  for (var i = 0; i < 4; i++) {
    outData.setUint32(i * 4, state[i], Endian.little);
  }
  for (var i = 0; i < 4; i++) {
    outData.setUint32(16 + i * 4, state[12 + i], Endian.little);
  }
  return out;
}

/// ChaCha20 quarter-round 操作。
void _quarterRound(Uint32List v, int a, int b, int c, int d) {
  v[a] = _add32(v[a], v[b]); v[d] = _rotl32(_xor32(v[d], v[a]), 16);
  v[c] = _add32(v[c], v[d]); v[b] = _rotl32(_xor32(v[b], v[c]), 12);
  v[a] = _add32(v[a], v[b]); v[d] = _rotl32(_xor32(v[d], v[a]), 8);
  v[c] = _add32(v[c], v[d]); v[b] = _rotl32(_xor32(v[b], v[c]), 7);
}

int _add32(int a, int b) => (a + b) & 0xFFFFFFFF;
int _xor32(int a, int b) => a ^ b;
int _rotl32(int v, int n) => ((v << n) | (v >>> (32 - n))) & 0xFFFFFFFF;

/// 平台自适应 AEAD 算法选择。
///
/// 根据目标平台选择最优 AEAD 算法：
/// - 移动端（Android/iOS）：XChaCha20-Poly1305（ARM NEON 优化，软件实现更快）
/// - 桌面端（Windows/macOS/Linux）：AES-256-GCM（硬件 AES-NI 加速）
/// - Web：AES-256-GCM（WebCrypto API 支持）
///
/// 返回算法标识符：'xchacha20-poly1305' 或 'aes-256-gcm'。
///
/// 注意：此为纯 Dart 层的选择逻辑——实际平台检测由 infrastructure 层
/// 通过 `Platform.isAndroid` 等实现。此处提供默认策略供上层参考。
enum AeadAlgorithm {
  /// XChaCha20-Poly1305（RFC draft-irtf-cfrg-xchacha）。
  /// 适合移动端——软件实现效率高，24 字节 nonce 可安全使用随机值。
  xchacha20Poly1305,

  /// AES-256-GCM（NIST SP 800-38D）。
  /// 适合桌面端——硬件 AES-NI 加速显著。
  aes256Gcm,
}

/// AEAD 加密结果（含算法标识）。
class AeadResult {
  const AeadResult({
    required this.ciphertext,
    required this.algorithm,
    required this.nonce,
  });

  /// 密文 + 认证标签。
  final Uint8List ciphertext;

  /// 使用的算法标识。
  final AeadAlgorithm algorithm;

  /// 使用的 nonce。
  final Uint8List nonce;
}

/// 平台自适应 AEAD 加密（选择最优算法）。
///
/// [platform] 平台标识：'android', 'ios', 'windows', 'macos', 'linux', 'web'。
/// [plaintext] 明文。
/// [key] 256 位密钥（32 字节）。
/// [aad] 附加认证数据（可选）。
///
/// 移动端使用 XChaCha20-Poly1305（24 字节随机 nonce），
/// 桌面端使用 AES-256-GCM（12 字节随机 nonce）。
AeadResult platformAeadEncrypt({
  required String platform,
  required List<int> plaintext,
  required List<int> key,
  List<int> aad = const [],
}) {
  final algorithm = selectAeadAlgorithm(platform);
  final rng = math.Random.secure();

  switch (algorithm) {
    case AeadAlgorithm.xchacha20Poly1305:
      // XChaCha20: 24 字节随机 nonce（安全使用随机值）。
      final nonce = Uint8List.fromList(
        List<int>.generate(24, (_) => rng.nextInt(256)),
      );
      final ciphertext = xchacha20Poly1305Encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );
      return AeadResult(
        ciphertext: ciphertext,
        algorithm: algorithm,
        nonce: nonce,
      );

    case AeadAlgorithm.aes256Gcm:
      // AES-GCM: 12 字节随机 nonce。
      final nonce = Uint8List.fromList(
        List<int>.generate(12, (_) => rng.nextInt(256)),
      );
      final ciphertext = aes256GcmEncrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );
      return AeadResult(
        ciphertext: ciphertext,
        algorithm: algorithm,
        nonce: nonce,
      );
  }
}

/// 平台自适应 AEAD 解密。
///
/// [algorithm] 加密时使用的算法标识。
/// [ciphertextWithTag] 密文 + 认证标签。
/// [key] 256 位密钥（32 字节）。
/// [nonce] 加密时使用的 nonce。
/// [aad] 附加认证数据（可选）。
///
/// 认证失败时抛出 [InvalidCipherTextException]。
Uint8List platformAeadDecrypt({
  required AeadAlgorithm algorithm,
  required List<int> ciphertextWithTag,
  required List<int> key,
  required List<int> nonce,
  List<int> aad = const [],
}) {
  switch (algorithm) {
    case AeadAlgorithm.xchacha20Poly1305:
      return xchacha20Poly1305Decrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: key,
        nonce: nonce,
        aad: aad,
      );
    case AeadAlgorithm.aes256Gcm:
      return aes256GcmDecrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: key,
        nonce: nonce,
        aad: aad,
      );
  }
}

/// 选择平台最优 AEAD 算法。
///
/// - 'android', 'ios' → XChaCha20-Poly1305（软件实现，ARM 友好）
/// - 'windows', 'macos', 'linux' → AES-256-GCM（硬件 AES-NI）
/// - 'web' → AES-256-GCM（WebCrypto API）
/// - 未知平台 → XChaCha20-Poly1305（更安全的默认值）
AeadAlgorithm selectAeadAlgorithm(String platform) {
  switch (platform.toLowerCase()) {
    case 'android':
    case 'ios':
      return AeadAlgorithm.xchacha20Poly1305;
    case 'windows':
    case 'macos':
    case 'linux':
    case 'web':
      return AeadAlgorithm.aes256Gcm;
    default:
      // 未知平台——保守选择 XChaCha20（更安全的默认值）
      return AeadAlgorithm.xchacha20Poly1305;
  }
}

// ─── 通用密码工具函数 ─────────────────────────────────────────────────────────

/// 计算数据的 SHA-256 哈希值（十六进制字符串）。
String sha256Hex(List<int> data) {
  final digest = Digest('SHA-256');
  final hash = digest.process(Uint8List.fromList(data));
  return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 从密码派生 256 位密钥（PBKDF2-SHA256）。
///
/// [rounds] 为 PBKDF2 迭代轮数（默认 3 轮，轻量场景）。
/// 返回 32 字节密钥。
Uint8List deriveKeyFromPassword({
  required String password,
  int rounds = 3,
}) {
  final passwordBytes = Uint8List.fromList(utf8.encode(password));
  // 使用固定 salt（生产环境应使用随机 salt 并与密文一起存储）
  final salt = Uint8List.fromList(utf8.encode('drawing-notes-backup-v1'));
  final pbkdf2 = PBKDF2KeyDerivator(HMac(Digest('SHA-256'), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, rounds, 32));
  return pbkdf2.process(passwordBytes);
}

/// 生成安全随机字节。
///
/// [length] 要生成的字节数。
Uint8List secureRandomBytes(int length) {
  final rng = math.Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rng.nextInt(256)),
  );
}
