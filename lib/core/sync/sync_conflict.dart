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
// 唯一例外是可疑时钟判定：[nowMs] 可注入（缺省读系统钟），测试传固定值
// 即可完全复现确定性。
//
// 注意：keepBoth 的「保留远端副本到本地」是 IO 副作用，由 SyncService 处理，
// 纯函数层面 keepBoth 仅表示「本地为主版本」（强制 upload）。
//
// M6 邻接修复：updatedAt 相等但内容不同（同毫秒双端编辑 / 时钟偏移巧合）
// 会被 planner 的「== → 忽略」分支永久静默分叉，且旧检测条件（两端均 ≠ 基线）
// 永远抓不到它——现补入 sameTsDiverged 分支，交由用户裁决闭环。
//
// P2 修复（审计 2026-10）：时钟偏快的一端把未来戳写进 manifest/基线后，
// 「两端都相对基线改过」这一必要条件永不成立（远端 == 基线），LWW 会让
// 未来戳一路赢下去，另一侧的真实编辑被**无提示覆盖**——违反「冲突可见」。
// 现补入两条判据：①结构性（主）：一端相对基线一字未动却在时间戳比大小中
// 获胜 ⇒ 该端戳不可信；②时钟性（辅）：远端戳晚于本地当前时间超容差。
// 命中任一即报冲突，且默认裁决偏向「保住真有改动的那一侧」。

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
    this.remoteTimestampUntrusted = false,
    this.localUnchangedSinceBaseline = false,
  });

  final String docId;
  final int localUpdatedAt; // epoch ms
  final int localSize;
  final int remoteUpdatedAt; // epoch ms
  final int remoteSize;

  /// 远端时间戳不可信（P2 时钟修复）：要么相对基线根本没变却在比大小中赢了
  /// 本地真实编辑，要么晚于本地当前时间（对端时钟偏快的未来戳）。按 LWW 取
  /// 远端必然静默覆盖本地——默认裁决改为保本地。
  final bool remoteTimestampUntrusted;

  /// 本地相对基线一字未动，却因时间戳较新而要覆盖远端改动：本地没有需要保住
  /// 的数据，默认裁决改为保远端（下载是无损的）。
  final bool localUnchangedSinceBaseline;

  /// LWW 的时间戳依据可疑：无用户显式裁决时不得沿用 planner 的默认方向。
  bool get lwwTimestampSuspect =>
      remoteTimestampUntrusted || localUnchangedSinceBaseline;

  /// 本地是否较新（用于 UI 建议的默认裁决）。
  bool get localNewer => localUpdatedAt > remoteUpdatedAt;

  /// 远端是否较新（用于 UI 建议的默认裁决）。
  bool get remoteNewer => remoteUpdatedAt > localUpdatedAt;

  /// 建议的默认裁决：较新者胜；相等时默认保留本地。
  /// 时间戳可疑时不看戳——保住「相对基线真有改动」的那一侧（P2 修复）。
  ConflictResolution get suggestedResolution {
    if (remoteTimestampUntrusted) return ConflictResolution.keepLocal;
    if (localUnchangedSinceBaseline) return ConflictResolution.keepRemote;
    return remoteNewer
        ? ConflictResolution.keepRemote
        : ConflictResolution.keepLocal;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncConflict &&
          runtimeType == other.runtimeType &&
          docId == other.docId &&
          localUpdatedAt == other.localUpdatedAt &&
          localSize == other.localSize &&
          remoteUpdatedAt == other.remoteUpdatedAt &&
          remoteSize == other.remoteSize &&
          remoteTimestampUntrusted == other.remoteTimestampUntrusted &&
          localUnchangedSinceBaseline == other.localUnchangedSinceBaseline;

  @override
  int get hashCode => Object.hash(
    docId,
    localUpdatedAt,
    localSize,
    remoteUpdatedAt,
    remoteSize,
    remoteTimestampUntrusted,
    localUnchangedSinceBaseline,
  );

  @override
  String toString() =>
      'SyncConflict(docId: $docId, local: $localUpdatedAt/'
      '$localSize, remote: $remoteUpdatedAt/$remoteSize'
      '${remoteTimestampUntrusted ? ', remoteTsUntrusted' : ''}'
      '${localUnchangedSinceBaseline ? ', localUnchanged' : ''})';
}

/// 可疑时钟容差（P2 修复）：远端 updatedAt 晚于本地当前时间超过此值即视为
/// 「未来戳」。取 5 分钟——足以吸收正常跨设备 NTP 漂移的误报，而真正的病态
/// 偏快（小时/天级）必然落进这里。主判据是下面的结构性规则（不依赖时钟），
/// 本容差只用于给「双边都改过」的场景挑一个不偏向未来戳的默认裁决。
const int kFutureClockToleranceMs = 5 * 60 * 1000;

