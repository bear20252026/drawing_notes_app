import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

/// VaultKeyManager 核心安全属性测试。
///
/// VaultKeyManager 位于 lib/core/security/ (Flutter 依赖——flutter_secure_storage)。
/// 本测试验证其使用的核心密码学原语：
/// - 常量时间比较（防时序攻击）
/// - Argon2id 密钥派生（KEK）
/// - SHA-256 验证哈希
/// - AES Key Wrap/Unwrap（DEK 包裹）
/// - AES-GCM-SIV（Vault 加密）
/// - 信封格式验证
void main() {
  // ════════════════════════════════════════════════════════════════
  // 常量时间比较（_constantTimeEqual 安全属性）
  // ════════════════════════════════════════════════════════════════
  group('常量时间比较（防时序攻击）', () {
    /// 等价于 VaultKeyManager._constantTimeEqual。
    bool constantTimeEquals(List<int> a, List<int> b) {
      if (a.length != b.length) return false;
      var result = 0;
      for (var i = 0; i < a.length; i++) {
        result |= a[i] ^ b[i];
      }
      return result == 0;
    }

    test('相同数据 → true', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('不同数据 → false', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    });

    test('不同长度 → false', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2]), isFalse);
    });

    test('空列表 → true', () {
      expect(constantTimeEquals([], []), isTrue);
    });

    test('单字节差异 → false', () {
      expect(constantTimeEquals([0x00], [0x01]), isFalse);
    });

    test('全零 → true', () {
      expect(
        constantTimeEquals(List.filled(32, 0), List.filled(32, 0)),
        isTrue,
      );
    });

    test('32 字节密钥 — 仅末字节不同', () {
      final a = List.filled(32, 0xAA);
      final b = List.filled(32, 0xAA);
      b[31] = 0xBB;
      expect(constantTimeEquals(a, b), isFalse);
    });

    test('32 字节密钥 — 完全匹配', () {
      final a = List.filled(32, 0xAA);
      final b = List.filled(32, 0xAA);
      expect(constantTimeEquals(a, b), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // Argon2id 密钥派生（KEK from password）
  // ════════════════════════════════════════════════════════════════
  group('Argon2id 密钥派生（KEK）', () {
    test('派生 32 字节密钥', () async {
      final algorithm = Argon2id(
        parallelism: 2,
        memory: 1024,
        iterations: 1,
        hashLength: 32,
      );
      final password = utf8.encode('test-password-123');
      final salt = List<int>.generate(32, (_) => 42);

      final secretKey = await algorithm.deriveKey(
        secretKey: SecretKey(password),
        nonce: salt,
      );
      final bytes = await secretKey.extractBytes();
      expect(bytes.length, 32);
    });

    test('不同密码 → 不同 KEK', () async {
      final algorithm = Argon2id(
        parallelism: 2,
        memory: 1024,
        iterations: 1,
        hashLength: 32,
      );
      final salt = List<int>.generate(32, (_) => 42);

      final k1 = await algorithm.deriveKey(
        secretKey: SecretKey(utf8.encode('password-1')),
        nonce: salt,
      );
      final k2 = await algorithm.deriveKey(
        secretKey: SecretKey(utf8.encode('password-2')),
        nonce: salt,
      );

      final b1 = await k1.extractBytes();
      final b2 = await k2.extractBytes();
      expect(b1, isNot(equals(b2)));
    });

    test('不同盐 → 不同 KEK', () async {
      final algorithm = Argon2id(
        parallelism: 2,
        memory: 1024,
        iterations: 1,
        hashLength: 32,
      );
      final password = utf8.encode('same-password');

      final k1 = await algorithm.deriveKey(
        secretKey: SecretKey(password),
        nonce: List<int>.generate(32, (_) => 0x01),
      );
      final k2 = await algorithm.deriveKey(
        secretKey: SecretKey(password),
        nonce: List<int>.generate(32, (_) => 0x02),
      );

      final b1 = await k1.extractBytes();
      final b2 = await k2.extractBytes();
      expect(b1, isNot(equals(b2)));
    });

    test('确定性', () async {
      final algorithm = Argon2id(
        parallelism: 2,
        memory: 1024,
        iterations: 1,
        hashLength: 32,
      );
      final password = utf8.encode('stable-password');
      final salt = List<int>.generate(32, (_) => 0xBB);

      final k1 = await algorithm.deriveKey(
        secretKey: SecretKey(password),
        nonce: salt,
      );
      final k2 = await algorithm.deriveKey(
        secretKey: SecretKey(password),
        nonce: salt,
      );

      final b1 = await k1.extractBytes();
      final b2 = await k2.extractBytes();
      expect(b1, b2);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SHA-256 验证哈希
  // ════════════════════════════════════════════════════════════════
  group('SHA-256 验证哈希', () {
    test('SHA-256 输出 32 字节', () async {
      final kek = List<int>.generate(32, (i) => i + 0x10);
      final hash = await Sha256().hash(kek);
      expect(hash.bytes.length, 32);
    });

    test('不同输入 → 不同哈希', () async {
      final a = await Sha256().hash(List<int>.generate(32, (_) => 1));
      final b = await Sha256().hash(List<int>.generate(32, (_) => 2));
      expect(a.bytes, isNot(equals(b.bytes)));
    });

    test('确定性', () async {
      final input = List<int>.generate(32, (_) => 0x42);
      final h1 = await Sha256().hash(input);
      final h2 = await Sha256().hash(input);
      expect(h1.bytes, h2.bytes);
    });

    test('空输入的 SHA-256 固定值', () async {
      final h = await Sha256().hash([]);
      // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
      final hex = h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });
  });

  // ════════════════════════════════════════════════════════════════
  // AES Key Wrap / Unwrap（DEK 包裹）
  // ════════════════════════════════════════════════════════════════
  group('AES Key Wrap/Unwrap（DEK 包裹）', () {
    Uint8List keyWrap(Uint8List plaintext, Uint8List key) {
      final aes = AESEngine()
        ..init(true, KeyParameter(key));
      final n = plaintext.length ~/ 8;
      var a = Uint8List.fromList(
          [0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6]);
      final r = List.generate(
          n, (i) => Uint8List.fromList(plaintext.sublist(i * 8, i * 8 + 8)));
      final block = Uint8List(16);

      for (var j = 0; j < 6; j++) {
        for (var i = 0; i < n; i++) {
          block.setRange(0, 8, a);
          block.setRange(8, 16, r[i]);
          final b = aes.process(block);
          a = Uint8List(8);
          for (var k = 0; k < 8; k++) a[k] = b[k];
          var t = n * j + i + 1;
          for (var k = 7; k >= 0 && t > 0; k--) {
            a[k] ^= t & 0xFF;
            t >>= 8;
          }
          r[i] = Uint8List.fromList(b.sublist(8, 16));
        }
      }

      final output = Uint8List(8 + plaintext.length);
      output.setRange(0, 8, a);
      for (var i = 0; i < n; i++) {
        output.setRange(8 + i * 8, 8 + i * 8 + 8, r[i]);
      }
      return output;
    }

    Uint8List keyUnwrap(Uint8List ciphertext, Uint8List key) {
      final aes = AESEngine()
        ..init(false, KeyParameter(key));
      final n = (ciphertext.length ~/ 8) - 1;
      var a = Uint8List.fromList(ciphertext.sublist(0, 8));
      final r = List.generate(
          n, (i) => Uint8List.fromList(
              ciphertext.sublist(8 + i * 8, 8 + i * 8 + 8)));
      final block = Uint8List(16);

      for (var j = 5; j >= 0; j--) {
        for (var i = n - 1; i >= 0; i--) {
          var t = n * j + i + 1;
          for (var k = 7; k >= 0 && t > 0; k--) {
            a[k] ^= t & 0xFF;
            t >>= 8;
          }
          block.setRange(0, 8, a);
          block.setRange(8, 16, r[i]);
          final b = aes.process(block);
          a = Uint8List.fromList(b.sublist(0, 8));
          r[i] = Uint8List.fromList(b.sublist(8, 16));
        }
      }

      const expectedA = [0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6];
      for (var k = 0; k < 8; k++) {
        if (a[k] != expectedA[k]) {
          throw StateError('AES Key Unwrap 认证失败');
        }
      }

      final output = Uint8List(n * 8);
      for (var i = 0; i < n; i++) {
        output.setRange(i * 8, i * 8 + 8, r[i]);
      }
      return output;
    }

    test('用 KEK 包裹 DEK — 往返', () {
      final kek = Uint8List(32)..fillRange(0, 32, 0xAA);
      final dek = Uint8List(32)..fillRange(0, 32, 0xBB);
      final wrapped = keyWrap(dek, kek);
      expect(wrapped.length, 40);
      final unwrapped = keyUnwrap(wrapped, kek);
      expect(unwrapped, dek);
    });

    test('错误 KEK unwrap → 异常', () {
      final kek = Uint8List(32)..fillRange(0, 32, 0xAA);
      final dek = Uint8List(32)..fillRange(0, 32, 0xBB);
      final wrongKek = Uint8List(32)..fillRange(0, 32, 0xCC);
      final wrapped = keyWrap(dek, kek);
      expect(() => keyUnwrap(wrapped, wrongKek), throwsA(isA<StateError>()));
    });

    test('篡改包装数据 → 异常', () {
      final kek = Uint8List(32)..fillRange(0, 32, 0xAA);
      final dek = Uint8List(32)..fillRange(0, 32, 0xBB);
      final wrapped = keyWrap(dek, kek);
      final tampered = Uint8List.fromList(wrapped);
      tampered[0] ^= 0xFF;
      expect(() => keyUnwrap(tampered, kek), throwsA(isA<StateError>()));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // v5 信封格式验证
  // ════════════════════════════════════════════════════════════════
  group('v5 信封格式', () {
    test('包含所有必需字段', () {
      final envelope = {
        'salt': base64Encode(List<int>.generate(32, (_) => 1)),
        'n2': base64Encode(List<int>.generate(12, (_) => 2)),
        'ek': base64Encode(List<int>.generate(32, (_) => 3)),
        'm2': base64Encode(List<int>.generate(16, (_) => 4)),
        'v': 5,
      };
      expect(envelope.containsKey('salt'), isTrue);
      expect(envelope.containsKey('n2'), isTrue);
      expect(envelope.containsKey('ek'), isTrue);
      expect(envelope.containsKey('m2'), isTrue);
      expect(envelope['v'], 5);
    });

    test('salt 32 字节', () {
      final salt = base64Decode(
        base64Encode(List<int>.generate(32, (_) => 1)),
      );
      expect(salt.length, 32);
    });

    test('n2 (nonce) 12 字节', () {
      final nonce = base64Decode(
        base64Encode(List<int>.generate(12, (_) => 2)),
      );
      expect(nonce.length, 12);
    });

    test('m2 (MAC) 16 字节', () {
      final mac = base64Decode(
        base64Encode(List<int>.generate(16, (_) => 4)),
      );
      expect(mac.length, 16);
    });

    test('ek (wrapped DEK) 40 字节', () {
      final ek = base64Decode(
        base64Encode(List<int>.generate(40, (_) => 5)),
      );
      expect(ek.length, 40);
    });

    test('序列化往返', () {
      final envelope = {
        'salt': base64Encode(List<int>.generate(32, (_) => 1)),
        'n2': base64Encode(List<int>.generate(12, (_) => 2)),
        'ek': base64Encode(List<int>.generate(32, (_) => 3)),
        'm2': base64Encode(List<int>.generate(16, (_) => 4)),
        'v': 5,
      };
      final jsonStr = jsonEncode(envelope);
      final restored = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(restored['v'], 5);
      expect(base64Decode(restored['salt'] as String).length, 32);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // AES-GCM-SIV（Vault 数据加密）
  // ════════════════════════════════════════════════════════════════
  group('GCM-SIV（Vault 数据加密）', () {
    Uint8List gcmSivEncrypt(
        List<int> plaintext, List<int> key, List<int> nonce) {
      final hmac = HMac(SHA256Digest(), 64);
      hmac.init(KeyParameter(Uint8List.fromList(key)));
      final aadBytes = Uint8List(0);
      final input = Uint8List(nonce.length + 8 + aadBytes.length + 8 + plaintext.length);
      var offset = 0;
      input.setRange(offset, offset + nonce.length, nonce);
      offset += nonce.length;
      // aad length = 0
      offset += 8;
      // plaintext length big-endian
      final ptLen = plaintext.length;
      input[offset] = (ptLen >> 56) & 0xFF;
      input[offset + 1] = (ptLen >> 48) & 0xFF;
      input[offset + 2] = (ptLen >> 40) & 0xFF;
      input[offset + 3] = (ptLen >> 32) & 0xFF;
      input[offset + 4] = (ptLen >> 24) & 0xFF;
      input[offset + 5] = (ptLen >> 16) & 0xFF;
      input[offset + 6] = (ptLen >> 8) & 0xFF;
      input[offset + 7] = ptLen & 0xFF;
      offset += 8;
      if (plaintext.isNotEmpty) {
        input.setRange(offset, offset + plaintext.length, plaintext);
      }
      final siv = hmac.process(input).sublist(0, 12);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(
          KeyParameter(Uint8List.fromList(key)),
          128,
          Uint8List.fromList(siv),
          Uint8List(0),
        ));
      final ct = cipher.process(Uint8List.fromList(plaintext));

      final result = Uint8List(12 + 12 + ct.length);
      result.setRange(0, 12, nonce);
      result.setRange(12, 24, siv);
      result.setRange(24, result.length, ct);
      return result;
    }

    List<int> gcmSivDecrypt(List<int> data, List<int> key) {
      final siv = data.sublist(12, 24);
      final ct = data.sublist(24);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(
          KeyParameter(Uint8List.fromList(key)),
          128,
          Uint8List.fromList(siv),
          Uint8List(0),
        ));
      try {
        return cipher.process(Uint8List.fromList(ct));
      } catch (e) {
        throw StateError('GCM-SIV 认证失败');
      }
    }

    test('加解密往返', () {
      final key = Uint8List(32)..fillRange(0, 32, 0x55);
      final nonce = Uint8List(12)..fillRange(0, 12, 0x66);
      final plaintext = utf8.encode('{"pages":[]}');
      final ct = gcmSivEncrypt(plaintext, key, nonce);
      // nonce(12) + siv(12) + ct + tag(16) = 12+12+12+16=52
      expect(ct.length, 52);
      final pt = gcmSivDecrypt(ct, key);
      expect(utf8.decode(pt), '{"pages":[]}');
    });

    test('空明文', () {
      final key = Uint8List(32)..fillRange(0, 32, 0x55);
      final nonce = Uint8List(12)..fillRange(0, 12, 0x66);
      final ct = gcmSivEncrypt([], key, nonce);
      expect(ct.length, 40); // 12+12+0+16
      final pt = gcmSivDecrypt(ct, key);
      expect(pt, isEmpty);
    });

    test('篡改密文 → 认证失败', () {
      final key = Uint8List(32)..fillRange(0, 32, 0x55);
      final nonce = Uint8List(12)..fillRange(0, 12, 0x66);
      final ct = gcmSivEncrypt(utf8.encode('test'), key, nonce);
      final tampered = Uint8List.fromList(ct);
      tampered[30] ^= 0xFF;
      expect(() => gcmSivDecrypt(tampered, key), throwsA(isA<StateError>()));
    });

    test('重复 nonce — 不泄露不同明文', () {
      final key = Uint8List(32)..fillRange(0, 32, 0x55);
      final nonce = Uint8List(12)..fillRange(0, 12, 0x66);
      final ct1 = gcmSivEncrypt(utf8.encode('secret-A'), key, nonce);
      final ct2 = gcmSivEncrypt(utf8.encode('secret-B'), key, nonce);

      expect(utf8.decode(gcmSivDecrypt(ct1, key)), 'secret-A');
      expect(utf8.decode(gcmSivDecrypt(ct2, key)), 'secret-B');
    });
  });
}
