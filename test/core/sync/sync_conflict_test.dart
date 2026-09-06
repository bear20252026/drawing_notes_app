// sync_conflict.dart 纯逻辑测试：冲突检测 + 裁决落计划 + 值模型。

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';

SyncSnapshot _snap(String id, int updatedAt) =>
    SyncSnapshot(id: id, updatedAt: updatedAt, size: 1);

void main() {
  group('SyncConflict 值模型', () {
    test('suggestedResolution：远端较新 → keepRemote', () {
      const c = SyncConflict(
        docId: 'a',
        localUpdatedAt: 10,
        localSize: 1,
        remoteUpdatedAt: 20,
        remoteSize: 1,
      );
      expect(c.remoteNewer, isTrue);
      expect(c.localNewer, isFalse);
      expect(c.suggestedResolution, ConflictResolution.keepRemote);
    });

    test('suggestedResolution：本地较新 → keepLocal', () {
      const c = SyncConflict(
        docId: 'a',
        localUpdatedAt: 20,
        localSize: 1,
        remoteUpdatedAt: 10,
        remoteSize: 1,
      );
      expect(c.suggestedResolution, ConflictResolution.keepLocal);
    });

    test('相等性与 hashCode', () {
      const a = SyncConflict(
        docId: 'a',
        localUpdatedAt: 1,
        localSize: 2,
        remoteUpdatedAt: 3,
        remoteSize: 4,
      );
      const b = SyncConflict(
        docId: 'a',
        localUpdatedAt: 1,
        localSize: 2,
        remoteUpdatedAt: 3,
        remoteSize: 4,
      );
      const c = SyncConflict(
        docId: 'a',
        localUpdatedAt: 9,
        localSize: 2,
        remoteUpdatedAt: 3,
        remoteSize: 4,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('detectSyncConflicts', () {
    test('两端相对基线都变更 → 冲突', () {
      final conflicts = detectSyncConflicts(
        {'a': _snap('a', 20)},
        SyncManifest(entries: {'a': _snap('a', 30)}),
        SyncManifest(entries: {'a': _snap('a', 10)}),
      );
      expect(conflicts, hasLength(1));
      expect(conflicts.single.docId, 'a');
    });

    test('仅本地变更 → 不冲突', () {
      final conflicts = detectSyncConflicts(
        {'a': _snap('a', 20)},
        SyncManifest(entries: {'a': _snap('a', 10)}),
        SyncManifest(entries: {'a': _snap('a', 10)}),
      );
      expect(conflicts, isEmpty);
    });

    test('仅远端变更 → 不冲突', () {
      final conflicts = detectSyncConflicts(
        {'a': _snap('a', 10)},
        SyncManifest(entries: {'a': _snap('a', 30)}),
        SyncManifest(entries: {'a': _snap('a', 10)}),
      );
      expect(conflicts, isEmpty);
    });

    test('基线/本地/远端缺一个 → 跳过', () {
      final conflicts = detectSyncConflicts(
        {'a': _snap('a', 20)},
        SyncManifest(entries: {'b': _snap('b', 30)}),
        SyncManifest(entries: {'a': _snap('a', 10)}),
      );
      expect(conflicts, isEmpty);
    });

    test('顺序与基线条目一致（确定性）', () {
      final conflicts = detectSyncConflicts(
        {'a': _snap('a', 20), 'b': _snap('b', 25)},
        SyncManifest(entries: {'a': _snap('a', 30), 'b': _snap('b', 35)}),
        SyncManifest(entries: {'a': _snap('a', 10), 'b': _snap('b', 10)}),
      );
      expect(conflicts.map((c) => c.docId).toList(), ['a', 'b']);
    });
  });

  group('applyConflictResolutions', () {
    SyncPlan makePlan(List<SyncOperation> ops) => SyncPlan(operations: ops);

    test('空裁决 → 返回原计划（引用相同）', () {
      final plan = makePlan([
        SyncOperation(kind: SyncOperationKind.upload, id: 'a'),
      ]);
      final conflicts = [
        const SyncConflict(
          docId: 'a',
          localUpdatedAt: 1,
          localSize: 1,
          remoteUpdatedAt: 2,
          remoteSize: 1,
        ),
      ];
      expect(applyConflictResolutions(plan, conflicts, const {}), same(plan));
    });

    test('keepLocal 把 download 反转为 upload', () {
      final plan = makePlan([
        SyncOperation(kind: SyncOperationKind.download, id: 'a'),
      ]);
      final conflicts = [_conflict('a')];
      final out = applyConflictResolutions(plan, conflicts, {
        'a': ConflictResolution.keepLocal,
      });
      expect(out.operations, hasLength(1));
      expect(out.operations.single.kind, SyncOperationKind.upload);
      expect(out.operations.single.id, 'a');
    });

    test('keepRemote 把 upload 反转为 download', () {
      final plan = makePlan([
        SyncOperation(kind: SyncOperationKind.upload, id: 'a'),
      ]);
      final conflicts = [_conflict('a')];
      final out = applyConflictResolutions(plan, conflicts, {
        'a': ConflictResolution.keepRemote,
      });
      expect(out.operations.single.kind, SyncOperationKind.download);
    });

    test('keepBoth 视为主版本 → 强制 upload', () {
      final plan = makePlan([
        SyncOperation(kind: SyncOperationKind.download, id: 'a'),
      ]);
      final conflicts = [_conflict('a')];
      final out = applyConflictResolutions(plan, conflicts, {
        'a': ConflictResolution.keepBoth,
      });
      expect(out.operations.single.kind, SyncOperationKind.upload);
    });

    test('未裁决的冲突文档走计划原操作（LWW）', () {
      final plan = makePlan([
        SyncOperation(kind: SyncOperationKind.upload, id: 'a'),
        SyncOperation(kind: SyncOperationKind.download, id: 'b'),
      ]);
      final conflicts = [_conflict('a'), _conflict('b')];
      final out = applyConflictResolutions(plan, conflicts, {
        'a': ConflictResolution.keepLocal,
      });
      // b 未裁决 → 保持 download；a → upload（原即 upload）。
      expect(out.operations, hasLength(2));
      final byId = {for (final op in out.operations) op.id: op.kind};
      expect(byId['a'], SyncOperationKind.upload);
      expect(byId['b'], SyncOperationKind.download);
    });

    test('被裁决但计划无操作 → 补充强制操作', () {
      final plan = makePlan([]); // 两端相等被忽略，无操作
      final conflicts = [_conflict('a')];
      final out = applyConflictResolutions(plan, conflicts, {
        'a': ConflictResolution.keepRemote,
      });
      expect(out.operations.single.kind, SyncOperationKind.download);
    });

    test('输出确定性排序 deleteRemote → upload → download', () {
      final plan = makePlan([
        SyncOperation(kind: SyncOperationKind.download, id: 'b'),
        SyncOperation(kind: SyncOperationKind.upload, id: 'a'),
        SyncOperation(kind: SyncOperationKind.deleteRemote, id: 'c'),
      ]);
      final conflicts = [_conflict('a'), _conflict('b')];
      final out = applyConflictResolutions(plan, conflicts, {
        'a': ConflictResolution.keepLocal,
      });
      expect(out.operations.map((op) => op.kind).toList(), [
        SyncOperationKind.deleteRemote,
        SyncOperationKind.upload,
        SyncOperationKind.download,
      ]);
      expect(out.operations.map((op) => op.id).toList(), ['c', 'a', 'b']);
    });
  });
}

SyncConflict _conflict(String id) => SyncConflict(
  docId: id,
  localUpdatedAt: 20,
  localSize: 1,
  remoteUpdatedAt: 30,
  remoteSize: 1,
);
