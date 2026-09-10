// 测试基建：可手动推进的假时钟。
//
// 供依赖 [DateTime] / 单调钟的测试在确定性时间推进下运行，避免依赖真实
// 系统时钟（真实时钟在 CI / 本机会让断言漂移）。本实现统一了此前
// `app_lock_guard_test.dart` 的 `FakeClock`（毫秒推进 + 可读写 `ms`）与
// `save_scheduler_test.dart` 的 `_FakeClock`（Duration 推进）两套语义：
// 两者都保留，调用方按需选用，行为与测试语义保持不变。
library;

/// 可手动推进的假时钟。
///
/// 起点取 [start]（缺省为 2026-01-01T08:00:00），之后只由 [advance] /
/// [advanceBy] 或直接读写 [ms] 改变；[call] 永远返回当前假时间。
///
/// 注意：被 [call] 注入到生产逻辑时，逻辑内部常借助 `max(假时钟, 真实
/// 单调钟, 高水位线)` 兜底。若你的测试需要假时钟「占主导」而对抗真实
/// 单调钟（如冷却/超时建模），构造时应传入 `DateTime.now()` 起始点。
class FakeClock {
  FakeClock([DateTime? start])
    : ms = (start ?? DateTime(2026, 1, 1, 8, 0, 0)).millisecondsSinceEpoch;

  /// 当前假时钟的 Unix 毫秒值。可直接读写以建模回拨（`ms -= ...`）等场景。
  int ms;

  /// 返回当前假时间。
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(ms);

  /// 推进 [milliseconds] 毫秒并返回推进后的毫秒值。
  int advance(int milliseconds) {
    ms += milliseconds;
    return ms;
  }

  /// 以 [Duration] 推进（等价于 [advance] 的毫秒换算，返回推进后毫秒值）。
  int advanceBy(Duration d) => advance(d.inMilliseconds);
}
