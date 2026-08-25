import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:editor_core/src/domain/crypto_utils.dart';

/// 性能基准测试——验证关键加密路径在可接受阈值内。
///
/// 阈值基于 CI 环境实测值 ×3 安全系数（CI 通常比生产硬件慢 3-5 倍）。
/// 纯 Dart 运行（无 Flutter 渲染层）。
void main() {
  // ════════════════════════════════════════════════════════════════
  // 加密性能基准
  // ════════════════════════════════════════════════════════════════
  group('加密性能基准', () {
    final key = Uint8List(32)..fillRange(0, 32, 0xAB);
    final nonce = Uint8List(12)..fillRange(0, 12, 0xCD);

    test('AES-256-GCM 加解密 1MB — CI < 5s', () {
      final plaintext = Uint8List(1024 * 1024); // 1MB
      final sw = Stopwatch()..start();
      final ct = aes256GcmEncrypt(plaintext: plaintext, key: key, nonce: nonce);
      final pt = aes256GcmDecrypt(ciphertextWithTag: ct, key: key, nonce: nonce);
      sw.stop();
      expect(pt.length, plaintext.length);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('ChaCha20-Poly1305 加解密 1MB — CI < 500ms', () {
      final plaintext = Uint8List(1024 * 1024);
      final sw = Stopwatch()..start();
      final ct = chacha20Poly1305Encrypt(
        plaintext: plaintext, key: key, nonce: nonce,
      );
      final pt = chacha20Poly1305Decrypt(
        ciphertextWithTag: ct, key: key, nonce: nonce,
      );
      sw.stop();
      expect(pt.length, plaintext.length);
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('XChaCha20-Poly1305 加解密 1MB — CI < 500ms', () {
      final plaintext = Uint8List(1024 * 1024);
      final xNonce = Uint8List(24)..fillRange(0, 24, 0xEF);
      final sw = Stopwatch()..start();
      final ct = xchacha20Poly1305Encrypt(
        plaintext: plaintext, key: key, nonce: xNonce,
      );
      final pt = xchacha20Poly1305Decrypt(
        ciphertextWithTag: ct, key: key, nonce: xNonce,
      );
      sw.stop();
      expect(pt.length, plaintext.length);
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('AES Key Wrap 32字节 — CI < 20ms', () {
      final dek = Uint8List(32)..fillRange(0, 32, 0x11);
      final sw = Stopwatch()..start();
      final wrapped = aes256KeyWrap(plaintext: dek, key: key);
      final unwrapped = aes256KeyUnwrap(ciphertext: wrapped, key: key);
      sw.stop();
      expect(unwrapped, dek);
      expect(sw.elapsedMilliseconds, lessThan(20));
    });

    test('SHA-256 哈希 1MB — CI < 500ms', () {
      final data = Uint8List(1024 * 1024);
      final sw = Stopwatch()..start();
      sha256Hex(data);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('deriveKeyFromPassword (PBKDF2) — < 5s', () {
      final salt = secureRandomBytes(16);
      final sw = Stopwatch()..start();
      deriveKeyFromPassword(
        password: 'test-password-123456',
        salt: salt,
        rounds: 10000,
      );
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('HKDF-SHA256 64 字节输出 — CI < 20ms', () {
      final ikm = Uint8List(32)..fillRange(0, 32, 0x55);
      final sw = Stopwatch()..start();
      hkdfSha256(ikm: ikm, info: const [1, 2, 3], outputLength: 64);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(20));
    });

    test('GCM-SIV 加解密 1MB — CI < 5s', () {
      final plaintext = Uint8List(1024 * 1024);
      final sw = Stopwatch()..start();
      final ct = aes256GcmSivEncrypt(
        plaintext: plaintext, key: key, nonce: nonce,
      );
      final pt = aes256GcmSivDecrypt(data: ct, key: key);
      sw.stop();
      expect(pt.length, plaintext.length);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // KeyRotationManager 性能
  // ════════════════════════════════════════════════════════════════
  group('KeyRotationManager 性能', () {
    test('100 次轮换 — < 50ms', () async {
      final keyStore = <String, Uint8List>{};
      final mgr = KeyRotationManager(
        storeKey: (keyId, data) async {
          keyStore[keyId] = Uint8List.fromList(data);
        },
        loadKey: (keyId) async => keyStore[keyId],
        deleteKey: (keyId) async { keyStore.remove(keyId); },
        maxActiveVersions: 3,
        rotationIntervalDays: 30,
      );
      final sw = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        await mgr.rotateKey();
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // secureRandomBytes 性能
  // ════════════════════════════════════════════════════════════════
  group('secureRandomBytes 性能', () {
    test('生成 1000 × 32 字节 — < 50ms', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        secureRandomBytes(32);
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });
}
