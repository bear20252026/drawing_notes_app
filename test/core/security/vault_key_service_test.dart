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
      // 批次④：v2 槽位结构（slots 数组；初始化只有 PIN 槽）。
      expect(doc['v'], 2);
      expect(doc['kdf'], 'PBKDF2-HMAC-SHA256');
      expect(doc['iter'], 2000);
      final slots = (doc['slots'] as List).cast<Map<String, dynamic>>();
      expect(slots, hasLength(1));
      expect(slots.single['type'], 'pin');
      expect(slots.single.keys, containsAll(['salt', 'wrapped']));
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
      final slots = (doc['slots'] as List).cast<Map<String, dynamic>>();
      final pinSlot =
          slots.singleWhere((s) => s['type'] == 'pin');
      final wrapped = base64Decode(pinSlot['wrapped'] as String);
      wrapped[13] ^= 0xFF; // 翻转密文首字节
      pinSlot['wrapped'] = base64Encode(wrapped);
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

  group('U 盘钥匙槽位（批次④，LUKS/BitLocker 多保护器模式）', () {
    test('绑定前无槽位；绑定后 hasUsbSlot 为真且 PIN 解锁不受影响', () async {
      await service.initialize('9527');
      expect(await service.hasUsbSlot(), isFalse);

      final usbKey = VaultKeyService.randomBytes(32);
      await service.addUsbKeySlot(externalKey: usbKey);
      expect(await service.hasUsbSlot(), isTrue);

      service.lock();
      await service.unlock('9527');
      expect(service.isUnlocked, isTrue);
    });

    test('主密钥副本不出设备：保险库文件不含 U 盘钥匙明文', () async {
      await service.initialize('9527');
      final usbKey = VaultKeyService.randomBytes(32);
      await service.addUsbKeySlot(externalKey: usbKey);

      final raw = await vaultFile.readAsString();
      // 钥匙本体（base64 形态）不得出现在保险库文件里——U 盘上只有
      // 随机钥匙文件，主密钥副本不出设备。
      expect(raw.contains(base64Encode(usbKey)), isFalse);
      // 槽位结构存在。
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      final types = (doc['slots'] as List)
          .cast<Map<String, dynamic>>()
          .map((s) => s['type'])
          .toList();
      expect(types, ['pin', 'usb']);
    });

    test('忘记 PIN 全流程：旧 PIN 解不开 → U 盘重置 → 新 PIN 可用', () async {
      await service.initialize('9527');
      final mk = service.masterKey;
      final usbKey = VaultKeyService.randomBytes(32);
      await service.addUsbKeySlot(externalKey: usbKey);
      service.lock();

      // 忘了 PIN：任何错误 PIN 都解不开。
      await expectLater(
        service.unlock('0000'),
        throwsA(isA<VaultUnlockException>()),
      );

      // U 盘重置：不需要旧 PIN。
      await service.resetPinWithUsbKey(externalKey: usbKey, newPin: '666666');
      expect(service.isUnlocked, isTrue);
      expect(service.masterKey, equals(mk)); // 主密钥不变，旧密文无需迁移。

      // 新 PIN 生效，旧 PIN 失效。
      service.lock();
      await expectLater(
        service.unlock('9527'),
        throwsA(isA<VaultUnlockException>()),
      );
      await service.unlock('666666');
      expect(service.masterKey, equals(mk));
    });

    test('错误 U 盘（钥匙不匹配）重置 → fail-closed 拒绝', () async {
      await service.initialize('9527');
      await service.addUsbKeySlot(externalKey: VaultKeyService.randomBytes(32));
      service.lock();

      await expectLater(
        service.resetPinWithUsbKey(
          externalKey: VaultKeyService.randomBytes(32), // 另一把 U 盘
          newPin: '666666',
        ),
        throwsA(
          isA<VaultUnlockException>().having(
            (e) => e.reason,
            'reason',
            'U 盘恢复钥匙不匹配或已损坏',
          ),
        ),
      );
      expect(service.isUnlocked, isFalse);
    });

    test('未绑定就重置 → 明确报「未绑定 U 盘恢复钥匙」', () async {
      await service.initialize('9527');
      service.lock();
      await expectLater(
        service.resetPinWithUsbKey(
          externalKey: VaultKeyService.randomBytes(32),
          newPin: '666666',
        ),
        throwsA(
          isA<VaultUnlockException>().having(
            (e) => e.reason,
            'reason',
            '未绑定 U 盘恢复钥匙',
          ),
        ),
      );
    });

    test('changePin 保留 U 盘槽位（改 PIN 后 U 盘仍可重置）', () async {
      await service.initialize('9527');
      final usbKey = VaultKeyService.randomBytes(32);
      await service.addUsbKeySlot(externalKey: usbKey);

      await service.changePin(oldPin: '9527', newPin: '8888');
      expect(await service.hasUsbSlot(), isTrue);

      service.lock();
      await service.resetPinWithUsbKey(externalKey: usbKey, newPin: '666666');
      await service.unlock('666666');
      expect(service.isUnlocked, isTrue);
    });

    test('解除绑定后 hasUsbSlot 为假且重置报未绑定', () async {
      await service.initialize('9527');
      await service.addUsbKeySlot(externalKey: VaultKeyService.randomBytes(32));
      await service.removeUsbKeySlot();
      expect(await service.hasUsbSlot(), isFalse);
      service.lock();
      await expectLater(
        service.resetPinWithUsbKey(
          externalKey: VaultKeyService.randomBytes(32),
          newPin: '666666',
        ),
        throwsA(isA<VaultUnlockException>()),
      );
    });

    test('v1 保险库惰性迁移：首解成功后升级为 v2 槽位结构', () async {
      // 手工构造 v1 保险库（老用户升级场景）。
      final salt = VaultKeyService.randomBytes(16);
      final mk = VaultKeyService.randomBytes(32);
      final kek = await VaultKeyService.deriveKek('9527', salt, 2000);
      final wrapped = await VaultKeyService.aeadEncrypt(
        kek,
        mk,
        'drawing-notes|vault|v1'.codeUnits,
      );
      await vaultFile.writeAsString(
        jsonEncode({
          'v': 1,
          'kdf': 'PBKDF2-HMAC-SHA256',
          'iter': 2000,
          'salt': base64Encode(salt),
          'wrapped': base64Encode(wrapped),
        }),
      );

      await service.unlock('9527');
      expect(service.masterKey, equals(mk));

      // 首解后文件已升级 v2，且 PIN / 主密钥均不变。
      final doc =
          jsonDecode(await vaultFile.readAsString()) as Map<String, dynamic>;
      expect(doc['v'], 2);
      final slots = (doc['slots'] as List).cast<Map<String, dynamic>>();
      expect(slots, hasLength(1));
      expect(slots.single['type'], 'pin');

      service.lock();
      await service.unlock('9527');
      expect(service.masterKey, equals(mk));
    });
  });
}
