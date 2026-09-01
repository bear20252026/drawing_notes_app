import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/vault_key_service.dart';

void main() {
  late Directory tmp;
  late File vaultFile;
  late VaultKeyService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vault_test_');
    vaultFile = File('${tmp.path}${Platform.pathSeparator}vault.key.json');
    service = VaultKeyService(
      vaultFileResolver: () async => vaultFile,
      iterations: 2000, // 测试提速（生产 600k 与 MediaCryptoService 对齐）
    );
  });

  tearDown(() async {
    service.lock();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('初始化与解锁', () {
    test('未配置 → isConfigured false；initialize 后 true', () async {
      expect(await service.isConfigured(), isFalse);
      await service.initialize('9527');
      expect(await service.isConfigured(), isTrue);
    });

    test('initialize 后主密钥在内存（32 字节）', () async {
      await service.initialize('9527');
      expect(service.isUnlocked, isTrue);
      expect(service.masterKey.length, 32);
    });

    test('正确 PIN 解锁成功；错误 PIN 抛 VaultUnlockException', () async {
      await service.initialize('9527');
      service.lock();

      await service.unlock('9527');
      expect(service.isUnlocked, isTrue);

      service.lock();
      await expectLater(
        service.unlock('0000'),
        throwsA(isA<VaultUnlockException>()),
      );
      expect(service.isUnlocked, isFalse);
    });

    test('持久化正确：新实例（同文件路径）解锁得到同一主密钥', () async {
      await service.initialize('9527');
      final mk1 = service.masterKey;
      service.lock();

      final service2 = VaultKeyService(
        vaultFileResolver: () async => vaultFile,
        iterations: 2000,
      );
      await service2.unlock('9527');
      expect(service2.masterKey, equals(mk1));
    });

    test('保险库文件不含 PIN 明文（fail-closed 底线）', () async {
      await service.initialize('952700');
      final raw = await vaultFile.readAsString();
      expect(raw.contains('952700'), isFalse);
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      expect(doc['v'], 1);
      expect(doc['kdf'], 'PBKDF2-HMAC-SHA256');
      expect(doc['iter'], 2000);
      expect(doc.keys, containsAll(['salt', 'wrapped']));
    });

    test('空 PIN 拒绝', () {
      expect(() => service.initialize(''), throwsArgumentError);
    });
  });

  group('改 PIN 与锁定', () {
    test('changePin 后旧 PIN 失效、新 PIN 可用、主密钥不变', () async {
      await service.initialize('9527');
      final mk = service.masterKey;

      await service.changePin(oldPin: '9527', newPin: '8888');
      expect(service.masterKey, equals(mk));

      service.lock();
      await expectLater(
        service.unlock('9527'),
        throwsA(isA<VaultUnlockException>()),
      );
      await service.unlock('8888');
      expect(service.masterKey, equals(mk));
    });

    test('旧 PIN 错误时 changePin 拒绝且原保险库不受影响', () async {
      await service.initialize('9527');
      await expectLater(
        service.changePin(oldPin: '1111', newPin: '8888'),
        throwsA(isA<VaultUnlockException>()),
      );
      // 原密码仍可解锁（换盐写入未发生）。
      await service.unlock('9527');
      expect(service.isUnlocked, isTrue);
    });

    test('lock() 清内存：isUnlocked false，masterKey 抛错', () async {
      await service.initialize('9527');
      service.lock();
      expect(service.isUnlocked, isFalse);
      expect(() => service.masterKey, throwsStateError);
    });

    test('wipe() 删除保险库文件并清内存', () async {
      await service.initialize('9527');
      await service.wipe();
      expect(await service.isConfigured(), isFalse);
      expect(service.isUnlocked, isFalse);
    });
  });

  group('篡改防护（fail-closed）', () {
    test('wrapped 载荷被篡改 → 解锁拒绝', () async {
      await service.initialize('9527');
      service.lock();

      final doc =
          jsonDecode(await vaultFile.readAsString()) as Map<String, dynamic>;
      final wrapped = base64Decode(doc['wrapped'] as String);
      wrapped[13] ^= 0xFF; // 翻转密文首字节
      doc['wrapped'] = base64Encode(wrapped);
      await vaultFile.writeAsString(jsonEncode(doc));

      await expectLater(
        service.unlock('9527'),
        throwsA(isA<VaultUnlockException>()),
      );
      expect(service.isUnlocked, isFalse);
    });

    test('JSON 损坏 → 解锁拒绝', () async {
      await service.initialize('9527');
      service.lock();
      await vaultFile.writeAsString('{corrupt');
      await expectLater(
        service.unlock('9527'),
        throwsA(isA<VaultUnlockException>()),
      );
    });
  });

  group('U 盘第二副本（重置通道核心）', () {
    test('export/import 往返恢复主密钥', () async {
      await service.initialize('9527');
      final mk = service.masterKey;

      final usbKey = VaultKeyService.randomBytes(32);
      final copy = await VaultKeyService.exportSecondCopy(
        masterKey: mk,
        externalKey: usbKey,
      );
      final restored = await VaultKeyService.importSecondCopy(
        secondCopy: copy,
        externalKey: usbKey,
      );
      expect(restored, equals(mk));
    });

    test('错误外部密钥解包失败（U 盘不匹配）', () async {
      final mk = VaultKeyService.randomBytes(32);
      final copy = await VaultKeyService.exportSecondCopy(
        masterKey: mk,
        externalKey: VaultKeyService.randomBytes(32),
      );
      await expectLater(
        VaultKeyService.importSecondCopy(
          secondCopy: copy,
          externalKey: VaultKeyService.randomBytes(32),
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('AEAD 单一来源', () {
    test('加解密往返；载荷被篡改时 tag 校验失败', () async {
      final key = VaultKeyService.randomBytes(32);
      final aad = 'drawing-notes|vault|v1'.codeUnits;
      final plain = utf8.encode('绝密笔记内容');
      final payload = await VaultKeyService.aeadEncrypt(key, plain, aad);

      expect(
        await VaultKeyService.aeadDecrypt(key, payload, aad),
        equals(plain),
      );

      payload[20] ^= 0xFF;
      await expectLater(
        VaultKeyService.aeadDecrypt(key, payload, aad),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('AAD 不匹配 → tag 校验失败（防跨用途密文交换）', () async {
      final key = VaultKeyService.randomBytes(32);
      final payload = await VaultKeyService.aeadEncrypt(
        key,
        utf8.encode('x'),
        'purpose-a'.codeUnits,
      );
      await expectLater(
        VaultKeyService.aeadDecrypt(key, payload, 'purpose-b'.codeUnits),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
