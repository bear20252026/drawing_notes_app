import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Cryptomator 借鉴——EncryptionVaultManager 加密保险库测试（纯逻辑——不搞崩）。
void main() {
  group('VaultConfig', () {
    test('默认值', () {
      const config = VaultConfig();
      expect(config.autoLockDuration, const Duration(minutes: 5));
      expect(config.requireBiometric, false);
      expect(config.pbkdf2Iterations, 600000);
      expect(config.version, 3);
    });

    test('copyWith 不可变', () {
      const config = VaultConfig();
      final updated = config.copyWith(name: 'My Vault', autoLockDuration: const Duration(minutes: 10));
      expect(config.name, ''); // 原实例不变。
      expect(updated.name, 'My Vault');
      expect(updated.autoLockDuration, const Duration(minutes: 10));
    });
  });

  group('VaultResult', () {
    test('成功/失败/静态常量', () {
      expect(VaultResult.locked.success, true);
      expect(VaultResult.locked.state, VaultState.locked);
      expect(VaultResult.unlocked.success, true);
      expect(VaultResult.unlocked.state, VaultState.unlocked);
      final err = VaultResult.error('Wrong password', 'AUTH_FAIL');
      expect(err.success, false);
      expect(err.errorCode, 'AUTH_FAIL');
    });
  });

  group('EncryptionVaultManager', () {
    test('初始状态：uninitialized + needsSetup', () {
      final mgr = EncryptionVaultManager();
      expect(mgr.currentState, VaultState.uninitialized);
      expect(mgr.needsSetup, true);
      expect(mgr.isUnlocked, false);
      expect(mgr.isLocked, false);
    });

    test('setPassword：首次设置密码（uninitialized → unlocked）', () {
      final mgr = EncryptionVaultManager();
      final result = mgr.setPassword('MyStr0ngPass!');
      expect(result.success, true);
      expect(mgr.currentState, VaultState.unlocked);
      expect(mgr.isUnlocked, true);
    });

    test('setPassword：密码太短', () {
      final mgr = EncryptionVaultManager();
      final result = mgr.setPassword('123');
      expect(result.success, false);
      expect(result.errorCode, 'WEAK_PASSWORD');
      expect(mgr.currentState, VaultState.uninitialized); // 状态不变。
    });

    test('setPassword：重复初始化', () {
      final mgr = EncryptionVaultManager();
      mgr.setPassword('MyStr0ngPass!');
      final result = mgr.setPassword('AnotherPass!');
      expect(result.success, false);
      expect(result.errorCode, 'ALREADY_INIT');
    });

    test('unlock：锁定后解锁', () {
      final mgr = EncryptionVaultManager();
      mgr.setPassword('MyStr0ngPass!');
      mgr.lock();
      expect(mgr.currentState, VaultState.locked);
      final result = mgr.unlock('MyStr0ngPass!');
      expect(result.success, true);
      expect(mgr.currentState, VaultState.unlocked);
    });

    test('unlock：未锁定时解锁', () {
      final mgr = EncryptionVaultManager();
      mgr.setPassword('MyStr0ngPass!');
      final result = mgr.unlock('pass');
      expect(result.success, false);
      expect(result.errorCode, 'NOT_LOCKED');
    });

    test('lock：解锁后锁定', () {
      final mgr = EncryptionVaultManager();
      mgr.setPassword('MyStr0ngPass!');
      final result = mgr.lock();
      expect(result.success, true);
      expect(mgr.currentState, VaultState.locked);
      expect(mgr.isLocked, true);
    });

    test('lock：未解锁时锁定', () {
      final mgr = EncryptionVaultManager();
      final result = mgr.lock();
      expect(result.success, false);
      expect(result.errorCode, 'NOT_UNLOCKED');
    });

    test('checkAutoLock：超时自动锁定', () async {
      final mgr = EncryptionVaultManager(
        config: const VaultConfig(autoLockDuration: Duration(milliseconds: 100)),
      );
      mgr.setPassword('MyStr0ngPass!');
      expect(mgr.currentState, VaultState.unlocked);
      await Future.delayed(const Duration(milliseconds: 150));
      final autoLocked = mgr.checkAutoLock();
      expect(autoLocked, true);
      expect(mgr.currentState, VaultState.autoLocked);
      expect(mgr.isLocked, true);
    });

    test('recordActivity：防止自动锁定', () async {
      final mgr = EncryptionVaultManager(
        config: const VaultConfig(autoLockDuration: Duration(milliseconds: 200)),
      );
      mgr.setPassword('MyStr0ngPass!');
      await Future.delayed(const Duration(milliseconds: 100));
      mgr.recordActivity(); // 记录活动。
      await Future.delayed(const Duration(milliseconds: 150));
      final autoLocked = mgr.checkAutoLock();
      expect(autoLocked, false); // 未超时（100+150=250 < 200+100=300）。
    });

    test('changePassword：修改密码', () {
      final mgr = EncryptionVaultManager();
      mgr.setPassword('OldPass123!');
      final result = mgr.changePassword('OldPass123!', 'NewStr0ngPass!');
      expect(result.success, true);
    });

    test('changePassword：未解锁时修改', () {
      final mgr = EncryptionVaultManager();
      final result = mgr.changePassword('old', 'new');
      expect(result.success, false);
      expect(result.errorCode, 'NOT_UNLOCKED');
    });

    test('VaultState 枚举', () {
      expect(VaultState.values.length, 6);
    });

    test('VaultOperation 枚举', () {
      expect(VaultOperation.values.length, 5);
    });
  });
}
