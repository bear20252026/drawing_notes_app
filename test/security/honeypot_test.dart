// honeypot_test.dart — 蜜罐密钥部署单元测试。
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/honeypot.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 简易内存 VaultKeyStore 用于测试。
class _MockVaultKeyStore implements VaultKeyStore {
  final Map<String, Uint8List> _store = {};

  @override
  Future<void> storeKey(String keyId, List<int> data) async {
    _store[keyId] = Uint8List.fromList(data);
  }

  @override
  Future<Uint8List?> readKey(String keyId) async {
    return _store[keyId];
  }

  @override
  Future<void> deleteKey(String keyId) async {
    _store.remove(keyId);
  }
}

void main() {
  group('HoneypotService', () {
    late _MockVaultKeyStore store;
    late HoneypotService service;

    setUp(() {
      store = _MockVaultKeyStore();
      service = HoneypotService(
        vaultStore: store,
        config: const HoneypotConfig(decoyKeyCount: 2),
      );
    });

    test('deploy 创建正确数量的假密钥', () async {
      await service.deploy();

      // 每个 decoy 生成 1 DEK + 1 SK + 1 PK = 3 个密钥
      expect(service.deployedIds.length, 6);
      expect(store._store.length, 6);

      // 验证 ID 命名规则。
      expect(service.deployedIds[0], 'honeypot.dek.0');
      expect(service.deployedIds[1], 'honeypot.signing.0.sk');
      expect(service.deployedIds[2], 'honeypot.signing.0.pk');
      expect(service.deployedIds[3], 'honeypot.dek.1');
      expect(service.deployedIds[4], 'honeypot.signing.1.sk');
      expect(service.deployedIds[5], 'honeypot.signing.1.pk');
    });

    test('isHoneypotKey 正确识别蜜罐密钥', () async {
      expect(service.isHoneypotKey('honeypot.dek.0'), true);
      expect(service.isHoneypotKey('honeypot.signing.0.sk'), true);
      expect(service.isHoneypotKey('dek.primary'), false);
      expect(service.isHoneypotKey('signing.primary.sk'), false);
    });

    test('readKey 触发蜜罐记录', () async {
      await service.deploy();

      // 读取蜜罐密钥。
      final data = await service.readKey('honeypot.dek.0');
      expect(data, isNotNull);
      expect(service.triggerCount, 1);

      // 再次读取。
      await service.readKey('honeypot.signing.0.sk');
      expect(service.triggerCount, 2);
    });

    test('readKey 读取真实密钥不触发', () async {
      await service.deploy();

      // 写入一个真实密钥。
      await store.storeKey('dek.primary', Uint8List(32));

      await service.readKey('dek.primary');
      expect(service.triggerCount, 0);
    });

    test('onTrigger 记录审计日志', () async {
      await service.deploy();

      service.onTrigger(
        keyId: 'honeypot.dek.0',
        operation: 'read',
        source: 'test',
      );

      expect(service.triggerCount, 1);
    });

    test('verifyIntegrity 检测完整性', () async {
      await service.deploy();

      final result = await service.verifyIntegrity();
      expect(result.intact, true);
      expect(result.checkedKeys, 6);
      expect(result.issues, isEmpty);
    });

    test('verifyIntegrity 检测缺失密钥', () async {
      await service.deploy();

      // 模拟攻击者删除了一个蜜罐密钥。
      await store.deleteKey('honeypot.dek.0');

      final result = await service.verifyIntegrity();
      expect(result.intact, false);
      expect(result.issues.length, 1);
      expect(result.issues[0], contains('honeypot.dek.0'));
    });

    test('假 DEK 大小正确', () async {
      await service.deploy();

      final dek = await store.readKey('honeypot.dek.0');
      expect(dek, isNotNull);
      expect(dek!.length, 32);
    });

    test('假签名公钥大小正确', () async {
      await service.deploy();

      final pk = await store.readKey('honeypot.signing.0.pk');
      expect(pk, isNotNull);
      // Ed25519 公钥 32 字节。
      expect(pk!.length, 32);
    });
  });
}
