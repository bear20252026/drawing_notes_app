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

/// 「本地这一份是被删那一版」这个结论是**靠什么证据**得出的。
///
/// 为什么要把证据单列：A3-2（甲）会据此**按住一次上传**，那就必须能说清
/// 「凭什么说你没有独有内容」。两种证据的可得性不同，混在一个枚举里就说不清
/// 哪条判据在起作用，将来收紧或放宽时无从下手。
enum RemoteDeleteProof {
  /// 我的基线说本地相对上次同步一字未动（最强、最直接）。
  baselineUnchanged,

  /// 没有可用基线，但本地那一版的 `updatedAt`（+ size）正等于墓碑记的
  /// 「被删的那一版」——跨设备可比的因果事实，因为 `updatedAt` 是文档自己的
  /// 字段、同步过之后两端拿到同一个数，不是各自读钟。
  causalAnchor,

  /// 相对基线确实改过 ⇒ 删除与编辑撞车，本地有只此一份的内容。
  baselineChanged,

  /// 两条证据都没有：不判胜负（缺信息永远走这一支，不当成「有改动」）。
  none,
}

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
    required this.proof,
    this.tombstoneBaseRev,
    this.tombstoneDeletedAt,
    this.tombstoneBaseSize,
  });

  final String docId;
  final RemoteDeleteKind kind;
  final int localUpdatedAt;
  final int localSize;

  /// 结论是靠什么证据得出的（见 [RemoteDeleteProof]）。单列出来是因为 A3-2 会
  /// 据此**按住一次上传**，那就必须答得出「凭什么说本机没有独有内容」。
  final RemoteDeleteProof proof;

  /// 墓碑带来的因果锚（删除作用在哪一版之上）。可能为 null——旧客户端写的
  /// 清单里没有这块，那时判据只能用本地基线那一条。
  final int? tombstoneBaseRev;
  final int? tombstoneDeletedAt;

  /// 被删那一版的字节数（因果判据的第二条腿）。null = 旧客户端没写，退回只比
  /// 时间戳。
  final int? tombstoneBaseSize;

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
          proof == other.proof &&
          tombstoneBaseRev == other.tombstoneBaseRev &&
          tombstoneDeletedAt == other.tombstoneDeletedAt &&
          tombstoneBaseSize == other.tombstoneBaseSize;

  @override
  int get hashCode => Object.hash(
    docId,
    kind,
    localUpdatedAt,
    localSize,
    proof,
    tombstoneBaseRev,
    tombstoneDeletedAt,
    tombstoneBaseSize,
  );

  @override
  String toString() =>
      'RemoteDeleteIssue(docId: $docId, kind: $kind, local: '
      '$localUpdatedAt/$localSize'
      '${tombstoneBaseRev == null ? '' : ', baseRev: $tombstoneBaseRev'}'
      ', proof: ${proof.name})';
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
    // 证据优先级：**先结构、后因果**。基线说本地改过就一定算改过——那是本机
    // 事实，比时间戳比对强；只有基线不可得时，才用墓碑的因果锚单独定案
    // （这正是 A3-2 需要的：基线会被后续同步推进掉，光靠它这条判据活不过第二轮）。
    final base = baseline.entries[id];
    final tombstone = remote.tombstones[id];
    RemoteDeleteKind kind;
    RemoteDeleteProof proof;
    if (base != null) {
      if (local != base) {
        kind = RemoteDeleteKind.localHasEdits;
        proof = RemoteDeleteProof.baselineChanged;
      } else {
        kind = RemoteDeleteKind.staleCopy;
        proof = RemoteDeleteProof.baselineUnchanged;
      }
    } else if (tombstone != null &&
        tombstone.hasRevisionAnchor &&
        local.updatedAt == tombstone.baseRev &&
        (tombstone.baseSize == null || tombstone.baseSize == local.size)) {
      kind = RemoteDeleteKind.staleCopy;
      proof = RemoteDeleteProof.causalAnchor;
    } else {
      kind = RemoteDeleteKind.unknowable;
      proof = RemoteDeleteProof.none;
    }
    result.add(
      RemoteDeleteIssue(
        docId: id,
        kind: kind,
        localUpdatedAt: local.updatedAt,
        localSize: local.size,
        proof: proof,
        tombstoneBaseRev: tombstone?.baseRev,
        tombstoneDeletedAt: tombstone?.deletedAt,
        tombstoneBaseSize: tombstone?.baseSize,
      ),
    );
  }
  return List.unmodifiable(result);
}
