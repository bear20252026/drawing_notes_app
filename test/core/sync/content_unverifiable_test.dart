// M7（第三轮专家审计）：摘要缺省时「不可比」不能再当成「相同」。
//
// 缺陷形状：`digest` 是可选字段（旧客户端 / 旧清单不写），而
// `contentDiffersFrom` 在任一侧缺省时返回 false ⇒ 同 ts、同 size 的两份内容
// 被判定为「一样」，planner 的「== → 忽略」与冲突检测双双静默，分叉可以
// 永久存活（与 DN-206 同一形状，只是那次两端都**有**摘要）。
//
// 修法分两半，两半都不能越界：
//  ① `contentDiffersFrom` 的语义**一个字不动**（缺摘要 = 不可比 ≠ 不同），
//     否则升级后第一轮全库皆红——那是假红风暴，比静默更糟；
//  ② 新增 `contentUnverifiable` 信号，只被 `detectSyncConflicts` 消费，
//     且判据限死在「两端相对基线**都有**改动」——只有一端改过时，未改动那侧
//     == 基线，而基线是两端上次一致的那一版，可判定相同，走 LWW 安全。
//
// 本文件钉三组：
//  ① 正向：两端都无摘要、结构指纹全同、两端都改过 ⇒ 报冲突 + keepBoth；
//  ② 反向锁：只有一端改过 / 两端都没改过 ⇒ **不报**（假红风暴防线）；
//  ③ 降级区分：一端有摘要一端没有 ⇒ 走「不可比」老语义，不报；
//     两端都改过但 size 不同 ⇒ 走 bothChanged 老语义，不报成 unverifiable。
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';

