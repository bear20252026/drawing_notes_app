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
}
