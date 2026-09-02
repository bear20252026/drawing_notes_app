// U3 P1-12：SearchDebouncer 单元测试。
//
// 用 testWidgets 的虚拟时钟（pump）驱动，验证 run 合帧 / flush 即时 / dispose。

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/shared/utils/search_debouncer.dart';

void main() {
  testWidgets('run 在窗口内多次调用只执行最后一次（合帧）', (tester) async {
    final executed = <int>[];
    final debouncer = SearchDebouncer();

    debouncer.run(() => executed.add(1));
    await tester.pump(const Duration(milliseconds: 100));
    debouncer.run(() => executed.add(2));
    debouncer.run(() => executed.add(3));

    // 窗口（250ms）未到：一次都不执行。
    expect(executed, isEmpty);
    // 最后一次 run 在 t=100 调度，250ms 窗口至 t=350 到期。
    await tester.pump(const Duration(milliseconds: 250));
    expect(executed, [3]);

    debouncer.dispose();
  });

  testWidgets('flush 立即执行动作并取消挂起的防抖', (tester) async {
    final executed = <String>[];
    final debouncer = SearchDebouncer();

    debouncer.run(() => executed.add('pending'));
    debouncer.flush(() => executed.add('flushed'));

    // flush 即时生效。
    expect(executed, ['flushed']);
    // 原挂起动作在窗口过后不再执行。
    await tester.pump(const Duration(milliseconds: 500));
    expect(executed, ['flushed']);

    debouncer.dispose();
  });

  testWidgets('flush 无挂起时也立即执行（清空按钮路径）', (tester) async {
    final executed = <bool>[];
    final debouncer = SearchDebouncer();

    debouncer.flush(() => executed.add(true));
    expect(executed, [true]);

    debouncer.dispose();
  });

  testWidgets('dispose 后挂起的动作不再执行', (tester) async {
    var executed = false;
    final debouncer = SearchDebouncer();

    debouncer.run(() => executed = true);
    debouncer.dispose();
    await tester.pump(const Duration(milliseconds: 500));

    expect(executed, isFalse);
  });

  testWidgets('dispose 后 run 为安全操作（不抛异常）', (tester) async {
    final debouncer = SearchDebouncer();
    debouncer.dispose();
    debouncer.run(() {});
    await tester.pump(const Duration(milliseconds: 300));
  });
}
