// 会话级机密统一清理注册表（session_secrets.dart）单测：
// 装载（register/liveCount）/ 清零语义（clearAll 后字节材料全 0）/
// 单个持有者抛错不阻断其他持有者 / 幂等。

import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用持有者：口令（String，仅移出）+ DEK 字节（fill(0) 后移出），
/// clearAllSessionSecrets 语义对齐 StorageService（幂等、永不抛错）。
class _FakeHolder implements SessionSecretsHolder {
  _FakeHolder({this.throwOnClear = false});

  final bool throwOnClear;
  final Map<String, String> passwords = {};
  final Map<String, Uint8List> deks = {};
  int clearCount = 0;

  @override
  void clearAllSessionSecrets() {
    clearCount++;
    if (throwOnClear) throw StateError('清理失败');
    for (final dek in deks.values) {
      dek.fillRange(0, dek.length, 0);
    }
    deks.clear();
    passwords.clear();
  }
}

void main() {
  tearDown(() {
    // 注册表是静态的：每个用例结束后清空，避免用例间串扰。
    SessionSecrets.clearAll();
  });

  test('register 后 liveCount 计入存活持有者', () {
    final before = SessionSecrets.liveCount;
    final holder = _FakeHolder()..passwords['doc'] = 'pw';

    SessionSecrets.register(holder);

    expect(SessionSecrets.liveCount, before + 1);
  });

  test('clearAll 清空全部存活持有者的口令（移出即不可达）', () {
    final h1 = _FakeHolder()..passwords['a'] = 'pw-a';
    final h2 = _FakeHolder()..passwords['b'] = 'pw-b';
    SessionSecrets.register(h1);
    SessionSecrets.register(h2);

    SessionSecrets.clearAll();

    expect(h1.passwords, isEmpty);
    expect(h2.passwords, isEmpty);
    expect(h1.clearCount, 1);
    expect(h2.clearCount, 1);
  });

  test('clearAll 后 DEK 字节材料全 0（D-2 清零模式）', () {
    final holder = _FakeHolder();
    final dek = Uint8List.fromList([1, 2, 3, 250, 255]);
    holder.deks['doc'] = dek;
    SessionSecrets.register(holder);

    SessionSecrets.clearAll();

    expect(dek, everyElement(0), reason: '字节机密必须 fill(0) 后再移出');
    expect(holder.deks, isEmpty);
  });

  test('单个持有者清理抛错不阻断其他持有者（各自 try/catch）', () {
    final bad = _FakeHolder(throwOnClear: true);
    final good = _FakeHolder()..passwords['x'] = 'pw';
    SessionSecrets.register(bad);
    SessionSecrets.register(good);

    SessionSecrets.clearAll();

    expect(bad.clearCount, 1, reason: '抛错者也被调用过一次');
    expect(good.passwords, isEmpty, reason: '前序抛错不影响后续清理');
  });

  test('clearAll 幂等：连续调用不抛错、不重复清空已空状态', () {
    final holder = _FakeHolder()..passwords['a'] = 'pw';
    SessionSecrets.register(holder);

    SessionSecrets.clearAll();
    SessionSecrets.clearAll();

    expect(holder.clearCount, 2);
    expect(holder.passwords, isEmpty);
  });

  test('clearAll 入口对抛错的持有者整体 returnsNormally（AppLockGate 联动不冒错）', () {
    SessionSecrets.register(_FakeHolder(throwOnClear: true));

    // 模拟 AppLockGate.hidden 联动路径：任一持有者抛错都不得向外传播。
    expect(SessionSecrets.clearAll, returnsNormally);
  });
}
