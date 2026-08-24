import 'package:test/test.dart';

import 'package:notebook_domain/notebook_domain.dart';

/// 专家批次 D（2026-08-18）：NotebookSession 测试——
/// 状态机、锁定/解锁、过期、权限校验（R-05 锁定阻断）。
void main() {
  late NotebookSession session;
  late LockPolicy policy;

  setUp(() {
    policy = const LockPolicy(autoLockDuration: Duration(seconds: 1));
    session = NotebookSession(notebookId: 'nb1', lockPolicy: policy);
  });

  tearDown(() {
    session.dispose();
  });

  test('初始状态：uninitialized', () {
    expect(session.state, SessionState.uninitialized);
    expect(session.isUnlocked, false);
    expect(session.keyHandle, isNull);
  });

  test('unlock：解锁后状态 unlocked + KeyHandle 可用', () {
    session.unlock([1, 2, 3, 4]);
    expect(session.state, SessionState.unlocked);
    expect(session.isUnlocked, true);
    expect(session.keyHandle, isNotNull);
    expect(session.keyHandle!.keyBytes, [1, 2, 3, 4]);
  });

  test('lock：锁定后清除 KeyHandle（R-05 锁定阻断）', () {
    session.unlock([1, 2, 3, 4]);
    session.lock();
    expect(session.state, SessionState.locked);
    expect(session.isLocked, true);
    expect(session.keyHandle, isNull); // R-05：锁定后密钥已清除
  });

  test('lock 后 canPerformAction 返回 false（R-05 锁定阻断编辑/保存/导出/媒体）', () {
    session.unlock([1, 2, 3, 4]);
    session.lock();
    expect(session.canPerformAction(), false);
  });

  test('unlock 后 canPerformAction 返回 true', () {
    session.unlock([1, 2, 3, 4]);
    expect(session.canPerformAction(), true);
  });

  test('checkExpiry：超时后自动锁定（expired）', () async {
    session.unlock([1, 2, 3, 4]);
    // 等待超过 autoLockDuration（1 秒）
    await Future.delayed(const Duration(milliseconds: 1100));
    final expired = session.checkExpiry();
    expect(expired, true);
    expect(session.state, SessionState.expired);
    expect(session.isLocked, true);
    expect(session.keyHandle, isNull); // 过期后密钥已清除
  });

  test('checkExpiry：未超时返回 false', () {
    session.unlock([1, 2, 3, 4]);
    final expired = session.checkExpiry();
    expect(expired, false);
    expect(session.state, SessionState.unlocked);
  });

  test('LockPolicy.isExpired：超时判定', () {
    final policy = const LockPolicy(autoLockDuration: Duration(seconds: 2));
    final past = DateTime.now().subtract(const Duration(seconds: 3));
    expect(policy.isExpired(past), true);
    final recent = DateTime.now().subtract(const Duration(seconds: 1));
    expect(policy.isExpired(recent), false);
  });

  test('LockPolicy.shortTimeout：1 分钟超时', () {
    expect(LockPolicy.shortTimeout.autoLockDuration, const Duration(minutes: 1));
  });
}