void main() {
  // 基线：两端上次一致的那一版（ts=10、size=7、无摘要）。
  const baselineSnap = SyncSnapshot(id: 'x', updatedAt: 10, size: 7);
  SyncManifest manifestOf(SyncSnapshot snap) =>
      SyncManifest(entries: {'x': snap});

  group('① 正向：两端都报不出摘要 ⇒ 不可知必须让用户看见', () {
    test('同 ts 同 size 两端都改过 ⇒ 报冲突，contentUnverifiable=true', () {
      // 两端各自在**同一毫秒**保存，字节数恰好相同，且都还没写摘要（旧客户端）。
      const local = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      const remote = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);

      final conflicts = detectSyncConflicts(
        {'x': local},
        manifestOf(remote),
        manifestOf(baselineSnap),
      );

      expect(conflicts, hasLength(1), reason: '同 ts 同 size 的分叉旧写法永久静默');
      final c = conflicts.single;
      expect(c.docId, 'x');
      expect(c.contentUnverifiable, isTrue);
      expect(c.fingerprintTie, isFalse, reason: '结构指纹其实全同——这不是平局');
      expect(c.lwwTimestampSuspect, isTrue);
      expect(c.suggestedResolution, ConflictResolution.keepBoth);
      expect(c.localDigest, isNull);
      expect(c.remoteDigest, isNull);
    });

    test('默认裁决落到计划：planner 给不出操作 ⇒ 补一条上传（本地为主版本）', () {
      const local = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      const remote = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      // 结构指纹全同 ⇒ planner 的「== → 忽略」给不出任何操作（这正是缺陷的
      // 另一半：冲突就算报了，计划里也必须有对应动作）。
      final plan = const SyncPlanner().plan(
        manifestOf(local),
        manifestOf(remote),
      );
      expect(plan.operations, isEmpty, reason: '前提：planner 确实给不出方向');

      final conflicts = detectSyncConflicts(
        {'x': local},
        manifestOf(remote),
        manifestOf(baselineSnap),
      );
      final effective = effectiveConflictResolutions(conflicts, const {});
      expect(effective['x'], ConflictResolution.keepBoth);

      final resolved = applyConflictResolutions(plan, conflicts, const {});
      expect(resolved.uploadCount, 1, reason: '本地为主版本上传，云端那版先留副本');
      expect(resolved.downloadCount, 0);
    });

    test('用户显式裁决优先于默认 keepBoth', () {
      const local = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      const remote = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      final plan = const SyncPlanner().plan(
        manifestOf(local),
        manifestOf(remote),
      );
      final conflicts = detectSyncConflicts(
        {'x': local},
        manifestOf(remote),
        manifestOf(baselineSnap),
      );

      final resolved = applyConflictResolutions(
        plan,
        conflicts,
        const {'x': ConflictResolution.keepRemote},
      );
      expect(resolved.downloadCount, 1);
      expect(resolved.uploadCount, 0);
    });

    test('多文档：只有不可知的那篇被报出来，其余不牵连', () {
      const changed = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      // y 这篇「两端都没动」：本地 == 远端 == 基线 ⇒ 不该报（假红风暴防线）。
      const untouched = SyncSnapshot(id: 'y', updatedAt: 30, size: 5);
      final conflicts = detectSyncConflicts(
        {'x': changed, 'y': untouched},
        SyncManifest(entries: {'x': changed, 'y': untouched}),
        SyncManifest(entries: {'x': baselineSnap, 'y': untouched}),
      );
      expect(conflicts.map((c) => c.docId), ['x']);
    });
  });

  group('② 反向锁：假红风暴防线（这些都不许报）', () {
    test('两端都没改过 ⇒ 结构指纹相同即内容相同，不报', () {
      const same = SyncSnapshot(id: 'x', updatedAt: 10, size: 7);
      final conflicts = detectSyncConflicts(
        {'x': same},
        manifestOf(same),
        manifestOf(baselineSnap),
      );
      expect(conflicts, isEmpty);
    });

    test('只有一端改过（本地改、远端==基线）⇒ 不报', () {
      const local = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      final conflicts = detectSyncConflicts(
        {'x': local},
        manifestOf(baselineSnap), // 远端未动
        manifestOf(baselineSnap),
      );
      expect(conflicts, isEmpty, reason: '未改动那侧 == 基线 ⇒ 可判定内容相同');
    });

    test('只有一端改过（远端改、本地==基线）⇒ 不报', () {
      const remote = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      final conflicts = detectSyncConflicts(
        {'x': baselineSnap}, // 本地未动
        manifestOf(remote),
        manifestOf(baselineSnap),
      );
      expect(conflicts, isEmpty);
    });

    test('两端改过但 size 不同 ⇒ 走 bothChanged 老语义，不标 unverifiable', () {
      const local = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      const remote = SyncSnapshot(id: 'x', updatedAt: 20, size: 9);
      final conflicts = detectSyncConflicts(
        {'x': local},
        manifestOf(remote),
        manifestOf(baselineSnap),
      );
      expect(conflicts, hasLength(1));
      expect(conflicts.single.contentUnverifiable, isFalse);
    });

    test('两端改过、ts 相同 size 相同，但**任一侧**有摘要 ⇒ 不标 unverifiable', () {
      // 一侧有摘要、另一侧没有：仍是「不可比」，但此时不是「两端都无法证明」，
      // 而是一端能提供指纹——按老语义处理（不报），避免把单边旧数据报成全库冲突。
      const local = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      const remote = SyncSnapshot(
        id: 'x',
        updatedAt: 20,
        size: 7,
        digest: 'aaaa',
      );
      final conflicts = detectSyncConflicts(
        {'x': local},
        manifestOf(remote),
        manifestOf(baselineSnap),
      );
      expect(conflicts, isEmpty);
      expect(local.contentDiffersFrom(remote), isFalse, reason: '语义未变：不可比');
    });

    test('两端都有摘要且相同 ⇒ 内容确实相同，不报', () {
      const local = SyncSnapshot(
        id: 'x',
        updatedAt: 20,
        size: 7,
        digest: 'aaaa',
      );
      const remote = SyncSnapshot(
        id: 'x',
        updatedAt: 20,
        size: 7,
        digest: 'aaaa',
      );
      final conflicts = detectSyncConflicts(
        {'x': local},
        manifestOf(remote),
        manifestOf(baselineSnap),
      );
      expect(conflicts, isEmpty, reason: '摘要相等是确定性判据，不需要打扰用户');
    });
  });

  group('③ 语义边界：contentDiffersFrom 的「缺摘要即不可比」未被改动', () {
    test('任一侧缺摘要 ⇒ false（DN-206 的老契约原样保留）', () {
      const withDigest = SyncSnapshot(
        id: 'x',
        updatedAt: 20,
        size: 7,
        digest: 'aaaa',
      );
      const without = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      expect(without.contentDiffersFrom(withDigest), isFalse);
      expect(withDigest.contentDiffersFrom(without), isFalse);
      expect(
        without.contentDiffersFrom(
          const SyncSnapshot(id: 'x', updatedAt: 20, size: 7),
        ),
        isFalse,
      );
    });

    test('两端都有摘要且不同 ⇒ true（确定性判据仍然成立）', () {
      const a = SyncSnapshot(id: 'x', updatedAt: 20, size: 7, digest: 'aaaa');
      const b = SyncSnapshot(id: 'x', updatedAt: 20, size: 7, digest: 'bbbb');
      expect(a.contentDiffersFrom(b), isTrue);
    });

    test('lwwTimestampSuspect 把 unverifiable 计入（否则兜底不会触发）', () {
      const c = SyncConflict(
        docId: 'x',
        localUpdatedAt: 20,
        localSize: 7,
        remoteUpdatedAt: 20,
        remoteSize: 7,
        contentUnverifiable: true,
      );
      expect(c.lwwTimestampSuspect, isTrue);
      expect(c.suggestedResolution, ConflictResolution.keepBoth);
    });
  });
}
