import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// EPC 2026 借鉴——SecretSharingService 密钥分割测试（纯逻辑——不搞崩）。
void main() {
  test('validateThreshold：有效配置', () {
    const service = SecretSharingService();
    expect(service.validateThreshold(totalShares: 5, threshold: 3), true);
    expect(service.validateThreshold(totalShares: 3, threshold: 2), true);
  });

  test('validateThreshold：无效配置', () {
    const service = SecretSharingService();
    expect(service.validateThreshold(totalShares: 1, threshold: 1), false); // < 2。
    expect(service.validateThreshold(totalShares: 3, threshold: 4), false); // threshold > shares。
    expect(service.validateThreshold(totalShares: 3, threshold: 1), false); // threshold < 2。
  });

  test('split/combine：任意 M ≥ threshold 份恢复原秘密', () {
    const service = SecretSharingService();
    const secret = [72, 101, 108, 108, 111]; // 'Hello'。
    final shares = service.split(secret, totalShares: 5, threshold: 3);
    expect(shares.length, 5);

    // 任意 3 份（阈值）恢复。
    final recovered = service.combine(shares.take(3).toList(), threshold: 3);
    expect(recovered, secret);
  });

  test('split/combine：不同子集恢复', () {
    const service = SecretSharingService();
    final secret = List.generate(16, (i) => i * 7 % 256); // 16 字节密钥。
    final shares = service.split(secret, totalShares: 5, threshold: 3);

    // 取第 1、3、5 份。
    final subset = [shares[0], shares[2], shares[4]];
    final recovered = service.combine(subset, threshold: 3);
    expect(recovered, secret);
  });

  test('combine：份额不足（< threshold）返回 null', () {
    const service = SecretSharingService();
    const secret = [1, 2, 3];
    final shares = service.split(secret, totalShares: 5, threshold: 3);
    final recovered = service.combine(shares.take(2).toList(), threshold: 3);
    expect(recovered, isNull);
  });

  test('split：无效阈值配置抛异常', () {
    const service = SecretSharingService();
    expect(
      () => service.split([1, 2, 3], totalShares: 3, threshold: 4),
      throwsArgumentError,
    );
  });

  test('SecretShare：copyWith + 相等性', () {
    const share = SecretShare(index: 1, value: [10, 20]);
    final updated = share.copyWith(value: [30, 40]);
    expect(share.value, [10, 20]); // 原实例不变。
    expect(updated.value, [30, 40]);
    const other = SecretShare(index: 1, value: [99, 99]);
    expect(share, other); // 按 index 相等。
  });
}
