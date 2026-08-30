// 由 Claude 团队生成 | Drawing Notes App
// 纯逻辑部件：保存失败重试策略决策。
// 无 flutter/io/controller/存储依赖；不可变输入 → 确定性输出。

/// 保存失败后的重试决策。
enum SaveRetryDecision {
  /// 立即重试。
  retry,

  /// 退避等待后重试。
  backoff,

  /// 放弃重试，上报错误。
  giveUp,
}

/// 保存失败重试策略的输入参数。
class SaveFailureInput {
  const SaveFailureInput({required this.failureCount, required this.elapsed});

  /// 连续失败次数（从 1 开始）。
  final int failureCount;

  /// 自首次失败以来的累计耗时。
  final Duration elapsed;
}

/// 纯逻辑保存失败重试策略。
///
/// 规则：
/// - failureCount == 1 → [SaveRetryDecision.retry]（首次失败立即重试）
/// - failureCount 2-3 且 elapsed < backoffThreshold → [SaveRetryDecision.backoff]（退避等待）
/// - failureCount >= 4 或 elapsed >= giveUpThreshold → [SaveRetryDecision.giveUp]（放弃）
///
/// 默认阈值：backoffThreshold = 5s，giveUpThreshold = 30s。
class SaveFailurePolicy {
  const SaveFailurePolicy({
    this.backoffThreshold = const Duration(seconds: 5),
    this.giveUpThreshold = const Duration(seconds: 30),
  });

  /// 进入退避的累计耗时阈值。
  final Duration backoffThreshold;

  /// 放弃重试的累计耗时阈值。
  final Duration giveUpThreshold;

  /// 根据输入参数决策重试行为。
  SaveRetryDecision decide(SaveFailureInput input) {
    // 超时或失败次数过多，放弃。
    if (input.failureCount >= 4 || input.elapsed >= giveUpThreshold) {
      return SaveRetryDecision.giveUp;
    }

    // 首次失败，立即重试。
    if (input.failureCount <= 1) {
      return SaveRetryDecision.retry;
    }

    // 2-3 次失败：若在退避阈值内则 backoff，否则 giveUp。
    if (input.elapsed < backoffThreshold) {
      return SaveRetryDecision.backoff;
    }

    return SaveRetryDecision.giveUp;
  }
}
