// ============================================================================
// lock_exemption_test.dart —— 进程级失焦豁免窗口单测（2026-10-04）。
// ============================================================================
//
// 覆盖安全红线：默认不豁免 / 计数配对 / 作用域式自动复位 / TTL 上界。
// TTL 到期是单调秒表事实（不真等 5 分钟）——以 [LockExemption.remaining]
// 单调递减 + 达阈值即失效的边界来佐证「免死金牌不会永续」。

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/session_guard.dart';

void main() {
  // SessionGuard 构造内部建 AppLifecycleListener → 需先初始化 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(LockExemption.resetForTest);
  tearDown(LockExemption.resetForTest);

  test('默认不豁免：isActive 恒 false', () {
    expect(LockExemption.isActive, isFalse);
    expect(LockExemption.remaining, Duration.zero);
  });

  test('begin/end 配对：计数归零即失效', () {
    LockExemption.begin();
    expect(LockExemption.isActive, isTrue);
    LockExemption.end();
    expect(LockExemption.isActive, isFalse);
  });

  test('嵌套计数：内层提前 end 不关掉外层豁免', () {
    LockExemption.begin(); // 外
    LockExemption.begin(); // 内
    LockExemption.end(); // 内退——外层仍在窗口内
    expect(LockExemption.isActive, isTrue);
    LockExemption.end(); // 外退——末位清空
    expect(LockExemption.isActive, isFalse);
  });

  test('多余 end 不把计数压成负数（isActive 仍 false）', () {
    LockExemption.begin();
    LockExemption.end();
    LockExemption.end(); // 越界 end
    expect(LockExemption.isActive, isFalse);
  });

  test('run：抛异常也复位豁免（不泄漏永久免死金牌）', () async {
    await expectLater(
      LockExemption.run(() => throw StateError('picker crashed')),
      throwsStateError,
    );
    expect(LockExemption.isActive, isFalse);
  });

  test('run：返回值透传且结束后复位', () async {
    final v = await LockExemption.run(() async {
      expect(LockExemption.isActive, isTrue); // 窗口内
      return 42;
    });
    expect(v, 42);
    expect(LockExemption.isActive, isFalse); // 出窗口
  });

  test('TTL 有上界：remaining 不超 ttl 且单调递减（时钟推进即失效）', () async {
    LockExemption.begin();
    expect(LockExemption.remaining <= LockExemption.ttl, isTrue);
    final first = LockExemption.remaining;
    // 单调秒表推进（真实微秒）——用忙等一个短窗让 elapsed 明确前进。
    final spin = Stopwatch()..start();
    while (spin.elapsedMilliseconds < 5) {
      // 忙等 ≤5ms，仅让豁免剩余时长可见地缩短；不触碰真 KDF。
    }
    spin.stop();
    expect(LockExemption.remaining < first, isTrue);
    expect(LockExemption.remaining >= Duration.zero, isTrue);
    LockExemption.end();
    expect(LockExemption.remaining, Duration.zero);
  });

  test('SessionGuard.runWithExemption 与门共用同一窗口（委托生效）', () async {
    var locked = false;
    final guard = SessionGuard(onLock: () => locked = true);
    await guard.runWithExemption(() async {
      // 豁免窗口开启 → 既不被 SessionGuard 锁，也应让 AppLockGate 跳过锁定。
      expect(LockExemption.isActive, isTrue);
      guard.onInactive();
      expect(guard.isLocked, isFalse);
      expect(locked, isFalse);
    });
    // 出窗口后 inactive 恢复锁定。
    guard.onInactive();
    expect(guard.isLocked, isTrue);
    guard.dispose();
  });
}
