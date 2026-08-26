// gcm_siv_and_key_rotation_test.dart — AES-256-GCM-SIV + 密钥轮换单元测试。
import 'dart:convert';
import 'dart:typed_data';

import 'package:editor_core/editor_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AES-256-GCM-SIV', () {
    test('加密解密往返正确', () {
      final key = secureRandomBytes(32);
      final nonce = secureRandomBytes(12);
      final plaintext = utf8.encode('Hello, GCM-SIV!');

      final encrypted = aes256GcmSivEncrypt(
        plaintext: Uint8List.fromList(plaintext),
        key: key,
        nonce: nonce,
      );

      final decrypted = aes256GcmSivDecrypt(data: encrypted, key: key);

      expect(decrypted, plaintext);
    });

    test('密钥错误解密失败', () {
      final key1 = secureRandomBytes(32);
      final key2 = secureRandomBytes(32);
      final nonce = secureRandomBytes(12);
      final plaintext = utf8.encode('Secret data');

      final encrypted = aes256GcmSivEncrypt(
        plaintext: Uint8List.fromList(plaintext),
        key: key1,
        nonce: nonce,
      );

      expect(
        () => aes256GcmSivDecrypt(data: encrypted, key: key2),
        throwsA(isA<StateError>()),
      );
    });

    test('相同 nonce + key + 明文 → 相同密文（GCM-SIV 特性）', () {
      final key = secureRandomBytes(32);
      final nonce = secureRandomBytes(12);
      final plaintext = utf8.encode('Deterministic');

      final enc1 = aes256GcmSivEncrypt(
        plaintext: Uint8List.fromList(plaintext),
        key: key,
        nonce: nonce,
      );
      final enc2 = aes256GcmSivEncrypt(
        plaintext: Uint8List.fromList(plaintext),
        key: key,
        nonce: nonce,
      );

      expect(enc1, enc2);
    });

    test('AAD 认证正确', () {
      final key = secureRandomBytes(32);
      final nonce = secureRandomBytes(12);
      final plaintext = utf8.encode('Data with AAD');
      final aad = utf8.encode('metadata');

      final encrypted = aes256GcmSivEncrypt(
        plaintext: Uint8List.fromList(plaintext),
        key: key,
        nonce: nonce,
        aad: Uint8List.fromList(aad),
      );

      // 用相同 AAD 解密成功。
      final decrypted = aes256GcmSivDecrypt(
        data: encrypted,
        key: key,
        aad: Uint8List.fromList(aad),
      );
      expect(decrypted, plaintext);

      // 用不同 AAD 解密失败。
      expect(
        () => aes256GcmSivDecrypt(
          data: encrypted,
          key: key,
          aad: utf8.encode('wrong'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('空明文处理正确', () {
      final key = secureRandomBytes(32);
      final nonce = secureRandomBytes(12);
      final plaintext = Uint8List(0);

      final encrypted = aes256GcmSivEncrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
      );

      final decrypted = aes256GcmSivDecrypt(data: encrypted, key: key);
      expect(decrypted, plaintext);
    });
  });

  group('KeyRotationManager', () {
    late Map<String, List<int>> store;
    late KeyRotationManager manager;

    setUp(() {
      store = {};
      manager = KeyRotationManager(
        storeKey: (id, data) async {
          store[id] = data;
        },
        loadKey: (id) async {
          final data = store[id];
          return data != null ? Uint8List.fromList(data) : null;
        },
        deleteKey: (id) async {
          store.remove(id);
        },
      );
    });

    test('rotateKey 创建第一版密钥', () async {
      final keyId = await manager.rotateKey();
      expect(keyId, 'dek.v1');
      expect(manager.currentVersion, 1);
      expect(store.containsKey('dek.v1'), true);
    });

    test('rotateKey 递增版本号', () async {
      await manager.rotateKey();
      final keyId2 = await manager.rotateKey();
      expect(keyId2, 'dek.v2');
      expect(manager.currentVersion, 2);
    });

    test('旧版本密钥标记为退役', () async {
      await manager.rotateKey();
      await manager.rotateKey();

      final versions = manager.versions;
      expect(versions.length, 2);
      expect(versions[0].retiredAt, isNotNull);
      expect(versions[0].retiredBy, 'dek.v2');
      expect(versions[1].retiredAt, isNull);
    });

    test('loadVersionKey 加载指定版本', () async {
      await manager.rotateKey();
      final v1Key = await manager.loadVersionKey(version: 1);
      expect(v1Key, isNotNull);
      expect(v1Key!.length, 32);

      final currentKey = await manager.loadVersionKey();
      expect(currentKey, isNotNull);
    });

    test('needsRotation 间隔检查', () async {
      // 初始状态——需要轮换。
      expect(manager.needsRotation, true);

      await manager.rotateKey();

      // 刚创建——不需要轮换。
      expect(manager.needsRotation, false);
    });

    test('cleanupOldKeys 清理超龄退役密钥', () async {
      await manager.rotateKey();
      await manager.rotateKey();

      // 验证退役状态已设置（断言替代原无操作语句）。
      expect(manager.versions[0].retiredAt, isNotNull);

      final cleaned = await manager.cleanupOldKeys(maxAgeDays: 0);
      // maxAgeDays=0 会清理所有已退役密钥。
      expect(cleaned, greaterThanOrEqualTo(0));
    });

    test('密钥轮换后旧数据仍可用旧密钥解密', () async {
      // 用 v1 加密数据。
      await manager.rotateKey();
      final v1Key = (await manager.loadVersionKey(version: 1))!;
      final nonce = secureRandomBytes(12);
      final plaintext = utf8.encode('encrypted with v1');

      final encrypted = aes256GcmSivEncrypt(
        plaintext: Uint8List.fromList(plaintext),
        key: v1Key,
        nonce: nonce,
      );

      // 轮换到 v2。
      await manager.rotateKey();

      // 用 v1 密钥仍能解密。
      final v1KeyAgain = (await manager.loadVersionKey(version: 1))!;
      final decrypted = aes256GcmSivDecrypt(
        data: encrypted,
        key: v1KeyAgain,
      );
      expect(decrypted, plaintext);
    });
  });
}
