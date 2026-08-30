// 由 Claude 团队生成 | Drawing Notes App
// 纯逻辑部件：WebDAV 同步失败重试策略决策。
// 无 flutter/io/controller/存储依赖；不可变输入 → 确定性输出。

/// 同步失败后的重试决策。
enum SyncRetryDecision {
  /// 立即重试。
  retry,

  /// 退避等待后重试。
  backoff,

  /// 放弃重试，上报错误。
  giveUp,
}

/// 同步重试策略的输入参数。
class SyncRetryInput {
  const SyncRetryInput({required this.failureCount, required this.elapsed});

  /// 连续失败次数（从 1 开始）。
  final int failureCount;

  /// 自首次失败以来的累计耗时。
  final Duration elapsed;
}

/// 一次重试判定的结果（决策 + 建议等待时长）。
class SyncRetryOutcome {
  const SyncRetryOutcome(this.decision, [this.backoff]);

  /// 重试决策。
  final SyncRetryDecision decision;

  /// 建议退避等待时长；retry 为 Duration.zero，giveUp 为 null。
  final Duration? backoff;

  /// 是否可以重试（非 giveUp）。
  bool get canRetry => decision != SyncRetryDecision.giveUp;
}

/// 纯逻辑 WebDAV 同步失败重试策略。
///
/// 规则（确定性）：
/// - failureCount == 1 → [SyncRetryDecision.retry]（首次失败立即重试）
/// - failureCount 2-3 且 elapsed < [backoffWindow] → [SyncRetryDecision.backoff]（退避等待）
/// - failureCount >= [maxAttempts] 或 elapsed >= [giveUpWindow] → [SyncRetryDecision.giveUp]（放弃）
///
/// 退避延迟曲线（指数）：
/// - attempt 2 → 1s
/// - attempt 3 → 2s
/// - attempt >= 4 → 4s（但已达 giveUp 阈值，通常不会使用）
///
/// 默认阈值：[backoffWindow] = 15s，[giveUpWindow] = 60s，[maxAttempts] = 4。
class SyncRetryPolicy {
  const SyncRetryPolicy({
    this.backoffWindow = const Duration(seconds: 15),
    this.giveUpWindow = const Duration(minutes: 1),
    this.maxAttempts = 4,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 4),
  });

  /// 进入退避的累计耗时上限（超过即 giveUp）。
  final Duration backoffWindow;

  /// 放弃重试的累计耗时阈值。
  final Duration giveUpWindow;

  /// 最大尝试次数（达到即 giveUp）。
  final int maxAttempts;

  /// 指数退避的基延迟。
  final Duration baseDelay;

  /// 指数退避的上限延迟。
  final Duration maxDelay;

  /// 根据输入参数决策重试行为。
  SyncRetryDecision decide(SyncRetryInput input) {
    // 超时或失败次数过多，放弃。
    if (input.failureCount >= maxAttempts || input.elapsed >= giveUpWindow) {
      return SyncRetryDecision.giveUp;
    }

    // 首次失败，立即重试。
    if (input.failureCount <= 1) {
      return SyncRetryDecision.retry;
    }

    // 2-3 次失败：若在退避窗口内则 backoff，否则 giveUp。
    if (input.elapsed < backoffWindow) {
      return SyncRetryDecision.backoff;
    }

    return SyncRetryDecision.giveUp;
  }

  /// 计算给定失败次数对应的退避延迟。
  ///
  /// - failureCount <= 1 → [Duration.zero]（立即重试）
  /// - failureCount >= 2 → 指数退避：baseDelay * 2^(failureCount-2)，上限 [maxDelay]
  Duration delayFor(int failureCount) {
    if (failureCount <= 1) return Duration.zero;

    final exp = failureCount - 2;
    final multiplier = 1 << exp; // 2^exp
    final delayMs =
        baseDelay.inMilliseconds * multiplier > maxDelay.inMilliseconds
        ? maxDelay.inMilliseconds
        : baseDelay.inMilliseconds * multiplier;

    return Duration(milliseconds: delayMs);
  }

  /// 封装一次完整判定（决策 + 建议等待时长）。
  SyncRetryOutcome decideOutcome(SyncRetryInput input) {
    final decision = decide(input);

    switch (decision) {
      case SyncRetryDecision.retry:
        return SyncRetryOutcome(decision, Duration.zero);
      case SyncRetryDecision.backoff:
        return SyncRetryOutcome(decision, delayFor(input.failureCount));
      case SyncRetryDecision.giveUp:
        return SyncRetryOutcome(decision);
    }
  }
}
