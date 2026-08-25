// editor_core——DocumentLockManager 测试（单文档编辑锁+.lock 文件检测）。

import 'package:test/test.dart';
import 'package:editor_core/src/domain/document_lock.dart';

void main() {
  group('DocumentLockManager', () {
    late DocumentLockManager manager;

    setUp(() {
      manager = DocumentLockManager(nodeId: 'test-node');
    });

    test('initial status is unlocked', () {
      expect(manager.getStatus('doc1'), LockStatus.unlocked);
    });

    test('tryLock succeeds for unlocked document', () {
      expect(manager.tryLock('doc1'), true);
      expect(manager.getStatus('doc1'), LockStatus.locked);
    });

    test('tryLock succeeds for document already locked by same node', () {
      manager.tryLock('doc1');
      expect(manager.tryLock('doc1'), true);
      expect(manager.getStatus('doc1'), LockStatus.locked);
    });

    test('unlock succeeds for document locked by same node', () {
      manager.tryLock('doc1');
      expect(manager.unlock('doc1'), true);
      expect(manager.getStatus('doc1'), LockStatus.unlocked);
    });

    test('unlock returns true for already unlocked document', () {
      expect(manager.unlock('doc1'), true);
    });

    test('getLockInfo returns correct info', () {
      manager.tryLock('doc1');

      final info = manager.getLockInfo('doc1');
      expect(info, isNotNull);
      expect(info!.docId, 'doc1');
      expect(info.ownerId, 'test-node');
      expect(info.isExpired, false);
    });

    test('getLockInfo returns null for unlocked document', () {
      expect(manager.getLockInfo('doc1'), null);
    });

    test('getActiveLocks returns all locks', () {
      manager.tryLock('doc1');
      manager.tryLock('doc2');
      manager.tryLock('doc3');

      final locks = manager.getActiveLocks();
      expect(locks.length, 3);
    });

    test('getMyLocks returns only locks owned by current node', () {
      manager.tryLock('doc1');
      manager.tryLock('doc2');

      final myLocks = manager.getMyLocks();
      expect(myLocks.length, 2);
      expect(myLocks.every((l) => l.ownerId == 'test-node'), true);
    });

    test('clear removes all locks', () {
      manager.tryLock('doc1');
      manager.tryLock('doc2');

      manager.clear();
      expect(manager.getStatus('doc1'), LockStatus.unlocked);
      expect(manager.getStatus('doc2'), LockStatus.unlocked);
    });

    test('generateLockFileContent produces valid JSON', () {
      manager.tryLock('doc1');

      final content = manager.generateLockFileContent('doc1');
      expect(content.contains('"docId": "doc1"'), true);
      expect(content.contains('"ownerId": "test-node"'), true);
      expect(content.contains('"lockedAt"'), true);
      expect(content.contains('"timeout"'), true);
    });

    test('parseLockFileContent parses correctly', () {
      const content = '''
{
  "docId": "doc1",
  "ownerId": "other-node",
  "lockedAt": "2026-08-24T12:00:00.000",
  "timeout": 1800
}''';

      final info = manager.parseLockFileContent('doc1', content);
      expect(info, isNotNull);
      expect(info!.docId, 'doc1');
      expect(info.ownerId, 'other-node');
      expect(info.timeout, const Duration(seconds: 1800));
    });

    test('parseLockFileContent returns null for invalid content', () {
      expect(manager.parseLockFileContent('doc1', 'invalid'), null);
      expect(manager.parseLockFileContent('doc1', '{}'), null);
    });

    test('metadata is stored correctly', () {
      manager.tryLock('doc1', metadata: {'user': 'alice', 'device': 'phone'});

      final info = manager.getLockInfo('doc1');
      expect(info!.metadata['user'], 'alice');
      expect(info.metadata['device'], 'phone');
    });
  });
}
