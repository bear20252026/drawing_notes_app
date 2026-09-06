// 由 Claude 团队生成 | Drawing Notes App
// save_failure_policy.dart 单元测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/saving/save_failure_policy.dart';

void main() {
  group('SaveFailurePolicy', () {
    const policy = SaveFailurePolicy();

    test('failureCount=1 → retry（首次失败立即重试）', () {
      const input = SaveFailureInput(failureCount: 1, elapsed: Duration.zero);
      expect(policy.decide(input), SaveRetryDecision.retry);
    });

    test('failureCount=2, elapsed < backoffThreshold → backoff', () {
      const input = SaveFailureInput(
        failureCount: 2,
        elapsed: Duration(seconds: 2),
      );
      expect(policy.decide(input), SaveRetryDecision.backoff);
    });

    test('failureCount=3, elapsed < backoffThreshold → backoff', () {
      const input = SaveFailureInput(
        failureCount: 3,
        elapsed: Duration(seconds: 4),
      );
      expect(policy.decide(input), SaveRetryDecision.backoff);
    });

    test('failureCount=3, elapsed >= backoffThreshold → giveUp', () {
      const input = SaveFailureInput(
        failureCount: 3,
        elapsed: Duration(seconds: 6),
      );
      expect(policy.decide(input), SaveRetryDecision.giveUp);
    });

    test('failureCount>=4 → giveUp', () {
      const input = SaveFailureInput(
        failureCount: 4,
        elapsed: Duration(seconds: 1),
      );
      expect(policy.decide(input), SaveRetryDecision.giveUp);
    });

    test('elapsed >= giveUpThreshold → giveUp（超时放弃）', () {
      const input = SaveFailureInput(
        failureCount: 2,
        elapsed: Duration(seconds: 30),
      );
      expect(policy.decide(input), SaveRetryDecision.giveUp);
    });

    test('failureCount=5, elapsed 较小 → giveUp（次数过多）', () {
      const input = SaveFailureInput(
        failureCount: 5,
        elapsed: Duration(seconds: 2),
      );
      expect(policy.decide(input), SaveRetryDecision.giveUp);
    });

    test('自定义阈值：缩短 giveUpThreshold', () {
      const customPolicy = SaveFailurePolicy(
        backoffThreshold: Duration(seconds: 2),
        giveUpThreshold: Duration(seconds: 10),
      );
      const input = SaveFailureInput(
        failureCount: 2,
        elapsed: Duration(seconds: 5),
      );
      expect(customPolicy.decide(input), SaveRetryDecision.giveUp);
    });

    test('确定性：相同输入多次调用结果一致', () {
      const input = SaveFailureInput(
        failureCount: 2,
        elapsed: Duration(seconds: 3),
      );
      final first = policy.decide(input);
      final second = policy.decide(input);
      expect(first, second);
      expect(first, SaveRetryDecision.backoff);
    });
  });
}
