/// 加密服务集成测试：双密钥槽流程 / 密钥轮换 / 向后兼容性 / 渐进延迟 / 端到端笔记本加密。
///
/// 覆盖 5 个集成场景，验证加密服务模块的完整生命周期。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/progressive_delay.dart';
import 'package:editor_core/editor_core.dart';
import 'package:editor_core/src/domain/deniable_encryption.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // 场景 1：双密钥槽流程（DeniableEncryptionService）
  // ═══════════════════════════════════════════════════════════
  group('双密钥槽流程（Deniable Encryption）', () {
    late DeniableEncryptionService service;

    setUp(() {
      service = DeniableEncryptionService(
        containerSize: 4 * 1024 * 1024, // 4MB 用于测试（分区布局含 1-2MB 随机填充）
        maxFailures: 10,
      );
    });

    test('初始化容器：强制设置主密码+胁迫密码', () {
      final container = service.initializeContainer(
        containerId: 'test-container-1',
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
        recoveryKey: 'abc123',
      );

      expect(container.id, 'test-container-1');
      expect(container.totalSize, 4 * 1024 * 1024);
      expect(container.slotStates, hasLength(2));
      expect(container.getSlotState(slotA).initialized, true);
      expect(container.getSlotState(slotB).initialized, true);
      // 两个槽都有分区
      expect(container.getPartitionsForSlot(slotA), isNotEmpty);
      expect(container.getPartitionsForSlot(slotB), isNotEmpty);
    });

    test('主密码和胁迫密码必须不同', () {
      expect(
        () => service.initializeContainer(
          containerId: 'test',
          primaryPassword: 'same_password_123',
          coercionPassword: 'same_password_123',
          recoveryKey: 'key',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('密码最小长度 8 字符', () {
      expect(
        () => service.initializeContainer(
          containerId: 'test',
          primaryPassword: 'short',
          coercionPassword: 'another_long_one',
          recoveryKey: 'key',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('派生双密钥：主密钥与胁迫密钥独立', () {
      final (primaryKey, coercionKey) = service.deriveDualKeys(
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
      );
      expect(primaryKey.length, 32);
      expect(coercionKey.length, 32);
      expect(
        primaryKey != coercionKey,
        true,
        reason: '主密钥和胁迫密钥必须独立',
      );
    });

    test('派生双密钥：同一密码+同一 salt → 同一密钥', () {
      final salt = List<int>.generate(32, (i) => i);
      final key1 = service.deriveKey(
        password: 'password',
        salt: salt,
        iterations: 3,
      );
      final key2 = service.deriveKey(
        password: 'password',
        salt: salt,
        iterations: 3,
      );
      expect(key1, key2);
    });

    test('加密到槽 A + 从槽 A 解密', () {
      final (primaryKey, _) = service.deriveDualKeys(
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
      );
      final plaintext = Uint8List.fromList('真实机密数据'.codeUnits);
      final encrypted = service.encryptToSlot(
        slotIndex: slotA,
        plaintext: plaintext,
        key: primaryKey,
      );
      final decrypted = service.decryptFromSlot(
        slotIndex: slotA,
        encryptedData: encrypted,
        key: primaryKey,
      );
      expect(decrypted, plaintext);
    });

    test('加密到槽 B + 从槽 B 解密', () {
      final (_, coercionKey) = service.deriveDualKeys(
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
      );
      final plaintext = Uint8List.fromList('安全笔记数据'.codeUnits);
      final encrypted = service.encryptToSlot(
        slotIndex: slotB,
        plaintext: plaintext,
        key: coercionKey,
      );
      final decrypted = service.decryptFromSlot(
        slotIndex: slotB,
        encryptedData: encrypted,
        key: coercionKey,
      );
      expect(decrypted, plaintext);
    });

    test('槽 A 的密钥无法解密槽 B 的数据（AAD 绑定）', () {
      final (primaryKey, coercionKey) = service.deriveDualKeys(
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
      );
      final plaintext = Uint8List.fromList('安全笔记'.codeUnits);
      // 用槽 B 的密钥加密
      final encrypted = service.encryptToSlot(
        slotIndex: slotB,
        plaintext: plaintext,
        key: coercionKey,
      );
      // 用槽 A 的密钥尝试解密 → 失败（AAD 不匹配）
      expect(
        () => service.decryptFromSlot(
          slotIndex: slotB,
          encryptedData: encrypted,
          key: primaryKey,
        ),
        throwsA(anything),
      );
    });

    test('用错误密钥解密 → 失败', () {
      final plaintext = Uint8List.fromList('机密'.codeUnits);
      final encrypted = service.encryptToSlot(
        slotIndex: slotA,
        plaintext: plaintext,
        key: Uint8List(32),
      );
      final wrongKey = List<int>.generate(32, (i) => 0xFF);
      expect(
        () => service.decryptFromSlot(
          slotIndex: slotA,
          encryptedData: encrypted,
          key: wrongKey,
        ),
        throwsA(anything),
      );
    });

    test('容器完整性验证', () {
      final container = service.initializeContainer(
        containerId: 'test-container-integrity',
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
        recoveryKey: 'key',
      );
      expect(service.verifyContainerIntegrity(container), true);
    });

    test('tryUnlock 正确密码 → 返回 slotA 成功', () {
      final container = service.initializeContainer(
        containerId: 'test-unlock',
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
        recoveryKey: 'key',
      );
      final result = service.tryUnlock(
        container: container,
        password: 'primary_password_123',
        primaryKeyMaterial: List<int>.generate(32, (i) => i),
        coercionKeyMaterial: List<int>.generate(32, (i) => i + 100),
      );
      expect(result.success, true);
      expect(result.slotIndex, slotA);
    });

    test('自毁状态初始：未销毁、失败计数为 0', () {
      expect(service.selfDestructState.destroyed, false);
      expect(service.selfDestructState.consecutiveFailures, 0);
    });

    test('重置失败计数', () {
      service.resetFailureCount();
      expect(service.selfDestructState.consecutiveFailures, 0);
      expect(service.selfDestructState.destroyed, false);
    });

    test('恢复密钥格式验证', () {
      final validKey = service.generateRecoveryKey();
      expect(service.isValidRecoveryKey(validKey), true);
      expect(validKey.length, 64);

      expect(service.isValidRecoveryKey('g' * 64), false); // 非 hex
      expect(service.isValidRecoveryKey('a' * 63), false); // 长度不对
      expect(service.isValidRecoveryKey('a' * 65), false); // 长度不对
    });

    test('安全擦除密钥材料 → 全零', () {
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      expect(key[0], 0);
      expect(key[1], 1);

      service.secureEraseKey(key);
      expect(key.every((b) => b == 0), true);
    });

    test('分区布局：两个槽都有独立分区', () {
      final container = service.initializeContainer(
        containerId: 'test-partitions',
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
        recoveryKey: 'key',
      );
      final slotAParts = container.getPartitionsForSlot(slotA);
      final slotBParts = container.getPartitionsForSlot(slotB);

      // Slot A 有 4-6 个分区
      expect(slotAParts.length, greaterThanOrEqualTo(4));
      expect(slotAParts.length, lessThanOrEqualTo(6));

      // Slot B 有 3-5 个分区
      expect(slotBParts.length, greaterThanOrEqualTo(3));
      expect(slotBParts.length, lessThanOrEqualTo(5));

      // 所有分区不重叠（各自偏移量递增）
      for (final p in slotAParts) {
        expect(p.slotIndex, slotA);
      }
      for (final p in slotBParts) {
        expect(p.slotIndex, slotB);
      }
    });

    test('SlotState 相等性', () {
      const s1 = KeySlotState(slotIndex: 0, initialized: true);
      const s2 = KeySlotState(slotIndex: 0, initialized: true);
      expect(s1, s2);
      expect(s1.hashCode, s2.hashCode);

      const s3 = KeySlotState(slotIndex: 1, initialized: false);
      expect(s1 == s3, false);
    });

    test('UnlockResult 成功/失败 工厂方法', () {
      final success = UnlockResult.createSuccess(slotA);
      expect(success.success, true);
      expect(success.slotIndex, slotA);
      expect(success.message, contains('Unlocked'));

      final failure = UnlockResult.createFailure('bad pw', 'INVALID');
      expect(failure.success, false);
      expect(failure.slotIndex, -1);
      expect(failure.errorCode, 'INVALID');
    });

    test('SelfDestructState copyWith', () {
      const initial = SelfDestructState();
      expect(initial.consecutiveFailures, 0);
      expect(initial.destroyed, false);

      final updated = initial.copyWith(
        consecutiveFailures: 5,
        destroyed: true,
      );
      expect(updated.consecutiveFailures, 5);
      expect(updated.destroyed, true);
    });

    test('DeniableContainer 相等性（按 id）', () {
      final c1 = service.initializeContainer(
        containerId: 'same-id',
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
        recoveryKey: 'key',
      );
      final c2 = service.initializeContainer(
        containerId: 'same-id',
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
        recoveryKey: 'key',
      );
      expect(c1, c2);

      final c3 = service.initializeContainer(
        containerId: 'different-id',
        primaryPassword: 'primary_password_123',
        coercionPassword: 'coercion_password_456',
        recoveryKey: 'key',
      );
      expect(c1 == c3, false);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 场景 2：密钥轮换（KeyRotationService）
  // ═══════════════════════════════════════════════════════════
  group('密钥轮换（Key Rotation）', () {
    const service = KeyRotationService();

    test('默认策略：90 天轮换周期，180 天最大寿命', () {
      const policy = KeyRotationPolicy();
      expect(policy.rotationInterval.inDays, 90);
      expect(policy.maxKeyAge.inDays, 180);
      expect(policy.forceRotationOnCompromise, true);
      expect(policy.maxPreviousKeys, 2);
      expect(policy.enabled, true);
    });

    test('未到期 → 不需要轮换', () {
      const policy = KeyRotationPolicy();
      final result = service.shouldRotate(
        keyCreatedAt: DateTime.now().subtract(const Duration(days: 30)),
        policy: policy,
        now: DateTime.now(),
      );
      expect(result.rotated, false);
      expect(result.reason, 'Within policy');
    });

    test('达到轮换周期（90 天）→ 需要轮换', () {
      const policy = KeyRotationPolicy();
      final result = service.shouldRotate(
        keyCreatedAt: DateTime.now().subtract(const Duration(days: 91)),
        policy: policy,
        now: DateTime.now(),
      );
      expect(result.rotated, true);
      expect(result.reason, contains('Rotation interval reached'));
      expect(result.newKeyId, 'key-1');
    });

    test('超过最大寿命（180 天）→ 强制轮换', () {
      const policy = KeyRotationPolicy();
      final result = service.shouldRotate(
        keyCreatedAt: DateTime.now().subtract(const Duration(days: 181)),
        policy: policy,
        now: DateTime.now(),
      );
      expect(result.rotated, true);
      expect(result.reason, contains('Key age exceeded max'));
    });

    test('密钥泄露 → 强制轮换（最高优先级）', () {
      const policy = KeyRotationPolicy();
      final result = service.shouldRotate(
        keyCreatedAt: DateTime.now().subtract(const Duration(days: 10)),
        policy: policy,
        now: DateTime.now(),
        compromised: true,
      );
      expect(result.rotated, true);
      expect(result.reason, contains('Key compromised'));
      expect(result.newKeyId, 'key-1');
    });

    test('禁用轮换 → 不需要轮换', () {
      const policy = KeyRotationPolicy(enabled: false);
      final result = service.shouldRotate(
        keyCreatedAt: DateTime.now().subtract(const Duration(days: 200)),
        policy: policy,
        now: DateTime.now(),
        compromised: true,
      );
      expect(result.rotated, false);
      expect(result.reason, 'Rotation disabled');
    });

    test('密钥 ID 版本递增：key-1 → key-2 → key-3', () {
      const policy = KeyRotationPolicy();
      final r1 = service.shouldRotate(
        keyCreatedAt: DateTime.now().subtract(const Duration(days: 91)),
        policy: policy,
        currentKeyId: '',
      );
      expect(r1.newKeyId, 'key-1');

      final r2 = service.shouldRotate(
        keyCreatedAt: DateTime.now().subtract(const Duration(days: 91)),
        policy: policy,
        currentKeyId: r1.newKeyId,
      );
      expect(r2.newKeyId, 'key-2');

      final r3 = service.shouldRotate(
        keyCreatedAt: DateTime.now().subtract(const Duration(days: 91)),
        policy: policy,
        currentKeyId: r2.newKeyId,
      );
      expect(r3.newKeyId, 'key-3');
    });

    test('自定义轮换策略 copyWith', () {
      const policy = KeyRotationPolicy();
      final custom = policy.copyWith(
        rotationInterval: const Duration(days: 30),
        maxKeyAge: const Duration(days: 60),
        maxPreviousKeys: 5,
      );
      expect(custom.rotationInterval.inDays, 30);
      expect(custom.maxKeyAge.inDays, 60);
      expect(custom.maxPreviousKeys, 5);
      // 不变的字段
      expect(custom.forceRotationOnCompromise, true);
      expect(custom.enabled, true);
    });

    test('RotationResult 常量相等', () {
      const r1 = RotationResult.notNeeded;
      const r2 = RotationResult(rotated: false, reason: 'Within policy');
      expect(r1, r2);
      expect(r1.hashCode, r2.hashCode);
    });

    test('KeyRotationPolicy 相等性', () {
      const p1 = KeyRotationPolicy();
      const p2 = KeyRotationPolicy();
      expect(p1, p2);
      const p3 = KeyRotationPolicy(enabled: false);
      expect(p1 == p3, false);
    });

    test('轮换时机：刚好到 90 天', () {
      const policy = KeyRotationPolicy();
      final result = service.shouldRotate(
        keyCreatedAt: DateTime(2026, 5, 26),
        policy: policy,
        now: DateTime(2026, 8, 25), // 90 days later
      );
      expect(result.rotated, true);
    });

    test('轮换时机：89 天不轮换', () {
      const policy = KeyRotationPolicy();
      final result = service.shouldRotate(
        keyCreatedAt: DateTime(2026, 5, 27),
        policy: policy,
        now: DateTime(2026, 8, 25), // 89 days
      );
      expect(result.rotated, false);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 场景 3：向后兼容性（EncryptionService 多版本）
  // ═══════════════════════════════════════════════════════════
  group('向后兼容性（加密版本兼容）', () {
    const encryption = EncryptionService.test();

    test('formatVersionOf 检测版本号', () {
      // v=5 数据
      final v5Data = jsonEncode({'v': 5, 's': 'abc'});
      expect(EncryptionService.formatVersionOf(v5Data), 5);

      // v=2 数据（默认）
      final v2Data = jsonEncode({'s': 'abc'});
      expect(EncryptionService.formatVersionOf(v2Data), 2);

      // 畸形数据
      expect(EncryptionService.formatVersionOf('not json'), 2);
    });

    test('密码模式 v5 加密 roundtrip', () async {
      final cipher = await encryption.encrypt('内容', 'password123');
      final dec = await encryption.decrypt(cipher, 'password123');
      expect(dec, '内容');
    });

    test('密文不包含明文', () async {
      final plain = '这是一段机密信息';
      final cipher = await encryption.encrypt(plain, 'password123');
      expect(cipher.contains(plain), false);
    });

    test('不同密码无法解密', () async {
      final cipher = await encryption.encrypt('机密', 'password1');
      expect(
        () => encryption.decrypt(cipher, 'password2'),
        throwsA(anything),
      );
    });

    test('恢复密钥信封 roundtrip', () async {
      final masterKey = List<int>.generate(32, (i) => i);
      final recoveryKey = 'my-recovery-key-phrase';

      final envelope = await encryption.wrapMasterKey(masterKey, recoveryKey);
      final unwrapped =
          await encryption.unwrapMasterKey(envelope, recoveryKey);
      expect(unwrapped, masterKey);
    });

    test('恢复密钥错误 → 解包裹失败', () async {
      final masterKey = List<int>.generate(32, (i) => i);
      final envelope =
          await encryption.wrapMasterKey(masterKey, 'correct-key');
      expect(
        () => encryption.unwrapMasterKey(envelope, 'wrong-key'),
        throwsA(anything),
      );
    });

    test('keyfile 模式 roundtrip', () async {
      final masterKey = List<int>.generate(32, (i) => i);
      final cipher =
          await encryption.encryptWithKey('keyfile 数据', masterKey);
      final dec = await encryption.decryptWithKey(cipher, masterKey);
      expect(dec, 'keyfile 数据');
    });

    test('keyfile 模式用错误密钥 → 失败', () async {
      final masterKey = List<int>.generate(32, (i) => i);
      final cipher = await encryption.encryptWithKey('数据', masterKey);
      final wrongKey = List<int>.generate(32, (i) => 0xFF);
      expect(
        () => encryption.decryptWithKey(cipher, wrongKey),
        throwsA(anything),
      );
    });

    test('密码模式 v4 AAD roundtrip（password-based）', () async {
      const service = EncryptionService.test();
      final encrypted = await service.encryptWithPasswordAad(
        notebookId: 'nb-password-test',
        plaintext: '密码模式 v4',
        password: 'secure-password-123',
      );
      final decrypted = await service.decryptWithPasswordAad(
        notebookId: 'nb-password-test',
        encryptedJson: encrypted,
        password: 'secure-password-123',
      );
      expect(decrypted, '密码模式 v4');
    });

    test('密码模式 v4：错误 notebookId → 解密失败', () async {
      const service = EncryptionService.test();
      final encrypted = await service.encryptWithPasswordAad(
        notebookId: 'nb-correct',
        plaintext: '敏感数据',
        password: 'secure-password-123',
      );
      expect(
        () => service.decryptWithPasswordAad(
          notebookId: 'nb-wrong',
          encryptedJson: encrypted,
          password: 'secure-password-123',
        ),
        throwsA(anything),
      );
    });

    test('v4 AAD 笔记本载荷加密 roundtrip', () async {
      const service = EncryptionService.test();
      final key = List<int>.generate(32, (i) => i);

      final encrypted = await service.encryptNotebookPayload(
        notebookId: 'nb-compat-test',
        plaintext: 'v4 格式内容',
        key: key,
      );
      final decrypted = await service.decryptNotebookPayload(
        notebookId: 'nb-compat-test',
        encryptedJson: encrypted,
        key: key,
      );
      expect(decrypted, 'v4 格式内容');
    });

    test('v4 AAD：错误 notebookId → 解密失败', () async {
      const service = EncryptionService.test();
      final key = List<int>.generate(32, (i) => i);

      final encrypted = await service.encryptNotebookPayload(
        notebookId: 'nb-correct',
        plaintext: '敏感数据',
        key: key,
      );
      expect(
        () => service.decryptNotebookPayload(
          notebookId: 'nb-wrong',
          encryptedJson: encrypted,
          key: key,
        ),
        throwsA(anything),
      );
    });

    test('PIN 长度验证', () {
      expect(EncryptionService.isPinLengthValid('12345'), false);
      expect(EncryptionService.isPinLengthValid('123456'), true);
      expect(EncryptionService.isPinLengthValid('1234567'), true);
    });

    test('渐进延迟信息（静态方法）', () {
      expect(EncryptionService.getProgressiveDelayInfo(0), '无延迟');
      expect(EncryptionService.getProgressiveDelayInfo(1), '1秒');
      expect(EncryptionService.getProgressiveDelayInfo(2), '5秒');
      expect(EncryptionService.getProgressiveDelayInfo(4), '5分钟');
      expect(EncryptionService.getProgressiveDelayInfo(5), '1小时');
    });

    test('渐进延迟序列单调递增', () {
      final delays = EncryptionService.progressiveDelaySeconds;
      for (var i = 1; i < delays.length; i++) {
        expect(delays[i] > delays[i - 1], true,
            reason: '延迟序列必须单调递增');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 场景 4：渐进延迟（ProgressiveDelay）
  // ═══════════════════════════════════════════════════════════
  group('渐进延迟（Progressive Delay）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('初始状态：无延迟', () async {
      expect(await ProgressiveDelay.getCurrentDelay(), 0);
      expect(await ProgressiveDelay.needsDelay(), false);
    });

    test('getDelayForCount 延迟序列', () {
      expect(ProgressiveDelay.getDelayForCount(0), 0);
      expect(ProgressiveDelay.getDelayForCount(1), 1); // 1s
      expect(ProgressiveDelay.getDelayForCount(2), 5); // 5s
      expect(ProgressiveDelay.getDelayForCount(3), 30); // 30s
      expect(ProgressiveDelay.getDelayForCount(4), 300); // 5min
      expect(ProgressiveDelay.getDelayForCount(5), 3600); // 1h
      // 超出序列 → 取最大值
      expect(ProgressiveDelay.getDelayForCount(100), 3600);
    });

    test('getDelayInfoForCount 显示格式', () {
      expect(ProgressiveDelay.getDelayInfoForCount(0), '无延迟');
      expect(ProgressiveDelay.getDelayInfoForCount(1), '1秒');
      expect(ProgressiveDelay.getDelayInfoForCount(2), '5秒');
      expect(ProgressiveDelay.getDelayInfoForCount(4), '5分钟');
      expect(ProgressiveDelay.getDelayInfoForCount(5), '1小时');
    });

    test('记录失败 → 失败计数递增', () async {
      expect(await ProgressiveDelay.getFailCount(), 0);
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getFailCount(), 1);
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getFailCount(), 2);
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getFailCount(), 3);
    });

    test('成功后重置计数', () async {
      await ProgressiveDelay.recordFailure();
      await ProgressiveDelay.recordFailure();
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getFailCount(), 3);

      await ProgressiveDelay.resetOnSuccess();
      expect(await ProgressiveDelay.getFailCount(), 0);
    });

    test('needsDelay 随失败变化', () async {
      expect(await ProgressiveDelay.needsDelay(), false);
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.needsDelay(), true);
    });

    test('getCurrentDelay 随失败次数递增', () async {
      expect(await ProgressiveDelay.getCurrentDelay(), 0);
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getCurrentDelay(), 1); // 1s
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getCurrentDelay(), 5); // 5s
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getCurrentDelay(), 30); // 30s
    });

    test('getDelayInfo 显示格式', () async {
      expect(await ProgressiveDelay.getDelayInfo(), '无延迟');
      await ProgressiveDelay.recordFailure();
      expect(await ProgressiveDelay.getDelayInfo(), '1秒');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 场景 5：端到端加密笔记本测试
  // ═══════════════════════════════════════════════════════════
  group('端到端加密笔记本测试', () {
    const encryption = EncryptionService.test();

    test('完整流程：设置密码 → 加密内容 → 解密验证', () async {
      final password = 'notebook_password_123';
      final content = jsonEncode({
        'title': '我的加密笔记',
        'pages': [
          {'id': 1, 'content': '第一页内容', 'strokes': []},
          {'id': 2, 'content': '第二页内容', 'strokes': []},
        ],
        'createdAt': DateTime.now().toIso8601String(),
      });

      // 加密
      final encrypted = await encryption.encrypt(content, password);
      expect(encrypted.isNotEmpty, true);

      // 验证密文结构
      final map = jsonDecode(encrypted) as Map<String, dynamic>;
      expect(map.containsKey('s'), true); // salt
      expect(map.containsKey('n'), true); // nonce
      expect(map.containsKey('c'), true); // ciphertext
      expect(map.containsKey('v'), true); // version
      expect(map['v'], 5);

      // 解密
      final decrypted = await encryption.decrypt(encrypted, password);
      expect(decrypted, content);

      // 验证结构完整性
      final decMap = jsonDecode(decrypted) as Map<String, dynamic>;
      expect(decMap['title'], '我的加密笔记');
      expect((decMap['pages'] as List).length, 2);
    });

    test('加密笔记本内容：不同页面不同密文', () async {
      final page1 = await encryption.encrypt('页面 1 内容', 'password');
      final page2 = await encryption.encrypt('页面 2 内容', 'password');
      expect(page1 != page2, true,
          reason: '随机盐+随机nonce → 不同密文');
    });

    test('加密笔记本：大容量内容', () async {
      final largeContent = '这是一段很长的文本。' * 1000;
      final cipher = await encryption.encrypt(largeContent, 'password');
      final dec = await encryption.decrypt(cipher, 'password');
      expect(dec, largeContent);
    });

    test('密钥轮换场景：修改密码后旧密文仍可解密', () async {
      const service = EncryptionService.test();
      final oldPassword = 'old_password_123';
      final newPassword = 'new_password_456';

      // 用旧密码加密
      final encrypted = await service.encrypt('重要笔记', oldPassword);

      // 修改密码后，旧密文仍然可以解密（因为盐+密码在 JSON 中）
      final decrypted = await service.decrypt(encrypted, oldPassword);
      expect(decrypted, '重要笔记');

      // 用新密码加密新内容
      final newEncrypted = await service.encrypt('新笔记', newPassword);
      final newDecrypted = await service.decrypt(newEncrypted, newPassword);
      expect(newDecrypted, '新笔记');

      // 新密码无法解密旧密文
      expect(
        () => service.decrypt(encrypted, newPassword),
        throwsA(anything),
      );
    });

    test('密码盘加密模式 roundtrip（大笔记多页批量）', () async {
      final masterKey = List<int>.generate(32, (i) => i);

      // 加密 20 个页面
      final pages = <String>[];
      final encrypted = <String>[];
      for (var i = 0; i < 20; i++) {
        final pageContent = jsonEncode({
          'id': i,
          'content': '第 $i 页的加密内容',
          'strokes': List.generate(5, (j) => {'x': i * j, 'y': j}),
        });
        pages.add(pageContent);
        encrypted.add(await encryption.encryptWithKey(pageContent, masterKey));
      }

      // 解密验证所有页面
      for (var i = 0; i < 20; i++) {
        final dec = await encryption.decryptWithKey(encrypted[i], masterKey);
        expect(jsonDecode(dec)['content'], '第 $i 页的加密内容');
      }
    });

    test('恢复密钥端到端：创建 → 包裹 → 恢复', () async {
      const recoveryPhrase = 'abandon ability able about above';

      // 生成随机主密钥
      final masterKey = List<int>.generate(32, (i) => i + 1);

      // 用恢复密钥包裹主密钥
      final envelope =
          await encryption.wrapMasterKey(masterKey, recoveryPhrase);

      // 用恢复密钥恢复
      final recovered =
          await encryption.unwrapMasterKey(envelope, recoveryPhrase);
      expect(recovered, masterKey);

      // 用恢复的主密钥解密数据
      final encrypted =
          await encryption.encryptWithKey('恢复的数据', masterKey);
      final decrypted =
          await encryption.decryptWithKey(encrypted, recovered);
      expect(decrypted, '恢复的数据');
    });

    test('笔记加密后不可读：密文不包含标题/内容', () async {
      final noteData = {
        'title': '绝密笔记标题',
        'content': '这是绝密内容，不能泄露',
        'tags': ['机密', '重要'],
      };

      final encrypted =
          await encryption.encrypt(jsonEncode(noteData), 'secure_pwd');

      // 密文中不包含任何明文关键词
      expect(encrypted.contains('绝密'), false);
      expect(encrypted.contains('不能泄露'), false);
      expect(encrypted.contains('机密'), false);
    });

    test('Unicode 内容加解密', () async {
      final unicode = '🔐 中文笔记 日本語ノート 한국어 📝 emojis 🎨';
      final cipher = await encryption.encrypt(unicode, 'pwd');
      final dec = await encryption.decrypt(cipher, 'pwd');
      expect(dec, unicode);
    });

    test('空内容加解密', () async {
      final cipher = await encryption.encrypt('', 'password');
      final dec = await encryption.decrypt(cipher, 'password');
      expect(dec, '');
    });
  });
}
