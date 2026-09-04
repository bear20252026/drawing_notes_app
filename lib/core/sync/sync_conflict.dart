// WebDAV 本地优先同步——冲突检测 + 用户解析（P4-D，纯逻辑部件）。
//
// 冲突定义：某文档在「本地上次成功同步基线」之后，本地与远端都发生过改动
// （两端 updatedAt 均 ≠ 基线），此时谁先谁后不再是唯一答案，需用户裁决。
//
// 本文件只提供：
//   1. 冲突值模型（SyncConflict）+ 裁决枚举（ConflictResolution）
//   2. 纯逻辑冲突检测（detectSyncConflicts）
//   3. 纯逻辑「把裁决落到同步计划」的函数（applyConflictResolutions）
// 无 flutter/io/http/storage 依赖；不可变输入 → 确定性输出。
//
// 注意：keepBoth 的「保留远端副本到本地」是 IO 副作用，由 SyncService 处理，
// 纯函数层面 keepBoth 仅表示「本地为主版本」（强制 upload）。
//
// M6 邻接修复：updatedAt 相等但内容不同（同毫秒双端编辑 / 时钟偏移巧合）
// 会被 planner 的「== → 忽略」分支永久静默分叉，且旧检测条件（两端均 ≠ 基线）
// 永远抓不到它——现补入 sameTsDiverged 分支，交由用户裁决闭环。

import 'sync_planner.dart';

/// 用户对一次冲突的裁决。
enum ConflictResolution {
  /// 保留本地版本（以本地为准，覆盖远端）。
  keepLocal,

  /// 保留远端版本（以远端为准，覆盖本地）。
  keepRemote,

  /// 两者皆保留：本地作为主版本，远端另存为本地副本（不丢失任一侧）。
  keepBoth,
}

/// 一次冲突的完整描述（供 UI 展示与裁决）。
class SyncConflict {
  const SyncConflict({
    required this.docId,
    required this.localUpdatedAt,
    required this.localSize,
    required this.remoteUpdatedAt,
    required this.remoteSize,
  });

  final String docId;
  final int localUpdatedAt; // epoch ms
  final int localSize;
  final int remoteUpdatedAt; // epoch ms
  final int remoteSize;

  /// 本地是否较新（用于 UI 建议的默认裁决）。
  bool get localNewer => localUpdatedAt > remoteUpdatedAt;

  /// 远端是否较新（用于 UI 建议的默认裁决）。
  bool get remoteNewer => remoteUpdatedAt > localUpdatedAt;

  /// 建议的默认裁决：较新者胜；相等时默认保留本地。
  ConflictResolution get suggestedResolution => remoteNewer
      ? ConflictResolution.keepRemote
      : ConflictResolution.keepLocal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncConflict &&
          runtimeType == other.runtimeType &&
          docId == other.docId &&
          localUpdatedAt == other.localUpdatedAt &&
          localSize == other.localSize &&
          remoteUpdatedAt == other.remoteUpdatedAt &&
          remoteSize == other.remoteSize;

  @override
  int get hashCode => Object.hash(
    docId,
    localUpdatedAt,
    localSize,
    remoteUpdatedAt,
    remoteSize,
  );

  @override
  String toString() =>
      'SyncConflict(docId: $docId, local: $localUpdatedAt/'
      '$localSize, remote: $remoteUpdatedAt/$remoteSize)';
}

