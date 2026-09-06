// 由 Claude 团队生成 | Drawing Notes App
// SyncRetryPolicy 纯逻辑测试。

import 'package:drawing_notes_app/core/sync/sync_retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncRetryDecision', () {
    test('enum values exist', () {
      expect(
        SyncRetryDecision.values,
        containsAll([
          SyncRetryDecision.retry,
          SyncRetryDecision.backoff,
          SyncRetryDecision.giveUp,
        ]),
      );
    });
  });

  group('SyncRetryPolicy.decide', () {
    const policy = SyncRetryPolicy();

    test('failure 1 → retry', () {
      expect(
        policy.decide(
          const SyncRetryInput(failureCount: 1, elapsed: Duration.zero),
        ),
        SyncRetryDecision.retry,
      );
    });

    test('failure 1 with elapsed time still → retry', () {
      expect(
        policy.decide(
          const SyncRetryInput(failureCount: 1, elapsed: Duration(seconds: 10)),
        ),
        SyncRetryDecision.retry,
      );
    });

    test('failure 2 with short elapsed → backoff', () {
      expect(
        policy.decide(
          const SyncRetryInput(failureCount: 2, elapsed: Duration(seconds: 3)),
        ),
        SyncRetryDecision.backoff,
      );
    });

    test('failure 3 with short elapsed → backoff', () {
      expect(
        policy.decide(
          const SyncRetryInput(failureCount: 3, elapsed: Duration(seconds: 10)),
        ),
        SyncRetryDecision.backoff,
      );
    });

    test('failure 4 → giveUp (maxAttempts reached)', () {
      expect(
        policy.decide(
          const SyncRetryInput(failureCount: 4, elapsed: Duration.zero),
        ),
        SyncRetryDecision.giveUp,
      );
    });

    test('failure 5 → giveUp', () {
      expect(
        policy.decide(
          const SyncRetryInput(failureCount: 5, elapsed: Duration(seconds: 5)),
        ),
        SyncRetryDecision.giveUp,
      );
    });

    test('long elapsed (>=60s) → giveUp even with few attempts', () {
      expect(
        policy.decide(
          const SyncRetryInput(failureCount: 2, elapsed: Duration(seconds: 60)),
        ),
        SyncRetryDecision.giveUp,
      );
      expect(
        policy.decide(
          const SyncRetryInput(failureCount: 2, elapsed: Duration(seconds: 90)),
        ),
        SyncRetryDecision.giveUp,
      );
    });

    test(
      'failure 3 with elapsed past backoff window but before giveUp → giveUp',
      () {
        // elapsed >= 15s (backoffWindow) but < 60s (giveUpWindow), failureCount=3 < 4
        expect(
          policy.decide(
            const SyncRetryInput(
              failureCount: 3,
              elapsed: Duration(seconds: 20),
            ),
          ),
          SyncRetryDecision.giveUp,
        );
      },
    );

    test('failure 2 at exactly backoffWindow boundary → giveUp', () {
      // elapsed == 15s is NOT < 15s, so giveUp
      expect(
        policy.decide(
          const SyncRetryInput(failureCount: 2, elapsed: Duration(seconds: 15)),
        ),
        SyncRetryDecision.giveUp,
      );
    });
  });

  group('SyncRetryPolicy.delayFor', () {
    const policy = SyncRetryPolicy();

    test('failure 1 → zero delay (immediate retry)', () {
      expect(policy.delayFor(1), Duration.zero);
    });

    test('failure 0 → zero delay', () {
      expect(policy.delayFor(0), Duration.zero);
    });

    test('failure 2 → 1s (baseDelay)', () {
      expect(policy.delayFor(2), const Duration(seconds: 1));
    });

    test('failure 3 → 2s (exponential)', () {
      expect(policy.delayFor(3), const Duration(seconds: 2));
    });

    test('failure 4 → 4s (exponential, hits maxDelay)', () {
      expect(policy.delayFor(4), const Duration(seconds: 4));
    });

    test('failure 5 → capped at maxDelay (4s)', () {
      expect(policy.delayFor(5), const Duration(seconds: 4));
    });

    test('failure 10 → still capped at maxDelay', () {
      expect(policy.delayFor(10), const Duration(seconds: 4));
    });

    test('delay curve is monotonically non-decreasing', () {
      final delays = List.generate(
        8,
        (i) => policy.delayFor(i + 1).inMilliseconds,
      );
      for (var i = 1; i < delays.length; i++) {
        expect(
          delays[i],
          greaterThanOrEqualTo(delays[i - 1]),
          reason: 'delay at attempt ${i + 1} should be >= delay at attempt $i',
        );
      }
    });
  });

  group('SyncRetryPolicy.maxAttempts', () {
    test('default maxAttempts is 4', () {
      expect(const SyncRetryPolicy().maxAttempts, 4);
    });

    test('custom maxAttempts respected', () {
      const custom = SyncRetryPolicy(maxAttempts: 6);
      expect(custom.maxAttempts, 6);
      expect(
        custom.decide(
          const SyncRetryInput(failureCount: 4, elapsed: Duration.zero),
        ),
        SyncRetryDecision.backoff,
      );
      expect(
        custom.decide(
          const SyncRetryInput(failureCount: 6, elapsed: Duration.zero),
        ),
        SyncRetryDecision.giveUp,
      );
    });
  });

  group('SyncRetryOutcome', () {
    const policy = SyncRetryPolicy();

    test('retry outcome has zero backoff and canRetry', () {
      final outcome = policy.decideOutcome(
        const SyncRetryInput(failureCount: 1, elapsed: Duration.zero),
      );
      expect(outcome.decision, SyncRetryDecision.retry);
      expect(outcome.backoff, Duration.zero);
      expect(outcome.canRetry, isTrue);
    });

    test('backoff outcome has positive backoff and canRetry', () {
      final outcome = policy.decideOutcome(
        const SyncRetryInput(failureCount: 2, elapsed: Duration(seconds: 3)),
      );
      expect(outcome.decision, SyncRetryDecision.backoff);
      expect(outcome.backoff, const Duration(seconds: 1));
      expect(outcome.canRetry, isTrue);
    });

    test('giveUp outcome has null backoff and cannot retry', () {
      final outcome = policy.decideOutcome(
        const SyncRetryInput(failureCount: 4, elapsed: Duration.zero),
      );
      expect(outcome.decision, SyncRetryDecision.giveUp);
      expect(outcome.backoff, isNull);
      expect(outcome.canRetry, isFalse);
    });
  });

  group('determinism', () {
    const policy = SyncRetryPolicy();

    test('same input always yields same decision', () {
      const input = SyncRetryInput(
        failureCount: 3,
        elapsed: Duration(seconds: 8),
      );
      final first = policy.decide(input);
      for (var i = 0; i < 10; i++) {
        expect(policy.decide(input), first);
      }
    });

    test('same input always yields same outcome', () {
      const input = SyncRetryInput(
        failureCount: 2,
        elapsed: Duration(seconds: 5),
      );
      final first = policy.decideOutcome(input);
      for (var i = 0; i < 10; i++) {
        final again = policy.decideOutcome(input);
        expect(again.decision, first.decision);
        expect(again.backoff, first.backoff);
      }
    });
  });

  group('custom thresholds', () {
    test('custom backoffWindow and giveUpWindow', () {
      const custom = SyncRetryPolicy(
        backoffWindow: Duration(seconds: 10),
        giveUpWindow: Duration(seconds: 45),
      );
      // failure 2, elapsed 8s < 10s → backoff
      expect(
        custom.decide(
          const SyncRetryInput(failureCount: 2, elapsed: Duration(seconds: 8)),
        ),
        SyncRetryDecision.backoff,
      );
      // failure 2, elapsed 12s >= 10s but < 45s → giveUp
      expect(
        custom.decide(
          const SyncRetryInput(failureCount: 2, elapsed: Duration(seconds: 12)),
        ),
        SyncRetryDecision.giveUp,
      );
      // failure 2, elapsed 45s >= 45s → giveUp
      expect(
        custom.decide(
          const SyncRetryInput(failureCount: 2, elapsed: Duration(seconds: 45)),
        ),
        SyncRetryDecision.giveUp,
      );
    });

    test('custom baseDelay and maxDelay', () {
      const custom = SyncRetryPolicy(
        baseDelay: Duration(milliseconds: 500),
        maxDelay: Duration(seconds: 8),
      );
      expect(custom.delayFor(1), Duration.zero);
      expect(custom.delayFor(2), const Duration(milliseconds: 500));
      expect(custom.delayFor(3), const Duration(seconds: 1));
      expect(custom.delayFor(4), const Duration(seconds: 2));
      expect(custom.delayFor(5), const Duration(seconds: 4));
      expect(custom.delayFor(6), const Duration(seconds: 8));
      expect(custom.delayFor(7), const Duration(seconds: 8)); // capped
    });
  });
}
