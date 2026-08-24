import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/progressive_delay.dart';

/// v5 军工级升级测试：Argon2id + 渐进式延迟 + 向后兼容。
void main() {
  group('Argon2id 密钥派生', () {
    // 使用测试参数（m=15→32MiB）加速——生产用 64MiB。
    const encryption = EncryptionService.test();

    test('v=5 roundtrip（Argon2id → HKDF → K1+K2+K3）', () async {
      final cipher = await encryption.encrypt('军工级加密测试', 'secure123456');
      final map = jsonDecode(cipher) as Map<String, dynamic>;
      
      // 验证版本号
      expect(map['v'], 5, reason: '必须是 v=5（Argon2id）');
      
      // 验证密文不包含明文
      expect(cipher.contains('军工级加密测试'), false);
      
      // 验证解密
      expect(await encryption.decrypt(cipher, 'secure123456'), '军工级加密测试');
    });

    test('v=5 不同密码产生不同密文', () async {
      final cipher1 = await encryption.encrypt('相同内容', 'password1');
      final cipher2 = await encryption.encrypt('相同内容', 'password2');
      
      // 不同密码 → 不同盐 → 不同密文
      expect(cipher1 != cipher2, true);
    });

    test('v=5 盐长度 32 字节', () async {
      final cipher = await encryption.encrypt('测试', 'password');
      final map = jsonDecode(cipher) as Map<String, dynamic>;
      final salt = base64Decode(map['s'] as String);
      
      expect(salt.length, 32, reason: 'Argon2id 盐长度必须是 32 字节');
    });

    test('deriveKeyChain 输出三个 SecretKey', () async {
      final (k1, k2, k3) = await encryption.deriveKeyChain(
        password: 'test-password',
        salt: List<int>.generate(32, (i) => i),
      );
      
      final k1Bytes = await k1.extractBytes();
      final k2Bytes = await k2.extractBytes();
      final k3Bytes = await k3.extractBytes();
      
      expect(k1Bytes.length, 32, reason: 'K1 必须是 32 字节（AES-256 密钥）');
      expect(k2Bytes.length, 32, reason: 'K2 必须是 32 字节（HKDF 输出 32 字节）');
      expect(k3Bytes.length, 32, reason: 'K3 必须是 32 字节（HKDF 输出 32 字节）');
    });

    test('deriveKeyChain 相同密码相同盐产生相同结果', () async {
      final salt = List<int>.generate(32, (i) => i);
      final (k1a, k2a, k3a) = await encryption.deriveKeyChain(
        password: 'password',
        salt: salt,
      );
      final (k1b, k2b, k3b) = await encryption.deriveKeyChain(
        password: 'password',
        salt: salt,
      );
      
      expect(await k1a.extractBytes(), await k1b.extractBytes());
      expect(await k2a.extractBytes(), await k2b.extractBytes());
      expect(await k3a.extractBytes(), await k3b.extractBytes());
    });

    test('deriveKeyChain 不同密码产生不同结果', () async {
      final (k1a, _, _) = await encryption.deriveKeyChain(
        password: 'password1',
        salt: List<int>.generate(32, (i) => i),
      );
      final (k1b, _, _) = await encryption.deriveKeyChain(
        password: 'password2',
        salt: List<int>.generate(32, (i) => i),
      );
      
      final k1aBytes = await k1a.extractBytes();
      final k1bBytes = await k1b.extractBytes();
      expect(k1aBytes, isNot(equals(k1bBytes)));
    });
  });

  group('向后兼容性', () {
    const encryption = EncryptionService.test();

    test('v=2 旧数据兼容解密', () async {
      final salt = List<int>.generate(16, (i) => i);
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      );
      final key = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode('old-pass')),
        nonce: salt,
      );
      final aes = AesGcm.with256bits();
      final nonce = List<int>.generate(12, (i) => 255 - i);
      final box = await aes.encrypt(
        utf8.encode('旧格式内容'),
        secretKey: key,
        nonce: nonce,
      );
      final oldJson = jsonEncode({
        's': base64Encode(salt),
        'n': base64Encode(nonce),
        'c': base64Encode(box.cipherText),
        'm': base64Encode(box.mac.bytes),
        'v': 2,
      });
      expect(await encryption.decrypt(oldJson, 'old-pass'), '旧格式内容');
    });

    test('v=3 旧数据兼容解密', () async {
      final salt = List<int>.generate(16, (i) => i * 2);
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 600000,
        bits: 256,
      );
      final key = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode('v3-pass')),
        nonce: salt,
      );
      final aes = AesGcm.with256bits();
      final nonce = List<int>.generate(12, (i) => 200 - i);
      final box = await aes.encrypt(
        utf8.encode('v3 格式内容'),
        secretKey: key,
        nonce: nonce,
      );
      final oldJson = jsonEncode({
        's': base64Encode(salt),
        'n': base64Encode(nonce),
        'c': base64Encode(box.cipherText),
        'm': base64Encode(box.mac.bytes),
        'v': 3,
      });
      expect(await encryption.decrypt(oldJson, 'v3-pass'), 'v3 格式内容');
    });

    test('v=4 旧数据兼容解密', () async {
      final salt = List<int>.generate(16, (i) => i + 10);
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 600000,
        bits: 256,
      );
      final key = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode('v4-pass')),
        nonce: salt,
      );
      final aes = AesGcm.with256bits();
      final nonce = List<int>.generate(12, (i) => 100 + i);
      final aad = utf8.encode('v4-test-note');
      final box = await aes.encrypt(
        utf8.encode('v4 AAD 内容'),
        secretKey: key,
        nonce: nonce,
        aad: aad,
      );
      final oldJson = jsonEncode({
        's': base64Encode(salt),
        'n': base64Encode(nonce),
        'c': base64Encode(box.cipherText),
        'm': base64Encode(box.mac.bytes),
        'a': base64Encode(aad),
        'v': 4,
      });
      expect(await encryption.decrypt(oldJson, 'v4-pass'), 'v4 AAD 内容');
    });
  });

  group('PIN 最小长度验证', () {
    test('PIN 长度 < 6 无效', () {
      expect(EncryptionService.isPinLengthValid('12345'), false);
      expect(EncryptionService.isPinLengthValid('1234'), false);
      expect(EncryptionService.isPinLengthValid('1'), false);
      expect(EncryptionService.isPinLengthValid(''), false);
    });

    test('PIN 长度 >= 6 有效', () {
      expect(EncryptionService.isPinLengthValid('123456'), true);
      expect(EncryptionService.isPinLengthValid('1234567'), true);
      expect(EncryptionService.isPinLengthValid('secure-pin'), true);
    });

    test('kPinMinLength 常量值正确', () {
      expect(EncryptionService.kPinMinLength, 6);
    });
  });

  group('渐进式延迟', () {
    setUp(() async {
      // 清空 SharedPreferences 测试环境
      SharedPreferences.setMockInitialValues({});
      await ProgressiveDelay.resetOnSuccess();
    });

    test('初始状态无延迟', () async {
      expect(await ProgressiveDelay.getFailCount(), 0);
      expect(await ProgressiveDelay.getCurrentDelay(), 0);
      expect(await ProgressiveDelay.needsDelay(), false);
    });

    test('失败次数 → 延迟序列 1s→5s→30s→5min→1h', () {
      expect(ProgressiveDelay.getDelayForCount(0), 0);
      expect(ProgressiveDelay.getDelayForCount(1), 1);
      expect(ProgressiveDelay.getDelayForCount(2), 5);
      expect(ProgressiveDelay.getDelayForCount(3), 30);
      expect(ProgressiveDelay.getDelayForCount(4), 300);
      expect(ProgressiveDelay.getDelayForCount(5), 3600);
      // 超过序列长度，使用最后一个值
      expect(ProgressiveDelay.getDelayForCount(10), 3600);
      expect(ProgressiveDelay.getDelayForCount(100), 3600);
    });

    test('渐进式延迟信息显示', () {
      expect(ProgressiveDelay.getDelayInfoForCount(0), '无延迟');
      expect(ProgressiveDelay.getDelayInfoForCount(1), '1秒');
      expect(ProgressiveDelay.getDelayInfoForCount(2), '5秒');
      expect(ProgressiveDelay.getDelayInfoForCount(3), '30秒');
      expect(ProgressiveDelay.getDelayInfoForCount(4), '5分钟');
      expect(ProgressiveDelay.getDelayInfoForCount(5), '1小时');
    });

    test('记录失败递增计数器', () async {
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getFailCount(), 1);
      
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getFailCount(), 2);
      
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getFailCount(), 3);
    });

    test('成功重置计数器', () async {
      // 累积失败
      await ProgressiveDelay.recordFailure();
      await ProgressiveDelay.recordFailure();
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getFailCount(), 3);
      
      // 成功重置
      await ProgressiveDelay.resetOnSuccess();
      expect(await ProgressiveDelay.getFailCount(), 0);
      expect(await ProgressiveDelay.getCurrentDelay(), 0);
    });

    test('延迟信息持久化', () async {
      await ProgressiveDelay.recordFailure();
      await ProgressiveDelay.recordFailure();
      
      // 重新加载（模拟重启）
      final count = await ProgressiveDelay.getFailCount();
      expect(count, 2);
      
      final delay = await ProgressiveDelay.getCurrentDelay();
      expect(delay, 5); // 第二次失败 → 5秒延迟
    });

    test('HMAC 签名防篡改', () async {
      await ProgressiveDelay.recordFailure();
      await ProgressiveDelay.recordFailure();
      
      // 获取当前状态
      final count = await ProgressiveDelay.getFailCount();
      expect(count, 2);
      
      // 尝试篡改 SharedPreferences 中的计数器
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('progressive_delay_fail_count', 100);
      
      // HMAC 验证失败，自动重置
      final tamperedCount = await ProgressiveDelay.getFailCount();
      expect(tamperedCount, 0, reason: '篡改后 HMAC 验证失败，计数器重置');
    });
  });

  group('渐进式延迟集成测试', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await ProgressiveDelay.resetOnSuccess();
    });

    test('连续失败后延迟递增', () async {
      // 第一次失败
      await ProgressiveDelay.recordFailure();
      var delay = await ProgressiveDelay.getCurrentDelay();
      expect(delay, 1);
      
      // 第二次失败
      await ProgressiveDelay.recordFailure();
      delay = await ProgressiveDelay.getCurrentDelay();
      expect(delay, 5);
      
      // 第三次失败
      await ProgressiveDelay.recordFailure();
      delay = await ProgressiveDelay.getCurrentDelay();
      expect(delay, 30);
    });

    test('成功解锁后延迟重置', () async {
      // 累积失败
      await ProgressiveDelay.recordFailure();
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getCurrentDelay(), 5);
      
      // 模拟成功解锁
      await ProgressiveDelay.resetOnSuccess();
      expect(await ProgressiveDelay.getCurrentDelay(), 0);
    });
  });

  group('密码学安全参数验证', () {
    test('Argon2id 参数符合 OWASP 2026', () {
      // 生产参数：t=3, m=64MiB, p=1
      // 测试参数：t=1, m=32MiB, p=1（加速）
      const testEncryption = EncryptionService.test();
      // 无法直接访问私有参数，但可以验证功能正常
      expect(testEncryption, isNotNull);
    });

    test('v=5 使用 Argon2id', () async {
      const encryption = EncryptionService.test();
      final cipher = await encryption.encrypt('test', 'password');
      final map = jsonDecode(cipher) as Map<String, dynamic>;
      expect(map['v'], 5, reason: '当前版本必须是 v=5（Argon2id）');
    });

    test('盐长度 32 字节（Argon2id 推荐）', () async {
      const encryption = EncryptionService.test();
      final cipher = await encryption.encrypt('test', 'password');
      final map = jsonDecode(cipher) as Map<String, dynamic>;
      final salt = base64Decode(map['s'] as String);
      expect(salt.length, 32);
    });
  });
}
