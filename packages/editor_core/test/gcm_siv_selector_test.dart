import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// SAFE 2026 借鉴——GcmSivSelector 测试（纯逻辑——不搞崩）。
void main() {
  test('GcmSivConfig：默认值', () {
    const config = GcmSivConfig();
    expect(config.preferSiv, true);
    expect(config.nonceReuseDetection, true);
    expect(config.fallbackToGcm, false);
    expect(config.maxNonceUses, 1000000);
  });

  test('select：默认优先 GCM-SIV（NMR——SAFE 2026）', () {
    const selector = GcmSivSelector();
    final selection = selector.select(const GcmSivConfig());
    expect(selection.usesSiv, true);
    expect(selection.algorithm, 'aes-256-gcm-siv');
    expect(selection.reason, contains('NMR'));
  });

  test('select：nonce 复用——GCM-SIV 安全降级', () {
    const selector = GcmSivSelector();
    final selection = selector.select(
      const GcmSivConfig(),
      nonceReused: true,
    );
    expect(selection.usesSiv, true); // 仍用 GCM-SIV（NMR 安全）。
    expect(selection.warning, contains('Nonce reuse'));
  });

  test('select：nonce 预算耗尽——建议轮换密钥', () {
    const selector = GcmSivSelector();
    final selection = selector.select(
      const GcmSivConfig(),
      nonceUses: 1000000, // 达到上限。
    );
    expect(selection.usesSiv, true);
    expect(selection.warning, contains('Rotate key'));
  });

  test('select：fallbackToGcm——nonce 耗尽回退 GCM（危险警告）', () {
    const selector = GcmSivSelector();
    final selection = selector.select(
      const GcmSivConfig(fallbackToGcm: true, preferSiv: false),
      nonceUses: 1000000,
    );
    expect(selection.algorithm, 'aes-256-gcm');
    expect(selection.warning, contains('DANGER'));
  });

  test('select：preferSiv=false——使用传统 GCM', () {
    const selector = GcmSivSelector();
    final selection = selector.select(const GcmSivConfig(preferSiv: false));
    expect(selection.algorithm, 'aes-256-gcm');
    expect(selection.warning, contains('Prefer GCM-SIV'));
  });

  test('shouldRotateKey：达到上限返回 true', () {
    const selector = GcmSivSelector();
    expect(selector.shouldRotateKey(const GcmSivConfig(), 1000000), true);
    expect(selector.shouldRotateKey(const GcmSivConfig(), 999999), false);
  });

  test('nonceBudgetRemaining：预算剩余百分比', () {
    const selector = GcmSivSelector();
    expect(selector.nonceBudgetRemaining(const GcmSivConfig(), 0), 1.0);
    expect(selector.nonceBudgetRemaining(const GcmSivConfig(), 500000), closeTo(0.5, 0.01));
    expect(selector.nonceBudgetRemaining(const GcmSivConfig(), 1000000), 0.0);
  });

  test('AlgorithmSelection：usesSiv + 相等性', () {
    const siv = AlgorithmSelection(algorithm: 'aes-256-gcm-siv', reason: 'x');
    expect(siv.usesSiv, true);
    const gcm = AlgorithmSelection(algorithm: 'aes-256-gcm', reason: 'y');
    expect(gcm.usesSiv, false);
    const other = AlgorithmSelection(algorithm: 'aes-256-gcm-siv', reason: 'z');
    expect(siv, other); // 按 algorithm 相等。
  });
}
