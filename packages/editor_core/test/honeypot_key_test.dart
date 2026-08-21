import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 安全最佳实践借鉴——HoneypotKeyService 蜜罐密钥测试（纯逻辑——不搞崩）。
void main() {
  test('HoneypotKeyConfig：默认值', () {
    const config = HoneypotKeyConfig();
    expect(config.enabled, true);
    expect(config.maxDecryptAttempts, 3);
    expect(config.alertOnAccess, true);
    expect(config.alertThreshold, 2);
  });

  test('recordDecryptAttempt：访问诱饵密钥即告警', () {
    const service = HoneypotKeyService();
    final alert = service.recordDecryptAttempt(
      const HoneypotKeyConfig(),
      decryptAttempts: 0,
      accessed: true,
    );
    expect(alert.triggered, true);
    expect(alert.reason, contains('Honeypot key accessed'));
  });

  test('recordDecryptAttempt：尝试次数达到阈值告警', () {
    const service = HoneypotKeyService();
    final alert = service.recordDecryptAttempt(
      const HoneypotKeyConfig(),
      decryptAttempts: 2, // 达到阈值 2。
    );
    expect(alert.triggered, true);
    expect(alert.reason, contains('threshold'));
  });

  test('recordDecryptAttempt：未达阈值不告警', () {
    const service = HoneypotKeyService();
    final alert = service.recordDecryptAttempt(
      const HoneypotKeyConfig(),
      decryptAttempts: 1, // 低于阈值 2。
    );
    expect(alert.triggered, false);
  });

  test('recordDecryptAttempt：蜜罐禁用', () {
    const service = HoneypotKeyService();
    final alert = service.recordDecryptAttempt(
      const HoneypotKeyConfig(enabled: false),
      decryptAttempts: 100,
    );
    expect(alert.triggered, false);
  });

  test('shouldLockOut：达到强制上限', () {
    const service = HoneypotKeyService();
    expect(service.shouldLockOut(const HoneypotKeyConfig(), 3), true);
    expect(service.shouldLockOut(const HoneypotKeyConfig(), 2), false);
  });

  test('isHoneypot：诱饵密钥判断', () {
    const service = HoneypotKeyService();
    const honeypotIds = {'key-honey-1', 'key-honey-2'};
    expect(service.isHoneypot('key-honey-1', honeypotIds), true);
    expect(service.isHoneypot('key-real-1', honeypotIds), false);
  });

  test('HoneypotKeyConfig：copyWith 不可变', () {
    const config = HoneypotKeyConfig();
    final updated = config.copyWith(enabled: false, alertThreshold: 5);
    expect(config.enabled, true); // 原实例不变。
    expect(updated.enabled, false);
    expect(updated.alertThreshold, 5);
  });
}
