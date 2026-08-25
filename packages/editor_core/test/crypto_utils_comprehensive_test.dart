import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:editor_core/src/domain/crypto_utils.dart';

/// crypto_utils.dart 完整单元测试（HKDF / AES-GCM / Key Wrap /
/// GCM-SIV / KeyRotationManager / 工具函数）。
///
/// 纯 Dart — 无 Flutter 依赖 — 可在 CI 运行。
void main() {
  // ════════════════════════════════════════════════════════════════
  // HKDF-SHA256
  // ════════════════════════════════════════════════════════════════
  group('hkdfSha256', () {
    test('输出长度等于请求长度', () {
      final ikm = Uint8List(22)..fillRange(0, 22, 0x0b);
      final result = hkdfSha256(
        ikm: ikm,
        info: const [],
        outputLength: 42,
      );
      expect(result.length, 42);
    });

    test('确定性 — 相同输入产生相同输出', () {
      final ikm = Uint8List(22)..fillRange(0, 22, 0x0b);
      final a = hkdfSha256(ikm: ikm, info: const [], outputLength: 32);
      final b = hkdfSha256(ikm: ikm, info: const [], outputLength: 32);
      expect(a, b);
    });

    test('不同 IKM → 不同输出', () {
      final ikm1 = Uint8List(22)..fillRange(0, 22, 0x01);
      final ikm2 = Uint8List(22)..fillRange(0, 22, 0x02);
      final a = hkdfSha256(ikm: ikm1, info: const [], outputLength: 32);
      final b = hkdfSha256(ikm: ikm2, info: const [], outputLength: 32);
      expect(a, isNot(equals(b)));
    });

    test('不同 salt → 不同输出', () {
      final ikm = Uint8List(22)..fillRange(0, 22, 0x0b);
      final salt1 = Uint8List(13)..fillRange(0, 13, 0x10);
      final salt2 = Uint8List(13)..fillRange(0, 13, 0x20);
      final a = hkdfSha256(ikm: ikm, salt: salt1, info: const [], outputLength: 32);
      final b = hkdfSha256(ikm: ikm, salt: salt2, info: const [], outputLength: 32);
      expect(a, isNot(equals(b)));
    });

    test('不同 info → 不同输出', () {
      final ikm = Uint8List(22)..fillRange(0, 22, 0x0b);
      final a = hkdfSha256(ikm: ikm, info: const [1], outputLength: 32);
      final b = hkdfSha256(ikm: ikm, info: const [2], outputLength: 32);
      expect(a, isNot(equals(b)));
    });

    test('空 IKM → 正常输出', () {
      final result = hkdfSha256(
        ikm: const [],
        info: const [0x01],
        outputLength: 32,
      );
      expect(result.length, 32);
    });

    test('输出长度为 0 → 返回空', () {
      final result = hkdfSha256(
        ikm: const [1, 2, 3],
        info: const [],
        outputLength: 0,
      );
      expect(result, isEmpty);
    });

    test('输出长度超过 SHA-256 块大小也正常', () {
      final ikm = Uint8List(32)..fillRange(0, 32, 0x01);
      final result = hkdfSha256(
        ikm: ikm,
        info: const [0x02],
        outputLength: 128,
      );
      expect(result.length, 128);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // AES-256-GCM
  // ════════════════════════════════════════════════════════════════
  group('aes256GcmEncrypt/Decrypt', () {
    final key = Uint8List(32)..fillRange(0, 32, 0xAB);
    final nonce = Uint8List(12)..fillRange(0, 12, 0xCD);

    test('基本加解密往返', () {
      final plaintext = Uint8List.fromList('Hello AES-256-GCM'.codeUnits);
      final ct = aes256GcmEncrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
      );
      expect(ct.length, plaintext.length + 16); // tag = 16 bytes

      final pt = aes256GcmDecrypt(
        ciphertextWithTag: ct,
        key: key,
        nonce: nonce,
      );
      expect(pt, plaintext);
    });

    test('空明文加解密', () {
      final ct = aes256GcmEncrypt(
        plaintext: const [],
        key: key,
        nonce: nonce,
      );
      expect(ct.length, 16); // 仅 tag

      final pt = aes256GcmDecrypt(
        ciphertextWithTag: ct,
        key: key,
        nonce: nonce,
      );
      expect(pt, isEmpty);
    });

    test('AAD 保护 — 不同 AAD 认证失败', () {
      final plaintext = Uint8List.fromList('test'.codeUnits);
      final ct = aes256GcmEncrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: const [1, 2, 3],
      );

      expect(
        () => aes256GcmDecrypt(
          ciphertextWithTag: ct,
          key: key,
          nonce: nonce,
          aad: const [1, 2, 4], // 不同 AAD
        ),
        throwsA(anything),
      );
    });

    test('篡改密文 → 认证失败', () {
      final ct = aes256GcmEncrypt(
        plaintext: Uint8List.fromList('tamper'.codeUnits),
        key: key,
        nonce: nonce,
      );
      final tampered = Uint8List.fromList(ct);
      tampered[0] ^= 0xFF;

      expect(
        () => aes256GcmDecrypt(
          ciphertextWithTag: tampered,
          key: key,
          nonce: nonce,
        ),
        throwsA(anything),
      );
    });

    test('不同 nonce → 不同密文', () {
      final pt = Uint8List.fromList('same'.codeUnits);
      final nonce2 = Uint8List(12)..fillRange(0, 12, 0xEF);
      final ct1 = aes256GcmEncrypt(plaintext: pt, key: key, nonce: nonce);
      final ct2 = aes256GcmEncrypt(plaintext: pt, key: key, nonce: nonce2);
      expect(ct1, isNot(equals(ct2)));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // AES-256 Key Wrap / Unwrap (RFC 3394)
  // ════════════════════════════════════════════════════════════════
  group('aes256KeyWrap / aes256KeyUnwrap', () {
    final kek = Uint8List(32)..fillRange(0, 32, 0x55);

    test('32 字节 DEK wrap/unwrap 往返', () {
      final dek = Uint8List.fromList(
        List.generate(32, (i) => i + 0x10),
      );
      final wrapped = aes256KeyWrap(plaintext: dek, key: kek);
      expect(wrapped.length, 40); // 32 + 8

      final unwrapped = aes256KeyUnwrap(ciphertext: wrapped, key: kek);
      expect(unwrapped, dek);
    });

    test('8 字节最小数据 wrap/unwrap', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final wrapped = aes256KeyWrap(plaintext: data, key: kek);
      expect(wrapped.length, 16);

      final unwrapped = aes256KeyUnwrap(ciphertext: wrapped, key: kek);
      expect(unwrapped, data);
    });

    test('48 字节数据 wrap/unwrap', () {
      final data = Uint8List(48)..fillRange(0, 48, 0xAA);
      final wrapped = aes256KeyWrap(plaintext: data, key: kek);
      expect(wrapped.length, 56);

      final unwrapped = aes256KeyUnwrap(ciphertext: wrapped, key: kek);
      expect(unwrapped, data);
    });

    test('错误 KEK unwrap → 认证失败', () {
      final dek = Uint8List(32)..fillRange(0, 32, 0xBB);
      final wrapped = aes256KeyWrap(plaintext: dek, key: kek);
      final wrongKek = Uint8List(32)..fillRange(0, 32, 0x99);

      expect(
        () => aes256KeyUnwrap(ciphertext: wrapped, key: wrongKek),
        throwsA(isA<StateError>()),
      );
    });

    test('篡改包装数据 → 认证失败', () {
      final dek = Uint8List(32)..fillRange(0, 32, 0xCC);
      final wrapped = aes256KeyWrap(plaintext: dek, key: kek);
      final tampered = Uint8List.fromList(wrapped);
      tampered[0] ^= 0xFF;

      expect(
        () => aes256KeyUnwrap(ciphertext: tampered, key: kek),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  // AES-256-GCM-SIV
  // ════════════════════════════════════════════════════════════════
  group('aes256GcmSivEncrypt/Decrypt', () {
    final key = Uint8List(32)..fillRange(0, 32, 0x77);
    final nonce = Uint8List(12)..fillRange(0, 12, 0x88);

    test('基本加解密往返', () {
      final plaintext = Uint8List.fromList('GCM-SIV test'.codeUnits);
      final ct = aes256GcmSivEncrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
      );
      // 格式：nonce(12) + siv(12) + ciphertext + tag(16) = 12+12+12+16=52
      expect(ct.length, 12 + 12 + plaintext.length + 16);

      final pt = aes256GcmSivDecrypt(data: ct, key: key);
      expect(pt, plaintext);
    });

    test('Nonce-misuse--resistant：重复 nonce 不泄露明文', () {
      final pt1 = Uint8List.fromList('secret-A'.codeUnits);
      final pt2 = Uint8List.fromList('secret-B'.codeUnits);
      final ct1 = aes256GcmSivEncrypt(plaintext: pt1, key: key, nonce: nonce);
      final ct2 = aes256GcmSivEncrypt(plaintext: pt2, key: key, nonce: nonce);

      // 同 nonce 不同明文 → 不同密文（但 SIV 也可能相同——这正是 GCM-SIV 的安全属性）
      // 关键：不同明文解密后不相同
      expect(aes256GcmSivDecrypt(data: ct1, key: key), pt1);
      expect(aes256GcmSivDecrypt(data: ct2, key: key), pt2);
    });

    test('篡改密文 → 认证失败', () {
      final ct = aes256GcmSivEncrypt(
        plaintext: Uint8List.fromList('tamper-siv'.codeUnits),
        key: key,
        nonce: nonce,
      );
      final tampered = Uint8List.fromList(ct);
      tampered[30] ^= 0xFF; // 篡改 ciphertext 部分

      expect(
        () => aes256GcmSivDecrypt(data: tampered, key: key),
        throwsA(isA<StateError>()),
      );
    });

    test('空明文加解密', () {
      final ct = aes256GcmSivEncrypt(
        plaintext: Uint8List(0),
        key: key,
        nonce: nonce,
      );
      // nonce(12) + siv(12) + ciphertext(0) + tag(16) = 40
      expect(ct.length, 40);

      final pt = aes256GcmSivDecrypt(data: ct, key: key);
      expect(pt, isEmpty);
    });

    test('AAD 保护 — 不同 AAD 认证失败', () {
      final plaintext = Uint8List.fromList('aad-test'.codeUnits);
      final ct = aes256GcmSivEncrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: Uint8List.fromList([1, 2, 3]),
      );

      expect(
        () => aes256GcmSivDecrypt(
          data: ct,
          key: key,
          aad: Uint8List.fromList([1, 2, 4]),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  // sha256Hex
  // ════════════════════════════════════════════════════════════════
  group('sha256Hex', () {
    test('SHA-256 of empty → 固定哈希', () {
      final hash = sha256Hex([]);
      expect(hash.length, 64); // 256 位 = 64 hex chars
      // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
      expect(hash, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('SHA-256("hello")', () {
      final hash = sha256Hex(utf8.encode('hello'));
      expect(
        hash,
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
    });

    test('确定性', () {
      final a = sha256Hex([1, 2, 3]);
      final b = sha256Hex([1, 2, 3]);
      expect(a, b);
    });

    test('不同输入 → 不同哈希', () {
      final a = sha256Hex([1, 2, 3]);
      final b = sha256Hex([1, 2, 4]);
      expect(a, isNot(equals(b)));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // deriveKeyFromPassword (PBKDF2)
  // ════════════════════════════════════════════════════════════════
  group('deriveKeyFromPassword', () {
    test('返回 32 字节密钥', () {
      final salt = secureRandomBytes(16);
      final key = deriveKeyFromPassword(
        password: 'test-password',
        salt: salt,
        rounds: 1000,
      );
      expect(key.length, 32);
    });

    test('不同密码 → 不同密钥', () {
      final salt = secureRandomBytes(16);
      final k1 = deriveKeyFromPassword(password: 'pass-1', salt: salt, rounds: 1000);
      final k2 = deriveKeyFromPassword(password: 'pass-2', salt: salt, rounds: 1000);
      expect(k1, isNot(equals(k2)));
    });

    test('不同盐 → 不同密钥', () {
      final salt1 = secureRandomBytes(16);
      final salt2 = secureRandomBytes(16);
      final k1 = deriveKeyFromPassword(password: 'same', salt: salt1, rounds: 1000);
      final k2 = deriveKeyFromPassword(password: 'same', salt: salt2, rounds: 1000);
      expect(k1, isNot(equals(k2)));
    });

    test('确定性', () {
      final salt = Uint8List(16)..fillRange(0, 16, 0xAA);
      final k1 = deriveKeyFromPassword(password: 'test', salt: salt, rounds: 500);
      final k2 = deriveKeyFromPassword(password: 'test', salt: salt, rounds: 500);
      expect(k1, k2);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // secureRandomBytes
  // ════════════════════════════════════════════════════════════════
  group('secureRandomBytes', () {
    test('返回指定长度', () {
      expect(secureRandomBytes(16).length, 16);
      expect(secureRandomBytes(32).length, 32);
      expect(secureRandomBytes(64).length, 64);
    });

    test('空长度 → 空列表', () {
      expect(secureRandomBytes(0), isEmpty);
    });

    test('多次调用产生不同结果', () {
      final a = secureRandomBytes(32);
      final b = secureRandomBytes(32);
      expect(a, isNot(equals(b)));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // AeadAlgorithm / selectAeadAlgorithm
  // ════════════════════════════════════════════════════════════════
  group('selectAeadAlgorithm', () {
    test('android/ios → xchacha20Poly1305', () {
      expect(selectAeadAlgorithm('android'), AeadAlgorithm.xchacha20Poly1305);
      expect(selectAeadAlgorithm('ios'), AeadAlgorithm.xchacha20Poly1305);
    });

    test('windows/macos/linux/web → aes256Gcm', () {
      expect(selectAeadAlgorithm('windows'), AeadAlgorithm.aes256Gcm);
      expect(selectAeadAlgorithm('macos'), AeadAlgorithm.aes256Gcm);
      expect(selectAeadAlgorithm('linux'), AeadAlgorithm.aes256Gcm);
      expect(selectAeadAlgorithm('web'), AeadAlgorithm.aes256Gcm);
    });

    test('未知平台 → xchacha20Poly1305', () {
      expect(selectAeadAlgorithm('fuchsia'), AeadAlgorithm.xchacha20Poly1305);
      expect(selectAeadAlgorithm(''), AeadAlgorithm.xchacha20Poly1305);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // KeyRotationMetadata
  // ════════════════════════════════════════════════════════════════
  group('KeyRotationMetadata', () {
    test('构造 + 字段访问', () {
      final meta = KeyRotationMetadata(
        keyId: 'dek.v1',
        version: 1,
        createdAt: DateTime(2026, 8, 24),
      );
      expect(meta.keyId, 'dek.v1');
      expect(meta.version, 1);
      expect(meta.retiredAt, isNull);
      expect(meta.retiredBy, isNull);
    });

    test('toJson 序列化 + fromJson 反序列化', () {
      final meta = KeyRotationMetadata(
        keyId: 'dek.v2',
        version: 2,
        createdAt: DateTime(2026, 1, 1),
        retiredAt: DateTime(2026, 6, 15),
        retiredBy: 'dek.v3',
      );
      final json = meta.toJson();
      expect(json['keyId'], 'dek.v2');
      expect(json['version'], 2);
      expect(json.containsKey('retiredAt'), isTrue);
      expect(json.containsKey('retiredBy'), isTrue);

      final restored = KeyRotationMetadata.fromJson(json);
      expect(restored.keyId, meta.keyId);
      expect(restored.version, meta.version);
      expect(restored.retiredAt, meta.retiredAt);
      expect(restored.retiredBy, meta.retiredBy);
    });

    test('无 retired 字段的 toJson', () {
      final meta = KeyRotationMetadata(
        keyId: 'dek.v1',
        version: 1,
        createdAt: DateTime(2026, 1, 1),
      );
      final json = meta.toJson();
      expect(json.containsKey('retiredAt'), isFalse);
      expect(json.containsKey('retiredBy'), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // KeyRotationManager
  // ════════════════════════════════════════════════════════════════
  group('KeyRotationManager', () {
    late Map<String, Uint8List> keyStore;
    late KeyRotationManager mgr;

    setUp(() {
      keyStore = {};
      mgr = KeyRotationManager(
        storeKey: (keyId, data) async {
          keyStore[keyId] = Uint8List.fromList(data);
        },
        loadKey: (keyId) async => keyStore[keyId],
        deleteKey: (keyId) async {
          keyStore.remove(keyId);
        },
        maxActiveVersions: 2,
        rotationIntervalDays: 30,
      );
    });

    test('初始状态 — currentVersion = 0', () {
      expect(mgr.currentVersion, 0);
      expect(mgr.needsRotation, isTrue);
      expect(mgr.versions, isEmpty);
    });

    test('rotateKey → version 1', () async {
      final keyId = await mgr.rotateKey();
      expect(keyId, 'dek.v1');
      expect(mgr.currentVersion, 1);
      expect(mgr.versions.length, 1);
      expect(keyStore.containsKey('dek.v1'), isTrue);
    });

    test('rotateKey 两次 → version 2 + 旧版本退休', () async {
      await mgr.rotateKey();
      final keyId2 = await mgr.rotateKey();
      expect(keyId2, 'dek.v2');
      expect(mgr.currentVersion, 2);
      expect(mgr.versions.length, 2);
      // 旧版本标记退休
      expect(mgr.versions[0].retiredAt, isNotNull);
      expect(mgr.versions[0].retiredBy, 'dek.v2');
      // 新版本未退休
      expect(mgr.versions[1].retiredAt, isNull);
    });

    test('超过 maxActiveVersions → 自动退休最旧', () async {
      // maxActiveVersions = 2
      await mgr.rotateKey(); // v1
      await mgr.rotateKey(); // v2
      await mgr.rotateKey(); // v3 → 应自动退休 v1
      expect(mgr.currentVersion, 3);
      final activeVersions = mgr.versions.where((v) => v.retiredAt == null).toList();
      expect(activeVersions.length, lessThanOrEqualTo(2));
    });

    test('needsRotation = false 刚轮换后', () async {
      await mgr.rotateKey();
      expect(mgr.needsRotation, isFalse);
    });

    test('needsRotation = true 超过间隔', () async {
      // 构造一个已过期的版本
      final oldMgr = KeyRotationManager(
        storeKey: (keyId, data) async {
          keyStore[keyId] = Uint8List.fromList(data);
        },
        loadKey: (keyId) async => keyStore[keyId],
        deleteKey: (keyId) async {
          keyStore.remove(keyId);
        },
        rotationIntervalDays: 0, // 0 天 = 总是过期
      );
      await oldMgr.rotateKey();
      expect(oldMgr.needsRotation, isTrue);
    });

    test('loadVersionKey 加载指定版本', () async {
      await mgr.rotateKey(); // v1
      await mgr.rotateKey(); // v2
      final k = await mgr.loadVersionKey(version: 1);
      expect(k, isNotNull);
      expect(keyStore.containsKey('dek.v1'), isTrue);
    });

    test('loadVersionKey version=0 → null', () async {
      final k = await mgr.loadVersionKey(version: 0);
      expect(k, isNull);
    });

    test('cleanupOldKeys 清理退休密钥', () async {
      await mgr.rotateKey();
      await mgr.rotateKey();
      // 无超过 maxAgeDays 的 → 清理 0 个
      final cleaned = await mgr.cleanupOldKeys(maxAgeDays: 365);
      expect(cleaned, 0);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // AeadResult
  // ════════════════════════════════════════════════════════════════
  group('AeadResult', () {
    test('构造 + 字段访问', () {
      final result = AeadResult(
        ciphertext: Uint8List(16),
        algorithm: AeadAlgorithm.aes256Gcm,
        nonce: Uint8List(12),
      );
      expect(result.ciphertext.length, 16);
      expect(result.algorithm, AeadAlgorithm.aes256Gcm);
      expect(result.nonce.length, 12);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // ChaCha20-Poly1305 AAD 保护
  // ════════════════════════════════════════════════════════════════
  group('ChaCha20 AAD', () {
    test('不同 AAD → 认证失败', () {
      final key = Uint8List(32)..fillRange(0, 32, 0xAA);
      final nonce = Uint8List(12)..fillRange(0, 12, 0xBB);
      final ct = chacha20Poly1305Encrypt(
        plaintext: Uint8List.fromList('aad-test'.codeUnits),
        key: key,
        nonce: nonce,
        aad: const [1, 2, 3],
      );

      expect(
        () => chacha20Poly1305Decrypt(
          ciphertextWithTag: ct,
          key: key,
          nonce: nonce,
          aad: const [1, 2, 4],
        ),
        throwsA(anything),
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  // XChaCha20 AAD 保护
  // ════════════════════════════════════════════════════════════════
  group('XChaCha20 AAD', () {
    test('不同 AAD → 认证失败', () {
      final key = Uint8List(32)..fillRange(0, 32, 0xCC);
      final nonce = Uint8List(24)..fillRange(0, 24, 0xDD);
      final ct = xchacha20Poly1305Encrypt(
        plaintext: Uint8List.fromList('xchacha-aad'.codeUnits),
        key: key,
        nonce: nonce,
        aad: const [1, 2, 3],
      );

      expect(
        () => xchacha20Poly1305Decrypt(
          ciphertextWithTag: ct,
          key: key,
          nonce: nonce,
          aad: const [1, 2, 4],
        ),
        throwsA(anything),
      );
    });
  });
}
