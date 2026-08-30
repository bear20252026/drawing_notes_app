// 由 Claude 团队生成 | Drawing Notes App
// 纯逻辑部件：保存/自动保存调度决策。
// 无 flutter/io/controller/存储依赖；不可变输入 → 确定性输出。

/// 保存调度决策结果。
enum SaveScheduleDecision {
  /// 立即执行保存。
  saveNow,

  /// 延迟等待，后续再判断。
  defer,

  /// 无需保存，跳过。
  skip,
}

/// 保存调度决策的输入参数。
class SaveScheduleInput {
  const SaveScheduleInput({
    required this.dirty,
    required this.now,
    required this.debounce,
    this.lastSaveAt,
    this.saveInFlight = false,
    this.isExiting = false,
  });

  /// 文档是否有未保存的改动。
  final bool dirty;

  /// 上次成功保存的时间（null 表示从未保存过）。
  final DateTime? lastSaveAt;

  /// 当前时间。
  final DateTime now;

  /// 防抖窗口：两次保存之间的最小间隔。
  final Duration debounce;

  /// 是否已有保存操作正在进行中。
  final bool saveInFlight;

  /// 页面是否正在退出（需要兜底保存）。
  final bool isExiting;

  /// 距上次保存的时间间隔（从未保存过则返回 null）。
  Duration? get timeSinceLastSave =>
      lastSaveAt == null ? null : now.difference(lastSaveAt!);
}

/// 纯逻辑保存调度决策器。
///
/// 规则（按优先级）：
/// 1. 非 dirty → [SaveScheduleDecision.skip]
/// 2. isExiting + dirty → [SaveScheduleDecision.saveNow]（退出兜底）
/// 3. saveInFlight → [SaveScheduleDecision.defer]（合并为一次）
/// 4. dirty + 距上次保存 >= debounce（或从未保存）→ [SaveScheduleDecision.saveNow]
/// 5. dirty + 未到 debounce → [SaveScheduleDecision.defer]
class SaveScheduleDecisioner {
  const SaveScheduleDecisioner();

  /// 根据输入参数决策是否保存。
  SaveScheduleDecision decide(SaveScheduleInput input) {
    // 1. 无改动，跳过。
    if (!input.dirty) return SaveScheduleDecision.skip;

    // 2. 页面退出兜底：有改动则立即保存。
    if (input.isExiting) return SaveScheduleDecision.saveNow;

    // 3. 已有 in-flight 保存，延迟等待合并。
    if (input.saveInFlight) return SaveScheduleDecision.defer;

    // 4. 达到防抖窗口或从未保存，立即保存。
    final elapsed = input.timeSinceLastSave;
    if (elapsed == null || elapsed >= input.debounce) {
      return SaveScheduleDecision.saveNow;
    }

    // 5. 未到防抖窗口，延迟。
    return SaveScheduleDecision.defer;
  }
}
