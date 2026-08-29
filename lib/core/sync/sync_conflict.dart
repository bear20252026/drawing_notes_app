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
  ConflictResolution get suggestedResolution =>
      remoteNewer ? ConflictResolution.keepRemote : ConflictResolution.keepLocal;

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
  int get hashCode =>
      Object.hash(docId, localUpdatedAt, localSize, remoteUpdatedAt, remoteSize);

  @override
  String toString() => 'SyncConflict(docId: $docId, local: $localUpdatedAt/'
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
    if (local.updatedAt != base.updatedAt && remote.updatedAt != base.updatedAt) {
      result.add(SyncConflict(
        docId: id,
        localUpdatedAt: local.updatedAt,
        localSize: local.size,
        remoteUpdatedAt: remote.updatedAt,
        remoteSize: remote.size,
      ));
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
  if (resolutions.isEmpty) return plan;
  final indexed = {for (final c in conflicts) c.docId: c};

  final uploads = <String>[];
  final downloads = <String>[];
  final deletes = <String>[];
  final handled = <String>{};

  for (final op in plan.operations) {
    final resolution = resolutions[op.id];
    if (resolution == null || !indexed.containsKey(op.id)) {
      _bucket(op, uploads, downloads, deletes);
      continue;
    }
    handled.add(op.id);
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

  // 被裁决但计划里没有操作（如两端 updatedAt 相等被忽略）的冲突文档：
  // 按裁决补充一条强制操作（keepRemote → 下载；否则 → 上传，幂等安全）。
  for (final c in conflicts) {
    if (handled.contains(c.docId)) continue;
    final resolution = resolutions[c.docId];
    if (resolution == null) continue;
    if (resolution == ConflictResolution.keepRemote) {
      downloads.add(c.docId);
    } else {
      uploads.add(c.docId);
    }
  }

  deletes.sort();
  uploads.sort();
  downloads.sort();
  return SyncPlan(operations: [
    for (final id in deletes) SyncOperation(kind: SyncOperationKind.deleteRemote, id: id),
    for (final id in uploads) SyncOperation(kind: SyncOperationKind.upload, id: id),
    for (final id in downloads) SyncOperation(kind: SyncOperationKind.download, id: id),
  ]);
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
  ) async =>
      const {};
}
