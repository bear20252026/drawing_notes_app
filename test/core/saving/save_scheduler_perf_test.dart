// v1.17.20 ⑧ 退出性能回归防护。
//
// 语义：干净调度器（无未落盘改动、无飞行中保存）的 flushIfDirty 必须
// 近零耗时返回且不触发任何 IO——这是「无改动退出编辑器秒退」的根基。
// 未来任何人在退出路径塞入同步重活（缩略图渲染/编码/网络）都会在此
// 被卡住。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/saving/save_scheduler.dart';

void main() {
  test('干净调度器 flushIfDirty 50ms 内返回且零保存调用', () async {
    var saveCalls = 0;
    final scheduler = SaveScheduler(save: () async => saveCalls++);

    final watch = Stopwatch()..start();
    await scheduler.flushIfDirty();
    watch.stop();

    expect(saveCalls, 0, reason: '无改动退出不应触发任何保存 IO');
    expect(
      watch.elapsedMilliseconds,
      lessThan(50),
      reason: '无改动退出应近零耗时（退出卡顿回归防护）',
    );
    scheduler.dispose();
  });

  test('干净调度器重复 flushIfDirty 同样近零耗时（多次切页场景）', () async {
    var saveCalls = 0;
    final scheduler = SaveScheduler(save: () async => saveCalls++);

    final watch = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      await scheduler.flushIfDirty();
    }
    watch.stop();

    expect(saveCalls, 0);
    expect(watch.elapsedMilliseconds, lessThan(50));
    scheduler.dispose();
  });
}
