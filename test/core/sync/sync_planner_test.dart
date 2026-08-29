import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';

SyncSnapshot _s(String id, int t, {int size = 100}) =>
    SyncSnapshot(id: id, updatedAt: t, size: size);

void main() {
  const planner = SyncPlanner();

  group('SyncPlanner 基本流向', () {
    test('仅本地新文档 → upload', () {
      final local = SyncManifest(entries: {'a': _s('a', 1000)});
      final remote = const SyncManifest();
      final plan = planner.plan(local, remote);
      expect(plan.operations, [const SyncOperation(kind: SyncOperationKind.upload, id: 'a')]);
      expect(plan.uploadCount, 1);
      expect(plan.downloadCount, 0);
      expect(plan.deleteCount, 0);
    });

    test('仅远端 → download', () {
      final local = const SyncManifest();
      final remote = SyncManifest(entries: {'b': _s('b', 1000)});
      final plan = planner.plan(local, remote);
      expect(plan.operations, [const SyncOperation(kind: SyncOperationKind.download, id: 'b')]);
      expect(plan.downloadCount, 1);
    });

    test('本地较新 → upload', () {
      final local = SyncManifest(entries: {'a': _s('a', 2000)});
      final remote = SyncManifest(entries: {'a': _s('a', 1000)});
      final plan = planner.plan(local, remote);
      expect(plan.operations, [const SyncOperation(kind: SyncOperationKind.upload, id: 'a')]);
    });

    test('远端较新 → download', () {
      final local = SyncManifest(entries: {'a': _s('a', 1000)});
      final remote = SyncManifest(entries: {'a': _s('a', 3000)});
      final plan = planner.plan(local, remote);
      expect(plan.operations, [const SyncOperation(kind: SyncOperationKind.download, id: 'a')]);
    });

    test('同 updatedAt → 忽略（无操作）', () {
      final local = SyncManifest(entries: {'a': _s('a', 1000)});
      final remote = SyncManifest(entries: {'a': _s('a', 1000)});
      final plan = planner.plan(local, remote);
      expect(plan.operations, isEmpty);
    });
  });

  group('SyncPlanner 墓碑（删除同步）', () {
    test('local.deletedIds 含 id 且远端存在、本地清单已不含 → deleteRemote', () {
      final local = SyncManifest(
        entries: {'keep': _s('keep', 1000)},
        deletedIds: const {'gone'},
      );
      final remote = SyncManifest(entries: {
        'keep': _s('keep', 1000),
        'gone': _s('gone', 1000),
      });
      final plan = planner.plan(local, remote);
      expect(plan.deleteCount, 1);
      expect(plan.operations.first.kind, SyncOperationKind.deleteRemote);
      expect(plan.operations.first.id, 'gone');
    });

    test('墓碑 id 远端已不存在 → 无操作', () {
      final local = SyncManifest(entries: const {}, deletedIds: const {'gone'});
      final remote = const SyncManifest();
      final plan = planner.plan(local, remote);
      expect(plan.operations, isEmpty);
    });

    test('墓碑 id 本地清单仍持有（未真正删除）→ 不按墓碑处理，正常比对', () {
      final local = SyncManifest(
        entries: {'a': _s('a', 2000)},
        deletedIds: const {'a'},
      );
      final remote = SyncManifest(entries: {'a': _s('a', 1000)});
      // 本地仍持有 → 走"两者都有"分支，本地较新 → upload
      final plan = planner.plan(local, remote);
      expect(plan.deleteCount, 0);
      expect(plan.uploadCount, 1);
    });
  });

  group('SyncPlanner 操作顺序确定性', () {
    test('先 deleteRemote，再按 id 排序的 upload/download', () {
      final local = SyncManifest(entries: {
        'z_up': _s('z_up', 2000),
        'a_up': _s('a_up', 2000),
      }, deletedIds: const {'del1', 'del2'});
      final remote = SyncManifest(entries: {
        'z_up': _s('z_up', 1000),
        'a_up': _s('a_up', 1000),
        'del1': _s('del1', 1000),
        'del2': _s('del2', 1000),
        'm_down': _s('m_down', 5000),
        'b_down': _s('b_down', 5000),
      });
      final plan = planner.plan(local, remote);
      final kinds = plan.operations.map((o) => o.kind).toList();
      final ids = plan.operations.map((o) => o.id).toList();

      // deleteRemote 在前
      expect(kinds.take(2), [SyncOperationKind.deleteRemote, SyncOperationKind.deleteRemote]);
      // 然后 upload（按 id 排序）
      expect(ids[2], 'a_up');
      expect(ids[3], 'z_up');
      // 然后 download（按 id 排序）
      expect(ids[4], 'b_down');
      expect(ids[5], 'm_down');
    });
  });

  group('SyncPlanner 空清单', () {
    test('双方空清单 → 空计划', () {
      final plan = planner.plan(const SyncManifest(), const SyncManifest());
      expect(plan.operations, isEmpty);
    });

    test('空 local + 远端有 → 全部 download', () {
      final remote = SyncManifest(entries: {
        'x': _s('x', 1000),
        'y': _s('y', 1000),
      });
      final plan = planner.plan(const SyncManifest(), remote);
      expect(plan.downloadCount, 2);
      expect(plan.uploadCount, 0);
    });
  });

  group('SyncSnapshot 值语义', () {
    test('== / hashCode', () {
      const a = SyncSnapshot(id: 'a', updatedAt: 1, size: 2);
      const b = SyncSnapshot(id: 'a', updatedAt: 1, size: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith', () {
      const a = SyncSnapshot(id: 'a', updatedAt: 1, size: 2);
      final b = a.copyWith(updatedAt: 99);
      expect(b.id, 'a');
      expect(b.updatedAt, 99);
      expect(b.size, 2);
    });
  });

  group('SyncManifest 序列化', () {
    test('toJson/fromJson 往返（map 形式 entries）', () {
      final m = SyncManifest(
        entries: {'a': _s('a', 1000, size: 50), 'b': _s('b', 2000, size: 80)},
        deletedIds: const {'c'},
      );
      final json = m.toJson();
      final restored = SyncManifest.fromJson(json);
      expect(restored.entries, m.entries);
      expect(restored.deletedIds, m.deletedIds);
    });

    test('fromJson 兼容数组形式 entries', () {
      final json = {
        'entries': [
          {'id': 'a', 'updatedAt': 1000, 'size': 50},
          {'id': 'b', 'updatedAt': 2000, 'size': 80},
        ],
        'deletedIds': ['c'],
      };
      final m = SyncManifest.fromJson(json);
      expect(m.entries['a']?.updatedAt, 1000);
      expect(m.entries['b']?.size, 80);
      expect(m.deletedIds, {'c'});
    });

    test('fromJson 缺失 deletedIds 兼容为空集', () {
      final json = {
        'entries': [
          {'id': 'a', 'updatedAt': 1000},
        ],
      };
      final m = SyncManifest.fromJson(json);
      expect(m.deletedIds, isEmpty);
      expect(m.entries['a']?.size, 0); // 缺失 size 默认 0
    });
  });

  group('SyncOperation 值语义', () {
    test('== / hashCode', () {
      const a = SyncOperation(kind: SyncOperationKind.upload, id: 'x');
      const b = SyncOperation(kind: SyncOperationKind.upload, id: 'x');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('不同 kind → 不等', () {
      const a = SyncOperation(kind: SyncOperationKind.upload, id: 'x');
      const b = SyncOperation(kind: SyncOperationKind.download, id: 'x');
      expect(a == b, isFalse);
    });
  });
}
