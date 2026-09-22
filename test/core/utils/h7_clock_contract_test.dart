// H7：脆弱测试时钟收敛样本——不直接依赖 DateTime.now 做断言，
// 改为可注入 FakeClock（与 app_lock_guard_test 同模式）。

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/utils/time_serialization.dart';
import '../../helpers/fake_clock.dart';

void main() {
  test('timeToIso 恒带 Z（UTC 写侧）', () {
    final fixed = DateTime.utc(2026, 9, 21, 12, 0, 0);
    final iso = timeToIso(fixed);
    expect(iso, endsWith('Z'));
  });

  test('timeFromIso 兼容无偏移历史串', () {
    final legacy = timeFromIso('2026-01-02T03:04:05');
    expect(legacy.year, 2026);
    expect(legacy.hour, 3);
  });

  test('FakeClock 可推进，不依赖墙钟', () {
    final clock = FakeClock(DateTime.utc(2026, 1, 1));
    final t0 = clock();
    clock.advanceBy(const Duration(minutes: 5));
    expect(clock().difference(t0), const Duration(minutes: 5));
  });
}