/// 纯逻辑冲突检测。
///
/// 遍历基线中每个文档，只要「按 LWW 走会静默覆盖掉真有改动的一侧」就报冲突
/// （宁可多报，不可静默覆盖）。返回的 [SyncConflict] 顺序与基线条目顺序一致
/// （确定性）；[nowMs] 注入固定值即可让时钟判据也完全确定。
List<SyncConflict> detectSyncConflicts(
  Map<String, SyncSnapshot> currentEntries,
  SyncManifest remoteManifest,
  SyncManifest baseline, {
  int? nowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final result = <SyncConflict>[];
  for (final id in baseline.entries.keys) {
    final base = baseline.entries[id];
    final local = currentEntries[id];
    final remote = remoteManifest.entries[id];
    if (base == null || local == null || remote == null) continue;
    // 两端指纹（时间戳 + size）完全一致：无变化或已收敛，无需裁决。
    if (local == remote) continue;
    // 「改过」按内容/版本指纹判（时间戳或 size 任一与基线不同）——只看时间戳
    // 会被时钟问题骗过（P2）。
    final localChanged = local != base;
    final remoteChanged = remote != base;
    // 两端相对基线都改过，且彼此不同（真·双边独立编辑）。同 ts 同 size 已被
    // 上面的 local == remote 挡掉；同 ts 不同 size 走 sameTsDiverged。
    final bothChanged =
        localChanged &&
        remoteChanged &&
        (local.updatedAt != remote.updatedAt || local.size != remote.size);
    // updatedAt 相等但 size 不同：planner 的「== → 忽略」永远不会处理它，
    // 若不报冲突则两端版本将静默分叉到下一次编辑为止（M6）。
    final sameTsDiverged =
        local.updatedAt == remote.updatedAt && local.size != remote.size;
    // 结构性判据①：远端相对基线一字未动，LWW 却判远端赢（remote.ts > local.ts）。
    // 远端既然没变过，它就不该有「更新的版本」——唯一解释是戳来自偏快的时钟
    // （或本机时钟偏慢）。按 LWW 下载会把本地真实编辑无提示覆盖掉（P2）。
    final remoteWinsWithoutChanging =
        localChanged && !remoteChanged && remote.updatedAt > local.updatedAt;
    // 结构性判据②（镜像）：本地相对基线一字未动，LWW 却判本地赢 → 上传会
    // 静默抹掉远端的真实改动。本地没有需要保住的数据。
    final localWinsWithoutChanging =
        remoteChanged && !localChanged && local.updatedAt > remote.updatedAt;
    // 时钟判据：远端戳晚于本地当前时间（超容差）且在比大小中赢。
    final futureRemoteStampWins =
        localChanged &&
        remote.updatedAt > local.updatedAt &&
        remote.updatedAt - now > kFutureClockToleranceMs;
    final remoteUntrusted =
        remoteWinsWithoutChanging || futureRemoteStampWins;
    final hasConflict =
        bothChanged ||
        sameTsDiverged ||
        remoteUntrusted ||
        localWinsWithoutChanging;
    if (hasConflict) {
      result.add(
        SyncConflict(
          docId: id,
          localUpdatedAt: local.updatedAt,
          localSize: local.size,
          remoteUpdatedAt: remote.updatedAt,
          remoteSize: remote.size,
          remoteTimestampUntrusted: remoteUntrusted,
          localUnchangedSinceBaseline: localWinsWithoutChanging,
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
/// 未出现在 [resolutions] 的冲突文档：时间戳可疑者按其默认裁决兜底（P2 修复
/// ——沿原计划就是静默覆盖），其余走默认 LWW。
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

  // 时钟可疑的冲突：用户没裁决（默认 LwwConflictHandler，或弹窗被取消）时
  // 不能沿用 planner 的 LWW 方向——那正是把真实编辑静默覆盖掉的方向。
  // 这里先按「保住真有改动的一侧」兜底，冲突本身仍会在 UI 上可见。
  final suspectDefaults = <String, ConflictResolution>{
    for (final c in conflicts)
      if (c.lwwTimestampSuspect) c.docId: c.suggestedResolution,
  };

  // 空裁决 且 所有冲突文档都已在计划中有操作、且无一可疑 → 无 gap，返回原计划
  // （引用相同，保既有行为）。仅当存在「计划里没有操作的冲突文档」（M6
  // sameTsDiverged 被 planner 丢弃）或有可疑时钟冲突时才继续。
  if (resolutions.isEmpty &&
      suspectDefaults.isEmpty &&
      conflicts.every((c) => planIds.contains(c.docId))) {
    return plan;
  }

  final uploads = <String>[];
  final downloads = <String>[];
  final deletes = <String>[];

  for (final op in plan.operations) {
    final conflict = indexed[op.id];
    final resolution = resolutions[op.id] ?? suspectDefaults[op.id];
    if (resolution == null || conflict == null) {
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
