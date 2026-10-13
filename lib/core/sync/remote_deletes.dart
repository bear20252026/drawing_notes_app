// A3 的第二件成品：远端删除的**只读**判定。
//
// 墓碑上了线（`SyncManifest.tombstones`）之后，第一个读者必须是这个，而且它
// 只能报告：判据里最有价值的那条「本地这份是删除之前的旧副本」一旦配上
// 「那就把本地这份删掉」，程序就会主动移除用户的画布。那一步需要业主点名
// （见 docs/COLLABORATION_ROADMAP_2026-10-13.md §10 的甲/乙/丙），本文件
// 因此**刻意不产出任何操作**，只把已经存在的分叉说清楚。
//
// 为什么这些条目过去完全隐形：`SyncPlanner.plan` 只读 `local.deletedIds`，
// 远端的删除集合没有任何消费者；而回写清单那句又是 `SyncManifest(entries:)`，
// 每轮把删除历史写空。于是「一端删除、另一端复活」既不报错也不留痕。
//
// 纯逻辑：无 flutter/io/http 依赖，不可变输入 → 确定性输出（按 id 字典序）。

import 'sync_planner.dart';

/// 一篇「云端已删除、本地仍留着」的文档，本地这一份到底是什么。
enum RemoteDeleteKind {
  /// 相对**自己的基线**一字未动 ⇒ 本地没有独有内容，它是删除之前的旧副本。
  /// 这一类是唯一可能「无损跟随删除」的（本轮仍不动它）。
  staleCopy,

  /// 相对基线改过 ⇒ 删除与编辑撞车，本地有只有这一份才有的内容。
  localHasEdits,

  /// 无从比对（我的基线里没有这一篇，或两端各写各的）⇒ 不判胜负。
  /// 缺信息一律走这一支，**绝不**当成「本地有改动」（DN-206 同一纪律：
  /// 否则混合版本集群升级的第一轮会冒出一堆假红）。
  unknowable,
}

/// 一条「云端删过、本地还留着」的报告项。
class RemoteDeleteIssue {
  const RemoteDeleteIssue({
    required this.docId,
    required this.kind,
    required this.localUpdatedAt,
    required this.localSize,
    this.tombstoneBaseRev,
    this.tombstoneDeletedAt,
  });

  final String docId;
  final RemoteDeleteKind kind;
  final int localUpdatedAt;
  final int localSize;

  /// 墓碑带来的因果锚（删除作用在哪一版之上）。可能为 null——旧客户端写的
  /// 清单里没有这块，那时判据只能用本地基线那一条。
  final int? tombstoneBaseRev;
  final int? tombstoneDeletedAt;

  /// 跟随删除是否会丢掉只存在于本机的手艺（本轮只用于**叙述**，不用于行动）。
  bool get isLossFreeToDrop => kind == RemoteDeleteKind.staleCopy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteDeleteIssue &&
          runtimeType == other.runtimeType &&
          docId == other.docId &&
          kind == other.kind &&
          localUpdatedAt == other.localUpdatedAt &&
          localSize == other.localSize &&
          tombstoneBaseRev == other.tombstoneBaseRev &&
          tombstoneDeletedAt == other.tombstoneDeletedAt;

  @override
  int get hashCode => Object.hash(
    docId,
    kind,
    localUpdatedAt,
    localSize,
    tombstoneBaseRev,
    tombstoneDeletedAt,
  );

  @override
  String toString() =>
      'RemoteDeleteIssue(docId: $docId, kind: $kind, local: '
      '$localUpdatedAt/$localSize'
      '${tombstoneBaseRev == null ? '' : ', baseRev: $tombstoneBaseRev'})';
}

/// 纯逻辑判定：远端宣布删除、本地却还活着的文档。
///
/// 三条边界：
///  ① 远端**同时**有条目又有墓碑（畸形或刚被别人重传）⇒ 按「还活着」处理，
///     不报——报错了会诱导用户去删自己正在用的东西；
///  ② 本地自己也主张删过（`localDeletedIds` 含它）⇒ 两端共识，不报；
///  ③ 本地根本没有这一篇 ⇒ 无话可说，不报。
List<RemoteDeleteIssue> detectRemoteDeletes({
  required Map<String, SyncSnapshot> currentEntries,
  required Set<String> localDeletedIds,
  required SyncManifest remote,
  required SyncManifest baseline,
}) {
  final result = <RemoteDeleteIssue>[];
  final ids = remote.deletedIds.toList()..sort();
  for (final id in ids) {
    if (remote.entries.containsKey(id)) continue; // ①
    if (localDeletedIds.contains(id)) continue; // ②
    final local = currentEntries[id];
    if (local == null) continue; // ③
    final base = baseline.entries[id];
    final kind = base == null
        ? RemoteDeleteKind.unknowable
        : (local != base
              ? RemoteDeleteKind.localHasEdits
              : RemoteDeleteKind.staleCopy);
    final tombstone = remote.tombstones[id];
    result.add(
      RemoteDeleteIssue(
        docId: id,
        kind: kind,
        localUpdatedAt: local.updatedAt,
        localSize: local.size,
        tombstoneBaseRev: tombstone?.baseRev,
        tombstoneDeletedAt: tombstone?.deletedAt,
      ),
    );
  }
  return List.unmodifiable(result);
}
