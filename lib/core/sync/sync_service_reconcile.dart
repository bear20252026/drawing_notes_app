// 由 Claude 团队生成 | Drawing Notes App
// SyncService 的「三方对账判据」一侧（2026-10-15 从 `syncNow()` 抽出）。
// 同库 part——私有成员互相可见，拆文件不改行为。
//
// 抽出来的唯一动机是**注意力预算**，不是行数指标：这两段是整轮同步里审计出处最密
// 的判据（DN-107 / DN-204 / A3 墓碑因果 / M4 副本 / DN-206 未保住副本），而它们
// 原本住在一个 430 行的 `syncNow()` 中间，每次改动都要在编排体里重新定位一次。
// `syncNow()` 到 972/1000 行只是顺带被治到的那个症状。
//
// 两条纪律：
// ① **纯函数**——网络与磁盘的腿（`documentStore.listDocuments()` /
//    `baselineStore.load()`）仍由 `syncNow()` 自己跑，读到的结果作参数传进来；
//    这两个函数自己不做任何 IO，也不写 `await`，所以「搬动它们」等价于搬动文本。
// ② **不复制判据**——「哪些算删除」这件事仍然只有段一这一处口径（A3 §9 的原话），
//    段二也不重新推导「本轮哪些真落地了」，它读的就是 `_ExecuteOutcome` 那一份。
part of 'sync_service.dart';

/// 段一产出的三样东西：本地清单、供冲突/删除判据用的当前条目、以及隔离态下
/// 「本该生成删除墓碑但被按住」的那批 id（DN-204 的差异摘要要报它）。
typedef _LocalReconciliation =
    ({
      Map<String, SyncSnapshot> currentEntries,
      SyncManifest manifest,
      Set<String> suppressedTombstoneIds,
    });

extension SyncServiceReconcile on SyncService {
  /// 构本地清单：当前可读文档 + 删除墓碑（基线有但本次清单无 ⇒ 墓碑）。
  ///
  /// A3（方案 §9）：`deletedIds` 与因果侧 `tombstones` 在**同一个循环、同一判据**
  /// 下生成——「哪些算删除」只允许有一处口径，另写一遍迟早和这里分叉。
  _LocalReconciliation _buildLocalManifest({
    required SyncLocalInventory inventory,
    required SyncManifest baseline,
    required PostRestoreReconcile? policy,
  }) {
    final currentEntries = <String, SyncSnapshot>{
      for (final d in inventory.readable)
        d.id: SyncSnapshot(
          id: d.id,
          updatedAt: d.updatedAt,
          size: d.size,
          digest: d.digest,
        ),
    };
    final deletedIds = <String>{};
    final localTombstones = <String, SyncTombstone>{};
    final tombstoneStampMs = DateTime.now().millisecondsSinceEpoch;
    // DN-204：隔离态下本会生成的删除墓碑全部改道进这里，一条 DELETE 都不发。
    final suppressedTombstones = <String>{};
    for (final id in baseline.entries.keys) {
      if (currentEntries.containsKey(id)) continue;
      // DN-107（P0 数据安全）：**存在但读不出来**（受密笔记锁定 / 权限不足 /
      // 暂时不可访问）绝不算删除。按基线快照原样带回清单 ⇒ 两端一致 ⇒ 计划器
      // 不产生任何操作，等它解锁后自然继续同步。此前这里直接落到「基线有、
      // 本次清单无 ⇒ 墓碑」，于是「关掉应用重新打开、笔记还没解锁就同步」
      // 会把云端副本删掉。
      if (inventory.unreadable.contains(id)) {
        final baselineSnap = baseline.entries[id];
        if (baselineSnap != null) currentEntries[id] = baselineSnap;
        continue;
      }
      if (baseline.deletedIds.contains(id)) continue;
      if (policy != null) {
        suppressedTombstones.add(id);
        continue;
      }
      deletedIds.add(id);
      // baseRev = 删除作用在哪一版之上（基线里那一条的 updatedAt）。这是下一
      // 条腿（「云端已删 ⇒ 本地这份是删除前的旧版」判定）唯一能用的因果锚。
      final removed = baseline.entries[id];
      localTombstones[id] = SyncTombstone(
        id: id,
        deletedAt: tombstoneStampMs,
        baseRev: removed?.updatedAt,
        baseSize: removed?.size,
      );
    }
    return (
      currentEntries: currentEntries,
      manifest: SyncManifest(
        entries: currentEntries,
        deletedIds: deletedIds,
        tombstones: localTombstones,
      ),
      suppressedTombstoneIds: suppressedTombstones,
    );
  }

