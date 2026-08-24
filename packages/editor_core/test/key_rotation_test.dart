import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 后量子迁移借鉴——KeyRotationService 密钥轮换测试（纯逻辑——不搞崩）。
void main() {
  test('KeyRotationPolicy：默认值', () {
    const policy = KeyRotationPolicy();
    expect(policy.rotationInterval, const Duration(days: 90));
    expect(policy.maxKeyAge, const Duration(days: 180));
    expect(policy.forceRotationOnCompromise, true);
    expect(policy.maxPreviousKeys, 2);
    expect(policy.enabled, true);
  });

  test('shouldRotate：周期内不轮换', () {
    const service = KeyRotationService();
    const policy = KeyRotationPolicy();
    final createdAt = DateTime.now().subtract(const Duration(days: 30));
    final result = service.shouldRotate(keyCreatedAt: createdAt, policy: policy);
    expect(result.rotated, false);
    expect(result.reason, 'Within policy');
  });

  test('shouldRotate：达到轮换周期', () {
    const service = KeyRotationService();
    const policy = KeyRotationPolicy(rotationInterval: Duration(days: 30));
    final createdAt = DateTime.now().subtract(const Duration(days: 40));
    final result = service.shouldRotate(keyCreatedAt: createdAt, policy: policy);
    expect(result.rotated, true);
    expect(result.reason, contains('Rotation interval'));
  });

  test('shouldRotate：超过最大寿命', () {
    const service = KeyRotationService();
    const policy = KeyRotationPolicy(maxKeyAge: Duration(days: 60));
    final createdAt = DateTime.now().subtract(const Duration(days: 100));
    final result = service.shouldRotate(keyCreatedAt: createdAt, policy: policy);
    expect(result.rotated, true);
    expect(result.reason, contains('Key age exceeded'));
  });

  test('shouldRotate：泄露强制轮换', () {
    const service = KeyRotationService();
    const policy = KeyRotationPolicy();
    final createdAt = DateTime.now();
    final result = service.shouldRotate(
      keyCreatedAt: createdAt,
      policy: policy,
      compromised: true,
    );
    expect(result.rotated, true);
    expect(result.reason, contains('compromised'));
  });

  test('shouldRotate：轮换禁用', () {
    const service = KeyRotationService();
    const policy = KeyRotationPolicy(enabled: false);
    final createdAt = DateTime.now().subtract(const Duration(days: 1000));
    final result = service.shouldRotate(keyCreatedAt: createdAt, policy: policy);
    expect(result.rotated, false);
    expect(result.reason, 'Rotation disabled');
  });

  test('shouldRotate：密钥 ID 版本递增', () {
    const service = KeyRotationService();
    const policy = KeyRotationPolicy(rotationInterval: Duration(days: 1));
    final createdAt = DateTime.now().subtract(const Duration(days: 10));
    final result = service.shouldRotate(
      keyCreatedAt: createdAt,
      policy: policy,
      currentKeyId: 'key-3',
    );
    expect(result.newKeyId, 'key-4'); // 版本递增。
  });

  test('KeyRotationPolicy：copyWith 不可变', () {
    const policy = KeyRotationPolicy();
    final updated = policy.copyWith(enabled: false, maxPreviousKeys: 5);
    expect(policy.enabled, true); // 原实例不变。
    expect(updated.enabled, false);
    expect(updated.maxPreviousKeys, 5);
  });
}
