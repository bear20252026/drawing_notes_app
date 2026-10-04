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