  /// 本轮结束时**本地基线**应当长什么样（远端清单已在上面写完，两者不是一套）。
  ///
  /// 四条规则按「谁本轮真落过字节」收口，全部来自踩过的坑，逐条都有用例钉着：
  /// - M4：keepBoth 副本只进本地基线（远端无此文件，进远端清单会导致其他设备
  ///   下载 404 空转）；下轮它们作为本地新增正常上传。
  /// - 毒丸防误删：仅远端文档**没真正下载成功**时（真失败 / 远端 404 而跳过，
  ///   两者都在 `notSyncedIds` 里），绝不能让它随 `{...newEntries}` 进入基线——
  ///   否则下轮「本地无 + 基线有」会被误判为本地删除墓碑，把从未成功下载的
  ///   远端文档 deleteRemote 掉（数据丢失；服务器对活对象误报 404 时更是直接
  ///   删掉真实云端文件）。远端 manifest 保留该条目（远端文件真实存在），
  ///   基线剔除后下轮它仍是「仅远端 ⇒ download」自动重试。
  ///   本地已有该文档的下载失败不受影响（墓碑推导要求本地缺失才会触发）。
  /// - 没能保住云端副本的文档本轮一个字节都没同步（上传已跳过）：基线必须退回
  ///   本轮开始时的值（远端清单仍保留该条目——远端文件真实存在）。若沿用
  ///   `{...newEntries}` 里的远端快照，基线等于谎称「云端那版就是上次同步态」，
  ///   下轮冲突判据会退化成「远端没改过却比本地新」⇒ 用户不出裁决时的兜底
  ///   方向正是上传 ⇒ 又变成静默盖掉云端。
  /// - DN-204：隔离轮的基线只能描述「本机现在真有」的那几篇。沿用
  ///   `{...newEntries}`（= 本轮结束时的云端清单）会把云端独有的篇目一并记进
  ///   基线——而恢复出来的库里就是没有它们。下一轮（基线已推进、隔离解除）判据
  ///   又是「基线有、本地无」⇒ 同一批删除墓碑重新生成，云端副本照旧被删掉，
  ///   只是**延后一轮**发生。那正是本条要修的事，绝不能以「用户已经选了方向」
  ///   为名把它放回管道里。允许进基线的三来源：本轮列得出来的本地文档
  ///   （含 DN-107 的「存在但读不到」，它按基线快照带回，本来就是本地文件）、
  ///   keepBoth 刚落到本地的副本、本轮真下载成功的文档。
  Map<String, SyncSnapshot> _baselineEntriesFor({
    required Map<String, SyncSnapshot> newEntries,
    required SyncPlan plan,
    required _ExecuteOutcome executed,
    required Map<String, SyncSnapshot> currentEntries,
    required List<SyncSnapshot> keptCopies,
    required Set<String> unprotected,
    required SyncManifest baseline,
    required PostRestoreReconcile? policy,
  }) {
    final baselineEntries = <String, SyncSnapshot>{...newEntries};
    for (final op in plan.operations) {
      if (op.kind == SyncOperationKind.download &&
          executed.notSyncedIds.contains(op.id) &&
          !currentEntries.containsKey(op.id)) {
        baselineEntries.remove(op.id);
      }
    }
    for (final copy in keptCopies) {
      baselineEntries[copy.id] = copy;
    }
    for (final id in unprotected) {
      final previous = baseline.entries[id];
      if (previous == null) {
        baselineEntries.remove(id);
      } else {
        baselineEntries[id] = previous;
      }
    }
    if (policy != null) {
      final localIds = <String>{
        ...currentEntries.keys,
        for (final copy in keptCopies) copy.id,
        for (final op in executed.succeeded)
          if (op.kind == SyncOperationKind.download) op.id,
      };
      baselineEntries.removeWhere((id, _) => !localIds.contains(id));
    }
    return baselineEntries;
  }
}
