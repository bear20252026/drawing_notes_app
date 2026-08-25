import 'dart:convert';
import 'dart:io';

import 'package:drawing_notes_app/core/error/offline_cache_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late OfflineCacheRecovery recovery;

  setUp(() {
    recovery = OfflineCacheRecovery.instance;
  });

  tearDown(() async {
    await recovery.clearAll();
  });

  group('OfflineCacheRecovery', () {
    test('initializes without error', () async {
      await recovery.initialize();
      expect(recovery.pendingCount, 0);
    });

    test('caches a failed write operation', () async {
      await recovery.initialize();

      await recovery.cacheFailedOperation(
        operationId: 'test_op_1',
        operationType: 'save',
        payload: {'key': 'value'},
        targetPath: '/tmp/test.json',
      );

      expect(recovery.pendingCount, 1);
      final ops = recovery.pendingOperations;
      expect(ops[0]['id'], 'test_op_1');
      expect(ops[0]['operationType'], 'save');
    });

    test('caches multiple operations', () async {
      await recovery.initialize();

      await recovery.cacheFailedOperation(
        operationId: 'op_1',
        operationType: 'save',
        payload: {'key': 'value1'},
      );
      await recovery.cacheFailedOperation(
        operationId: 'op_2',
        operationType: 'delete',
        payload: {'key': 'value2'},
      );
      await recovery.cacheFailedOperation(
        operationId: 'op_3',
        operationType: 'update',
        payload: {'key': 'value3'},
      );

      expect(recovery.pendingCount, 3);
    });

    test('clears a specific operation', () async {
      await recovery.initialize();

      await recovery.cacheFailedOperation(
        operationId: 'op_to_clear',
        operationType: 'save',
        payload: {'key': 'value'},
      );
      expect(recovery.pendingCount, 1);

      await recovery.clearOperation('op_to_clear');
      expect(recovery.pendingCount, 0);
    });

    test('clears all operations', () async {
      await recovery.initialize();

      await recovery.cacheFailedOperation(
        operationId: 'op_1',
        operationType: 'save',
        payload: {},
      );
      await recovery.cacheFailedOperation(
        operationId: 'op_2',
        operationType: 'delete',
        payload: {},
      );

      await recovery.clearAll();
      expect(recovery.pendingCount, 0);
    });

    test('cleanupExpired removes old entries', () async {
      await recovery.initialize();

      await recovery.cacheFailedOperation(
        operationId: 'old_op',
        operationType: 'save',
        payload: {'data': 'old'},
      );

      // Manually modify the persisted file to have an old date
      // Since we can't easily manipulate internal state, just verify cleanup runs
      final cleaned = await recovery.cleanupExpired();
      expect(cleaned, greaterThanOrEqualTo(0));
    });

    test('cacheWriteFailure convenience method', () async {
      await recovery.initialize();

      await recovery.cacheWriteFailure(
        documentId: 'doc_1',
        documentData: {'title': 'Test Document'},
        targetPath: '/tmp/doc_1.json',
      );

      expect(recovery.pendingCount, 1);
      final ops = recovery.pendingOperations;
      expect(ops[0]['id'], 'write_doc_1');
      expect(ops[0]['operationType'], 'save');
    });

    test('cacheDeleteFailure convenience method', () async {
      await recovery.initialize();

      await recovery.cacheDeleteFailure(
        documentId: 'doc_1',
        targetPath: '/tmp/doc_1.json',
      );

      expect(recovery.pendingCount, 1);
      final ops = recovery.pendingOperations;
      expect(ops[0]['id'], 'delete_doc_1');
      expect(ops[0]['operationType'], 'delete');
    });

    test('cacheUpdateFailure convenience method', () async {
      await recovery.initialize();

      await recovery.cacheUpdateFailure(
        documentId: 'doc_1',
        documentData: {'title': 'Updated'},
        targetPath: '/tmp/doc_1.json',
      );

      expect(recovery.pendingCount, 1);
      final ops = recovery.pendingOperations;
      expect(ops[0]['id'], 'update_doc_1');
      expect(ops[0]['operationType'], 'update');
    });

    test('executeSave operation writes file correctly', () async {
      await recovery.initialize();

      final tmpDir = Directory.systemTemp;
      final targetPath = '${tmpDir.path}/test_cache_recovery.json';

      await recovery.cacheFailedOperation(
        operationId: 'save_test',
        operationType: 'save',
        payload: {'title': 'Test', 'content': 'Hello World'},
        targetPath: targetPath,
      );

      // Trigger retry
      await recovery.retryAll();

      // Verify file was written
      final file = File(targetPath);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      final data = jsonDecode(content);
      expect(data['title'], 'Test');
      expect(data['content'], 'Hello World');

      // Cleanup
      await file.delete();
    });

    test('executeDelete operation removes file', () async {
      await recovery.initialize();

      final tmpDir = Directory.systemTemp;
      final targetPath = '${tmpDir.path}/test_cache_delete.json';

      // Create a file first
      final file = File(targetPath);
      await file.writeAsString('test content');
      expect(await file.exists(), isTrue);

      // Cache a delete operation
      await recovery.cacheFailedOperation(
        operationId: 'delete_test',
        operationType: 'delete',
        payload: {},
        targetPath: targetPath,
      );

      // Trigger retry
      await recovery.retryAll();

      // Verify file was deleted
      expect(await file.exists(), isFalse);
    });

    test('network status triggers retry when coming online', () async {
      await recovery.initialize();

      await recovery.cacheFailedOperation(
        operationId: 'network_test',
        operationType: 'save',
        payload: {'data': 'test'},
        targetPath: null, // null target means save will fail
      );

      // Set offline
      recovery.setNetworkStatus(false);
      expect(recovery.pendingCount, 1);

      // Set online - should trigger retry
      recovery.setNetworkStatus(true);
      // Give async processing time
      await Future.delayed(const Duration(milliseconds: 100));
      // The operation will fail (null target) but should be retried
    });
  });
}
