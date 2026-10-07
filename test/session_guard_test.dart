import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/session_guard.dart';

/// 会话守卫单测（专家审计最优先③——2026-08-16）：
/// inactive 立即锁定 + 文件选择器豁免 + resume 再认证 + unlock。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onInactive：立即锁定并触发 onLock 回调', () {
    var locked = false;
    var lockCalls = 0;
    final guard = SessionGuard(
      onLock: () {
        locked = true;
        lockCalls++;
      },
    );
    expect(guard.isLocked, isFalse);
    guard.onInactive();
    expect(guard.isLocked, isTrue);
    expect(locked, isTrue);
    expect(lockCalls, 1);
    // 重复 inactive 不重复锁定。
    guard.onInactive();
    expect(lockCalls, 1);
  });

  test('文件选择器运行中：inactive 豁免（防导入/导出误锁）', () {
    var locked = false;
    final guard = SessionGuard(onLock: () => locked = true);
    guard.setFilePickerActive(true);
    guard.onInactive();
    expect(guard.isLocked, isFalse);
    expect(locked, isFalse);
    // 选择器结束后 inactive 恢复锁定。
    guard.setFilePickerActive(false);
    guard.onInactive();
    expect(guard.isLocked, isTrue);
  });

  test('onResume：已锁定触发再认证回调', () {
    var reauth = false;
    final guard = SessionGuard(onReauthenticateRequired: () => reauth = true);
    guard.onInactive(); // 锁定
    guard.onResume();
    expect(reauth, isTrue);
  });

  test('unlock：重新认证后重置锁定状态', () {
    var reauth = false;
    final guard = SessionGuard(onReauthenticateRequired: () => reauth = true);
    guard.onInactive();
    guard.unlock();
    expect(guard.isLocked, isFalse);
    // 解锁后 resume 不再触发再认证。
    guard.onResume();
    expect(reauth, isFalse);
  });

  test('dispose：释放生命周期监听器', () {
    final guard = SessionGuard();
    guard.dispose();
    expect(guard.isLocked, isFalse);
  });

  test('runWithExemption：抛异常也不泄漏豁免（P0 修复）', () async {
    var locked = false;
    final guard = SessionGuard(onLock: () => locked = true);
    await expectLater(
      guard.runWithExemption(() => throw StateError('picker crashed')),
      throwsStateError,
    );
    // 豁免已复位：inactive 必须锁定。
    guard.onInactive();
    expect(guard.isLocked, isTrue);
    expect(locked, isTrue);
  });

  test('runWithExemption：嵌套豁免计数配对，不提前关闭', () async {
    final guard = SessionGuard(onLock: () {});
    await guard.runWithExemption(() async {
      guard.setFilePickerActive(true);
      guard.setFilePickerActive(false);
      // 外层豁免仍有效。
      guard.onInactive();
      expect(guard.isLocked, isFalse);
    });
    // 全部退出后恢复锁定。
    guard.onInactive();
    expect(guard.isLocked, isTrue);
  });

  test('P2-1 续项：豁免窗口关闭时人未回前台，等满宽限落锁（不再等下一次 onInactive）', () async {
    var locked = false;
    var lockCalls = 0;
    final guard = SessionGuard(
      onLock: () {
        locked = true;
        lockCalls++;
      },
      graceDuration: const Duration(milliseconds: 20),
      // 模拟「对话框期间窗口 inactive，关闭后焦点迟迟没回来」。
      lifecycleStateProvider: () => AppLifecycleState.inactive,
    );
    guard.setFilePickerActive(true);
    guard.onInactive(); // 豁免期失焦：不锁（防选择器假锁），起看门表。
    expect(guard.isLocked, isFalse);
    guard.setFilePickerActive(false); // 窗口关闭，人未回前台。
    expect(guard.isLocked, isFalse, reason: '宽限内不就地置锁——焦点交接无闪断');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(guard.isLocked, isTrue, reason: '等满宽限没人回来 = 离席，必须落锁');
    expect(locked, isTrue);
    expect(lockCalls, 1);
    guard.dispose();
  });

  test('P2-1 续项：宽限内回到前台，撤销挂起判定（正常导出/导入路径无假锁）', () async {
    var locked = false;
    var state = AppLifecycleState.inactive;
    final guard = SessionGuard(
      onLock: () => locked = true,
      graceDuration: const Duration(milliseconds: 30),
      lifecycleStateProvider: () => state,
    );
    guard.setFilePickerActive(true);
    guard.onInactive();
    guard.setFilePickerActive(false); // 窗口关闭，人未回。
    state = AppLifecycleState.resumed; // 焦点交接完成（宽限内）。
    guard.onResume();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(guard.isLocked, isFalse, reason: 'resumed 先于宽限到期 = 人已回来');
    expect(locked, isFalse);
    guard.dispose();
  });

  test('P2-1 续项：豁免 TTL 到点无人来读，看门表主动复核并落锁（不给宽限资格）', () async {
    LockExemption.ttlOverrideForTest = const Duration(milliseconds: 50);
    addTearDown(LockExemption.resetForTest);
    var locked = false;
    final guard = SessionGuard(
      onLock: () => locked = true,
      // TTL 到期 = 调用方漏 end / 选择器挂死，不是「人还在」——
      // 与 AppLockGate 同口径：直接落锁，不走宽限期。
      lifecycleStateProvider: () => AppLifecycleState.inactive,
    );
    guard.setFilePickerActive(true); // begin（刷新 50ms 截止）。
    guard.onInactive(); // 豁免期失焦：起看门表。
    expect(guard.isLocked, isFalse);
    // 真实时间越过 TTL ⇒ 看门表到点读 isActive ⇒ 惰性失效 + 同步通知。
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(guard.isLocked, isTrue, reason: 'TTL 到期必须主动落锁，不再依赖下一次 onInactive');
    expect(locked, isTrue);
    guard.dispose();
  });
}
