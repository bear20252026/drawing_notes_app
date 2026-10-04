// 门禁/回归共用的「轮询等待真实异步完成」探针（2026-10-04 测试侧加固）。
//
// 缘起：`fix_regression_test.dart` 三处用 `for (var i = 0; i < 100; i++) {
// await Future.delayed(10ms); }` 睡满 1 秒，把「睡够了」当成「做完了」的
// 判据（盲睡当 oracle）——慢机器上睡够仍未完成会假红，快机器上纯浪费 1 秒，
// 而真正的完成信号从未被观测。`memory_p0_regression_test.dart` 早已改用
// 轮询探针（2026-09-23 全量跑两次偶发失败后的修法），但该写法当时留在文件
// 内是私有 `_waitUntil`。本文件把它抽成**唯一一份**共享实现，两处共用，
// 不再复制第三份。
//
// 语义纪律（与原 `_waitUntil` 完全一致，不得弱化）：
// - **超时后直接返回**，不 `fail('timeout')`：让随后的 `expect` 带着原始断言
//   信息失败，失败原因仍是「被测行为不成立」而非「等待器抱怨」；
// - **绝不无限等待**：真缺陷时必须有限时间内变红，否则用例挂到套件超时，
//   门禁连「红」都拿不到。
//
// 用法约定：探针应当观测**完成条件本身**（位图已生成、缓存已解码…），
// 而不是把紧随其后的 expect 条件抄一遍——否则断言退化成恒真、失去牙齿。
//
// 本文件是「等待真实异步完成」的**唯一一份**实现，两个入口同纪律：
// - [waitUntil]：纯异步（`test()` 体）探针；
// - [WidgetTesterPumpUntil.pumpUntil]：Widget 测试（`testWidgets()` 的
//   FakeAsync 区）探针，见 T-08（审计 2026-09-27）下沉说明。

import 'package:flutter_test/flutter_test.dart';

/// 轮询 [probe] 直到为真或 [timeout] 到期；到期后原样返回。
Future<void> waitUntil(
  bool Function() probe, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final sw = Stopwatch()..start();
  while (!probe()) {
    if (sw.elapsed > timeout) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Widget 测试专用探针（T-08 下沉共享，2026-10-04）：固定步长 `pump` 至
/// [condition] 满足或 [maxSteps] 耗尽——取代「双段盲泵 / 固定 pump 当时序
/// 判据」（`pump(100ms); pump(100ms);` 之类），慢机器不会因固定余量击穿而
/// 假红，快机器不空耗 fake 时钟。
///
/// 为什么不能复用上面的 [waitUntil]：`testWidgets` 跑在 FakeAsync 区，
/// `Future.delayed` 的定时器只有 `tester.pump` 才推进——纯 sleep 会死锁。
/// `pump(step)` 一步两用：既推进假时钟，又产出一帧让状态回灌到 widget 树。
///
/// 语义纪律与 [waitUntil] 完全一致（实现即原
/// `editor_shortcuts_text_guard_test` 私有 `pumpUntil`，逐字搬入，仅改为
/// 扩展方法以共享）：
/// - 条件不满足时**静默返回**，不 `fail`：让随后的 `expect` 带着原始断言
///   信息失败，失败原因仍是「被测行为不成立」；
/// - [maxSteps] 有上界，绝不无限等。默认 40 × 50ms = 2s 假时钟。
///
/// 调用约定（**必须遵守**）：条件是在泵**之前**求值的，所以调用方要先
/// `await tester.pump()` 产出首帧——否则首帧缺失，这一帧里才会抛的布局异常
/// 与才渲染出的内容都观测不到（等价于把断言改弱）。探针条件仍遵原约定：
/// 观测**完成条件本身**，不要把紧随其后的 `expect` 整条抄一遍。
extension WidgetTesterPumpUntil on WidgetTester {
  Future<void> pumpUntil(
    bool Function() condition, {
    Duration step = const Duration(milliseconds: 50),
    int maxSteps = 40,
  }) async {
    for (var i = 0; i < maxSteps && !condition(); i++) {
      await pump(step);
    }
  }
}
