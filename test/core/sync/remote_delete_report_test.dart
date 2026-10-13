// A3 墓碑的第一位读者：远端删除的**只读**判定（见 lib/core/sync/remote_deletes.dart）。
//
// 这一组用例守的是两条相反的方向，缺一条都会漏掉真缺陷：
//  ① 分得清「陈旧副本 / 本机有独有内容 / 无从比对」——否则下一步（跟随删除）
//     会把「本机只此一份」的画布也一起删掉；
//  ② 报告**不产生任何动作**，也绝不把「无从比对」当成「有改动」（DN-206 的
//     假红风暴在 204/206 两条里已经吃过一次）。
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/sync/remote_deletes.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';

SyncSnapshot _snap(String id, int updatedAt, [int size = 100]) =>
    SyncSnapshot(id: id, updatedAt: updatedAt, size: size);

void main() {
  List<RemoteDeleteIssue> detect({
    required Map<String, SyncSnapshot> local,
    Set<String> localDeleted = const {},
    required SyncManifest remote,
    required SyncManifest baseline,
  }) => detectRemoteDeletes(
    currentEntries: local,
    localDeletedIds: localDeleted,
    remote: remote,
    baseline: baseline,
  );

  group('A3 远端删除判定：三类分得清', () {
    test('本地相对自己的基线一字未动 ⇒ staleCopy（唯一可能无损的那一类）', () {
      final issues = detect(
        local: {'x': _snap('x', 200)},
        remote: SyncManifest(
          deletedIds: const {'x'},
          tombstones: const {
            'x': SyncTombstone(id: 'x', deletedAt: 260, baseRev: 200),
          },
        ),
        baseline: SyncManifest(entries: {'x': _snap('x', 200)}),
      );

      expect(issues.single.docId, 'x');
      expect(issues.single.kind, RemoteDeleteKind.staleCopy);
      expect(issues.single.isLossFreeToDrop, isTrue);
      // 因果锚从远端墓碑透传过来——它是下一条腿唯一能用的信息。
      expect(issues.single.tombstoneBaseRev, 200);
      expect(issues.single.tombstoneDeletedAt, 260);
    });

    test('本地相对基线改过 ⇒ localHasEdits（删除与编辑撞上，两份都得留）', () {
      final issues = detect(
        local: {'x': _snap('x', 260)},
        remote: SyncManifest(
          deletedIds: const {'x'},
          tombstones: const {
            'x': SyncTombstone(id: 'x', deletedAt: 240, baseRev: 200),
          },
        ),
        baseline: SyncManifest(entries: {'x': _snap('x', 200)}),
      );

      expect(issues.single.kind, RemoteDeleteKind.localHasEdits);
      expect(issues.single.isLossFreeToDrop, isFalse);
    });

    test('size 变了也算改过——只看时间戳会被同毫秒编辑骗过（DN-206 同口径）', () {
      final issues = detect(
        local: {'x': _snap('x', 200, 999)},
        remote: SyncManifest(deletedIds: const {'x'}),
        baseline: SyncManifest(entries: {'x': _snap('x', 200, 100)}),
      );
      expect(issues.single.kind, RemoteDeleteKind.localHasEdits);
    });

    test('本机没有这一篇的基线 ⇒ unknowable，**不得**当成「本机有改动」', () {
      // 反向锁：把「无从比对」误判成「有独有内容」会让混合版本集群升级的第一轮
      // 冒出一堆假红，并把真正无损的那一类藏起来。
      final issues = detect(
        local: {'x': _snap('x', 200)},
        remote: SyncManifest(deletedIds: const {'x'}),
        baseline: const SyncManifest(),
      );

      expect(issues.single.kind, RemoteDeleteKind.unknowable);
      expect(issues.single.isLossFreeToDrop, isFalse);
      // 旧客户端写的清单没有墓碑块 ⇒ 因果字段为 null，不抛。
      expect(issues.single.tombstoneBaseRev, isNull);
      expect(issues.single.tombstoneDeletedAt, isNull);
    });
  });

  group('A3 远端删除判定：三种不该报的情形', () {
    test('远端同时有条目又有墓碑 ⇒ 按「还活着」处理，不报', () {
      // 报错了会诱导用户去删自己正在用的东西：有条目就说明此刻云端有活副本
      // （别人重传否决了那次删除，或清单畸形）。
      final issues = detect(
        local: {'x': _snap('x', 200)},
        remote: SyncManifest(
          entries: {'x': _snap('x', 200)},
          deletedIds: const {'x'},
        ),
        baseline: SyncManifest(entries: {'x': _snap('x', 200)}),
      );
      expect(issues, isEmpty);
    });

    test('本机自己也主张删过 ⇒ 两端共识，不是分叉', () {
      final issues = detect(
        local: {'x': _snap('x', 200)},
        localDeleted: const {'x'},
        remote: SyncManifest(deletedIds: const {'x'}),
        baseline: SyncManifest(entries: {'x': _snap('x', 200)}),
      );
      expect(issues, isEmpty);
    });

    test('本机根本没有这一篇 ⇒ 无话可说', () {
      final issues = detect(
        local: const {},
        remote: SyncManifest(deletedIds: const {'x'}),
        baseline: SyncManifest(entries: {'x': _snap('x', 200)}),
      );
      expect(issues, isEmpty);
    });
  });

  test('A3 远端删除判定：输出按 id 字典序，与输入顺序无关（纯逻辑必须确定）', () {
    final issues = detect(
      local: {'zed': _snap('zed', 1), 'abc': _snap('abc', 1), 'mid': _snap('mid', 1)},
      remote: SyncManifest(deletedIds: const {'zed', 'abc', 'mid'}),
      baseline: SyncManifest(
        entries: {'zed': _snap('zed', 1), 'abc': _snap('abc', 1), 'mid': _snap('mid', 1)},
      ),
    );

    expect(issues.map((i) => i.docId), ['abc', 'mid', 'zed']);
  });
}
