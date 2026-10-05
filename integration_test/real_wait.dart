/// integration_test 共用的**真实时钟**等待（2026-10-05 从 doc_lifecycle_test
/// 的文件内私有实现抽出，此前 `cuj_01_test` 缺它而长期真机红）。
///
/// 为什么必须单独存在：`flutter test ... -d windows` 走的是 LiveTest binding，
/// `Timer`/`Future.delayed` 挂在**真实时钟**上，而 `pump(duration)` 只推进测试
/// 时钟、不消耗真实时间。于是「800ms 防抖落盘 → 列表重扫」这类链路用
/// `pumpAndSettle` 永远等不到——表现成「刚建的文档在列表里凭空消失」，
/// 看着像产品数据丢失，实为测试没有跨过真实定时器。
///
/// 语义纪律：真实 sleep 与 `pump` 交替进行——只 sleep 不 pump 则不产帧，
/// 写完盘的 UI 更新依旧不可见。
library;

import 'package:flutter_test/flutter_test.dart';

Future<void> realWait(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
