import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 用户需求——EncryptionAccessService 加密访问控制测试（纯逻辑——不搞崩）。
void main() {
  test('初始状态：无加密（打开不需要密码）', () {
    const state = EncryptionAccessState();
    expect(state.appEncrypted, false);
    expect(state.appUnlocked, false);
    // 打开软件/笔记——不需要密码。
    expect(const EncryptionAccessService().requiresPassword(state), false);
    expect(
      const EncryptionAccessService().requiresPassword(state, objectId: 'n1'),
      false,
    );
  });

  test('fromScope：从加密对象选择构建（用户选择 app/note）', () {
    var scope = const EncryptionScopeService();
    scope = scope.setNoteEncrypted('n2', true);
    final state = EncryptionAccessService.fromScope(scope);
    expect(state.encryptedIds, {'n2'});
    expect(state.appEncrypted, false);
  });

  test('requiresPassword：app 级加密——打开软件需密码', () {
    const state = EncryptionAccessState(appEncrypted: true);
    const service = EncryptionAccessService();
    expect(service.requiresPassword(state), true); // 打开软件需密码。
    expect(service.requiresPassword(state, objectId: 'n1'), true); // 打开笔记也需。
  });

  test('unlockApp：解锁应用——再次打开不需要密码（本次会话）', () {
    const service = EncryptionAccessService();
    var state = const EncryptionAccessState(appEncrypted: true);
    expect(service.requiresPassword(state), true);
    state = service.unlockApp(state);
    expect(state.appUnlocked, true);
    expect(service.requiresPassword(state), false);
    expect(service.canAccess(state), true);
  });

  test('requiresPassword：note 级加密——打开单个笔记需密码', () {
    const state = EncryptionAccessState(encryptedIds: {'n2'});
    const service = EncryptionAccessService();
    expect(service.requiresPassword(state, objectId: 'n2'), true); // 加密笔记。
    expect(service.requiresPassword(state, objectId: 'n1'), false); // 未加密笔记。
    expect(service.requiresPassword(state), false); // 软件本身不加密。
  });

  test('unlockNote：解锁单个笔记——可访问', () {
    const service = EncryptionAccessService();
    var state = const EncryptionAccessState(encryptedIds: {'n2'});
    state = service.unlockNote(state, 'n2');
    expect(service.canAccess(state, objectId: 'n2'), true);
    expect(service.canAccess(state, objectId: 'n1'), true); // 未加密一直可访问。
  });

  test('lock：锁定——清除解锁状态（再次打开需密码——用户需求）', () {
    const service = EncryptionAccessService();
    var state = const EncryptionAccessState(appEncrypted: true);
    state = service.unlockApp(state);
    expect(service.requiresPassword(state), false);
    state = service.lock(state);
    expect(state.appUnlocked, false);
    expect(state.unlockedIds, isEmpty);
    expect(service.requiresPassword(state), true); // 再次打开需密码。
  });

  test('canAccess：访问控制（app/note 已解锁）', () {
    const state = EncryptionAccessState(encryptedIds: {'n2'});
    const service = EncryptionAccessService();
    expect(service.canAccess(state, objectId: 'n2'), false); // 未解锁。
    expect(service.canAccess(state, objectId: 'n1'), true);
    expect(service.canAccess(state), true); // 软件未加密。
  });

  test('EncryptionAccessState：copyWith 不可变', () {
    const state = EncryptionAccessState();
    final updated = state.copyWith(appEncrypted: true, appUnlocked: true);
    expect(state.appEncrypted, false); // 原实例不变。
    expect(updated.appEncrypted, true);
    expect(updated.appUnlocked, true);
  });
}