/// 纯逻辑冲突检测。
///
/// 遍历基线中每个文档，若本地与远端相对基线都发生过变更，则视为一次真冲突。
/// 返回的 [SyncConflict] 顺序与基线条目顺序一致（确定性）。
List<SyncConflict> detectSyncConflicts(
  Map<String, SyncSnapshot> currentEntries,
  SyncManifest remoteManifest,
  SyncManifest baseline,
) {
  final result = <SyncConflict>[];
  for (final id in baseline.entries.keys) {
    final base = baseline.entries[id];
    final local = currentEntries[id];
    final remote = remoteManifest.entries[id];
    if (base == null || local == null || remote == null) continue;
    // 两端相对基线都改过，且 updatedAt 不一致（真·双边独立编辑）。
    // 注意：local.updatedAt == remote.updatedAt 不属此类——同 ts 同 size 是无
    // 变化、同 ts 不同 size 是 sameTsDiverged；把同 ts 排除出 bothChanged 是
    // 避免「同毫秒双端编辑 / 时钟偏移巧合」被误判为冲突的关键。
    final bothChanged =
        local.updatedAt != base.updatedAt &&
        remote.updatedAt != base.updatedAt &&
        local.updatedAt != remote.updatedAt;
    // updatedAt 相等但 size 不同：planner 的「== → 忽略」永远不会处理它，
    // 若不报冲突则两端版本将静默分叉到下一次编辑为止。必须交由用户裁决。
    final sameTsDiverged =
        local.updatedAt == remote.updatedAt && local.size != remote.size;
    if (bothChanged || sameTsDiverged) {
      result.add(
        SyncConflict(
          docId: id,
          localUpdatedAt: local.updatedAt,
          localSize: local.size,
          remoteUpdatedAt: remote.updatedAt,
          remoteSize: remote.size,
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

/// 把裁决映射应用到同步计划，得到「有效计划」。
///
/// - [keepLocal]：该文档强制上传（本地胜）。
/// - [keepRemote]：该文档强制下载（远端胜）。
/// - [keepBoth]：该文档强制上传（本地为默认主版本）；远端副本由 SyncService
///   另行落地，纯函数不处理。
/// 未出现在 [resolutions] 的冲突文档不覆盖（走默认 LWW）。
/// 返回的新计划保持确定性排序：deleteRemote → upload → download（id 字典序）。
SyncPlan applyConflictResolutions(
  SyncPlan plan,
  List<SyncConflict> conflicts,
  Map<String, ConflictResolution> resolutions,
) {
  // 无冲突时计划无需调整（保 LWW 既有行为）。
  if (conflicts.isEmpty) return plan;
  final indexed = {for (final c in conflicts) c.docId: c};
  final planIds = {for (final op in plan.operations) op.id};

  // 空裁决 且 所有冲突文档都已在计划中有操作 → 无 gap，返回原计划（引用相同，保既有行为）。
  // 仅当存在「计划里没有操作的冲突文档」（M6 sameTsDiverged 被 planner 丢弃）时才继续，
  // 为其补一条 LWW 默认操作（ts 相等 → keepLocal → 上传）。
  if (resolutions.isEmpty &&
      conflicts.every((c) => planIds.contains(c.docId))) {
    return plan;
  }

  final uploads = <String>[];
  final downloads = <String>[];
  final deletes = <String>[];

  for (final op in plan.operations) {
    final resolution = resolutions[op.id];
    if (resolution == null || !indexed.containsKey(op.id)) {
      _bucket(op, uploads, downloads, deletes);
      continue;
    }
    switch (resolution) {
      case ConflictResolution.keepLocal:
      case ConflictResolution.keepBoth:
        if (op.kind != SyncOperationKind.deleteRemote) {
          uploads.add(op.id);
        }
        break;
      case ConflictResolution.keepRemote:
        if (op.kind != SyncOperationKind.deleteRemote) {
          downloads.add(op.id);
        }
        break;
    }
  }

  // 计划里没有操作（如两端 updatedAt 相等被 planner 「== → 忽略」丢弃）的冲突文档：
  // 必须补一条强制操作，否则该冲突将静默分叉到下次编辑为止（M6）。
  // 无显式裁决时按 LWW 默认（ts 相等 → suggestedResolution 为 keepLocal → 上传）。
  for (final c in conflicts) {
    if (planIds.contains(c.docId)) continue; // 计划已有操作，首轮已 bucket，跳过
    final resolution = resolutions[c.docId];
    final effective = resolution ?? c.suggestedResolution;
    if (effective == ConflictResolution.keepRemote) {
      downloads.add(c.docId);
    } else {
      uploads.add(c.docId);
    }
  }

  deletes.sort();
  uploads.sort();
  downloads.sort();
  return SyncPlan(
    operations: [
      for (final id in deletes)
        SyncOperation(kind: SyncOperationKind.deleteRemote, id: id),
      for (final id in uploads)
        SyncOperation(kind: SyncOperationKind.upload, id: id),
      for (final id in downloads)
        SyncOperation(kind: SyncOperationKind.download, id: id),
    ],
  );
}

void _bucket(
  SyncOperation op,
  List<String> uploads,
  List<String> downloads,
  List<String> deletes,
) {
  switch (op.kind) {
    case SyncOperationKind.upload:
      uploads.add(op.id);
    case SyncOperationKind.download:
      downloads.add(op.id);
    case SyncOperationKind.deleteRemote:
      deletes.add(op.id);
  }
}

/// 冲突裁决处理器（注入式）。
///
/// 默认 [LwwConflictHandler] 不覆盖任何文档（返回空映射），保持 LWW 语义不变。
/// UI 可注入「弹窗询问用户」的实现。
abstract class ConflictHandler {
  /// 对所有 [conflicts] 返回裁决映射；返回空映射表示「不覆盖，走默认 LWW」。
  Future<Map<String, ConflictResolution>> resolve(List<SyncConflict> conflicts);
}

/// 默认冲突处理器：不做任何覆盖（LWW 较新者胜），保既有行为。
class LwwConflictHandler implements ConflictHandler {
  const LwwConflictHandler();

  @override
  Future<Map<String, ConflictResolution>> resolve(
    List<SyncConflict> conflicts,
  ) async => const {};
}
