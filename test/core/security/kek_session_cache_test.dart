/// N3 解密提速 B 方案：KekSessionCache 回归测试。
///
/// 覆盖：pointycastle（isolate 内）与 package:cryptography Pbkdf2 逐字节
/// 一致性、缓存命中（同输入零重派生）、clear 擦除（代际防清后复活）、
/// 不同输入不同输出、并发同键去重、LRU 上限封顶、Argon2id 分派与
/// 跨 KDF 缓存隔离（批B）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late KekSessionCache cache;

  setUp(() {
    cache = KekSessionCache.instance;
    cache.clear();
  });

  group('KekSessionCache', () {
    test('pointycastle(isolate) 与 cryptography Pbkdf2 逐字节一致', () async {
      final cryptographyPbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 1000,
        bits: 256,
      );
      final saltA = Uint8List.fromList(utf8.encode('salt-salt-16byte'));
      final saltB = Uint8List.fromList(List.generate(16, (i) => i ^ 0x2F));
      final saltC = Uint8List.fromList(utf8.encode('chinese-salt-16'));
      const cases = [
        ('hello-pin-1', 1000, 0),
        ('另一组密码🔥', 1000, 1),
        ('ascii-pin-003', 1000, 2),
      ];
      final salts = [saltA, saltB, saltC];
      for (final (pw, it, idx) in cases) {
        final salt = salts[idx];
        final expected = await cryptographyPbkdf2.deriveKey(
          secretKey: SecretKey(utf8.encode(pw)),
          nonce: salt,
        );
        final expectedBytes = await expected.extractBytes();
        final actual = await cache.deriveKek(pw, salt, KdfParams.pbkdf2(it));
        expect(actual, orderedEquals(expectedBytes));
      }
      // 大迭代组：600k 与 100k 同实现逐字节一致（盐不同即可）。
      final salt100k = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final ref = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode('big-iter-pw')),
        nonce: salt100k,
      );
      expect(
        await cache.deriveKek('big-iter-pw', salt100k, const KdfParams.pbkdf2(100000)),
        orderedEquals(await ref.extractBytes()),
      );
    });

    test('缓存命中：同输入两次派生结果一致且只存一条', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i * 3));
      final a = await cache.deriveKek('same-pw', salt, const KdfParams.pbkdf2(1000));
      final b = await cache.deriveKek('same-pw', salt, const KdfParams.pbkdf2(1000));
      expect(a, orderedEquals(b));
      expect(cache.entryCount, 1);
      // 不同盐 → 不同条目、不同输出。
      final otherSalt = Uint8List.fromList(List.generate(16, (i) => i * 3 + 1));
      final c = await cache.deriveKek('same-pw', otherSalt, const KdfParams.pbkdf2(1000));
      expect(c, isNot(orderedEquals(a)));
      expect(cache.entryCount, 2);
    });

    test('clear：条目清零；再派生结果不变（功能不受影响）', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final before = await cache.deriveKek('clear-pw', salt, const KdfParams.pbkdf2(1000));
      expect(cache.entryCount, 1);
      cache.clear();
      expect(cache.entryCount, 0);
      final after = await cache.deriveKek('clear-pw', salt, const KdfParams.pbkdf2(1000));
      expect(after, orderedEquals(before));
    });

    test('并发同键去重：并发派生共享同一计算', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i + 7));
      final results = await Future.wait([
        cache.deriveKek('concurrent-pw', salt, const KdfParams.pbkdf2(50000)),
        cache.deriveKek('concurrent-pw', salt, const KdfParams.pbkdf2(50000)),
        cache.deriveKek('concurrent-pw', salt, const KdfParams.pbkdf2(50000)),
      ]);
      expect(results[0], orderedEquals(results[1]));
      expect(results[1], orderedEquals(results[2]));
      expect(cache.entryCount, 1);
    });

    test('LRU 上限封顶：条目数不超过 64', () async {
      for (var i = 0; i < 70; i++) {
        final salt = Uint8List.fromList(List.generate(16, (j) => j + i));
        await cache.deriveKek('lru-pw-$i', salt, const KdfParams.pbkdf2(100));
      }
      expect(cache.entryCount, KekSessionCache.instance.entryCount);
      expect(cache.entryCount, lessThanOrEqualTo(64));
      // 最早的条目（i=0..5）已被淘汰，最新条目仍在。
      final salt69 = Uint8List.fromList(List.generate(16, (j) => j + 69));
      await cache.deriveKek('lru-pw-69', salt69, const KdfParams.pbkdf2(100));
      expect(cache.entryCount, lessThanOrEqualTo(64));
    });

    test('批B：Argon2id 分派——确定性输出 + 与 PBKDF2 结果互异', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i + 21));
      const params = KdfParams.testLight;
      final a = await cache.deriveKek('argon2-pw', salt, params);
      final b = await cache.deriveKek('argon2-pw', salt, params);
      expect(a.length, 32);
      expect(a, orderedEquals(b)); // 确定性 + 缓存命中
      expect(cache.entryCount, 1);
      final pb = await cache.deriveKek(
        'argon2-pw',
        salt,
        const KdfParams.pbkdf2(1000),
      );
      expect(pb, isNot(orderedEquals(a))); // KDF 不同 → 输出不同
      expect(cache.entryCount, 2); // 跨 KDF 缓存隔离
    });

    test('批B：同盐同密码不同 Argon2id 参数 → 不同条目不同输出', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i + 33));
      final a = await cache.deriveKek(
        'argon2-pw',
        salt,
        KdfParams.testLight,
      );
      final b = await cache.deriveKek(
        'argon2-pw',
        salt,
        const KdfParams.argon2id(memoryKiB: 8192, timeCost: 2, parallelism: 1),
      );
      expect(b, isNot(orderedEquals(a)));
      expect(cache.entryCount, 2);
    });
  });
}
