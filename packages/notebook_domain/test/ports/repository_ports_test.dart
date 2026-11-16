// notebook_domain 端口契约测试（L-9 收口 2026-11-16）。
//
// 背景：notebook_domain 是纯 Dart 安全域的端口契约层（3 个 abstract
// interface class），adapter 尚未接线（C-07 续批）——此前零测试。本测试
// 用 fake 实现钉住端口契约：①签名可满足（实现方无需依赖具体存储）；
// ②notebookId 隔离语义（媒体按本隔离、密钥按本清除——I-009/R-05）；
// ③纯 Dart（不触 Widget/Platform/File）。契约变更（改签名/删方法）即红。

import 'package:notebook_domain/notebook_domain.dart';
import 'package:test/test.dart';

/// 笔记本仓库 fake：按 id 存认证载荷，lock 清除（R-05 锁定阻断语义）。
class _FakeNotebookRepository implements NotebookRepositoryPort {
  final Map<String, List<int>> _payloads = {};
  final Set<String> _locked = {};

  @override
  Future<String> open(String notebookId) async {
    if (_locked.contains(notebookId)) {
      throw StateError('笔记本已锁定: $notebookId');
    }
    return 'handle:$notebookId';
  }

  @override
  Future<void> save(String notebookId, List<int> authenticatedPayload) async {
    _payloads[notebookId] = List<int>.from(authenticatedPayload);
    _locked.remove(notebookId);
  }

  @override
  Future<void> lock(String notebookId) async {
    _locked.add(notebookId);
    _payloads.remove(notebookId); // 清除 scoped 载荷。
  }
}

/// 媒体仓库 fake：按 (notebookId, mediaId) 隔离存储（I-009 所有者校验语义）。
class _FakeMediaRepository implements MediaRepositoryPort {
  final Map<String, Map<String, List<int>>> _byNotebook = {};
  int _seq = 0;

  @override
  Future<List<int>> read(String notebookId, String mediaId) async {
    final bucket = _byNotebook[notebookId];
    final data = bucket?[mediaId];
    if (data == null) throw StateError('媒体不存在或跨本: $notebookId/$mediaId');
    return List<int>.from(data);
  }

  @override
  Future<String> store(String notebookId, List<int> plain) async {
    final id = 'media-${_seq++}';
    (_byNotebook[notebookId] ??= {})[id] = List<int>.from(plain);
    return id;
  }
}

/// 密钥提供 fake：passphrase+salt 确定性派生（同输入同输出）。
class _FakeKeyProvider implements KeyProviderPort {
  @override
  Future<List<int>> deriveKey(String passphrase, List<int> salt) async {
    // 简化确定性派生（契约测试不验证密码学强度，只验证签名与隔离）。
    return List<int>.generate(
      32,
      (i) => (passphrase.codeUnitAt(i % passphrase.length) + salt[i % salt.length]) & 0xFF,
    );
  }
}

void main() {
  group('NotebookRepositoryPort 契约', () {
    test('open/save/lock 往返：保存后可打开，锁定后拒绝', () async {
      final repo = _FakeNotebookRepository();
      await repo.save('nb-1', [1, 2, 3]);
      expect(await repo.open('nb-1'), 'handle:nb-1');
      await repo.lock('nb-1');
      await expectLater(repo.open('nb-1'), throwsStateError);
    });

    test('lock 按本隔离：锁 nb-1 不影响 nb-2（R-05 scoped）', () async {
      final repo = _FakeNotebookRepository();
      await repo.save('nb-1', [1]);
      await repo.save('nb-2', [2]);
      await repo.lock('nb-1');
      expect(await repo.open('nb-2'), 'handle:nb-2');
    });
  });

  group('MediaRepositoryPort 契约（notebookId 隔离 I-009）', () {
    test('store/read 往返：同本可读', () async {
      final media = _FakeMediaRepository();
      final id = await media.store('nb-a', [9, 8, 7]);
      expect(await media.read('nb-a', id), [9, 8, 7]);
    });

    test('跨本读取拒绝：nb-a 的媒体在 nb-b 不可读（所有者校验）', () async {
      final media = _FakeMediaRepository();
      final id = await media.store('nb-a', [9, 8, 7]);
      await expectLater(media.read('nb-b', id), throwsStateError);
    });
  });

  group('KeyProviderPort 契约', () {
    test('deriveKey 确定性：同 passphrase+salt 同输出（32B）', () async {
      final kp = _FakeKeyProvider();
      final k1 = await kp.deriveKey('pw', [1, 2, 3, 4]);
      final k2 = await kp.deriveKey('pw', [1, 2, 3, 4]);
      expect(k1, k2);
      expect(k1.length, 32);
    });

    test('不同 salt 派生不同密钥（salt 绑定）', () async {
      final kp = _FakeKeyProvider();
      final k1 = await kp.deriveKey('pw', [1, 2, 3, 4]);
      final k2 = await kp.deriveKey('pw', [5, 6, 7, 8]);
      expect(k1, isNot(equals(k2)));
    });
  });
}