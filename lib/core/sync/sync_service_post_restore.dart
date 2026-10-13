// 由 Claude 团队生成 | Drawing Notes App
// SyncService 的 DN-204 一侧：恢复换根后的「隔离轮次」（只报差异、零写入）与
// 按用户裁决方向裁剪计划。同库 part——私有成员互相可见，拆文件不改行为。
part of 'sync_service.dart';

/// DN-204：恢复后基线隔离相关的编排步骤（`SyncService` 的一部分）。
extension SyncServicePostRestore on SyncService {
  /// DN-204：隔离轮次——**只读**。拉远端清单、算两端差异，然后原样返回。
  ///
  /// 刻意不走 `ensureCollection` / 不回写远端清单 / 不推进基线：用户还没裁决，
  /// 这一轮连「把云端某个文档登记成已知」的资格都没有。基线时间戳不前进，
  /// 隔离也就自然保持（见 `FilePostRestoreBaselineGate` 的判据）。
  Future<SyncResult> _reportPostRestoreDiff() async {
    _emit(SyncProgress.phase(SyncProgressPhase.planning));
    final remoteManifest = (await _readRemoteManifest()).manifest;
    final inventory = await documentStore.listDocuments();
    final currentEntries = <String, SyncSnapshot>{
      for (final d in inventory.readable)
        d.id: SyncSnapshot(
          id: d.id,
          updatedAt: d.updatedAt,
          size: d.size,
          digest: d.digest,
        ),
    };
    final baseline = await baselineStore.load() ?? const SyncManifest();
    // 「什么才算用户删除」的判据与 syncNow 第 3 步是同一条，包括 DN-107 的
    // 「存在但读不到」按基线快照带回——两处必须一起改，否则隔离轮会把锁定的
    // 笔记算进「云端有、本地没有」，用户一选合并就把它盖掉。
    final suppressed = <String>{};
    for (final id in baseline.entries.keys) {
      if (currentEntries.containsKey(id)) continue;
      if (inventory.unreadable.contains(id)) {
        final baselineSnap = baseline.entries[id];
        if (baselineSnap != null) currentEntries[id] = baselineSnap;
        continue;
      }
      if (baseline.deletedIds.contains(id)) continue;
      suppressed.add(id);
    }
    _emit(SyncProgress.complete());
    return SyncResult(
      uploaded: 0,
      downloaded: 0,
      deletedRemote: 0,
      postRestorePolicy: PostRestoreReconcile.reportOnly,
      postRestoreDiff: _diffOf(
        currentEntries: currentEntries,
        remoteManifest: remoteManifest,
        suppressedTombstoneIds: suppressed,
      ),
    );
  }

  /// 两端差异（DN-204 的展示数据；[suppressedTombstoneIds] 是本轮被拦下的删除墓碑）。
  PostRestoreDiff _diffOf({
    required Map<String, SyncSnapshot> currentEntries,
    required SyncManifest remoteManifest,
    required Set<String> suppressedTombstoneIds,
  }) {
    final localOnly = <String>[];
    final diverged = <String>[];
    for (final entry in currentEntries.entries) {
      final remote = remoteManifest.entries[entry.key];
      if (remote == null) {
        localOnly.add(entry.key);
      } else if (remote != entry.value) {
        diverged.add(entry.key);
      }
    }
    final remoteOnly = [
      for (final id in remoteManifest.entries.keys)
        if (!currentEntries.containsKey(id)) id,
    ];
    // 排序：这份清单要上屏给用户看，也是测试钉语义的锚点，不能随 Map 迭代序漂。
    int byId(String a, String b) => a.compareTo(b);
    return PostRestoreDiff(
      localOnlyIds: List.unmodifiable(localOnly..sort(byId)),
      remoteOnlyIds: List.unmodifiable(remoteOnly..sort(byId)),
      divergedIds: List.unmodifiable(diverged..sort(byId)),
      suppressedTombstoneIds: List.unmodifiable(
        suppressedTombstoneIds.toList()..sort(byId),
      ),
    );
  }

  /// DN-204：把计划裁剪到用户裁决的方向。删除墓碑在任何方向下都不放行
  /// （本轮的 `deletedIds` 已经为空，这里再兜一道：将来若有人改动墓碑来源，
  /// 这条过滤是最后一道闸）。
  ///
  /// 「覆盖云端」方向有一条必须说清的转写：两端都有、内容不同的那篇，planner
  /// 按时间戳会判成 download（云端更新），而这个方向的语义恰恰是「以本机恢复
  /// 出来的版本为准」⇒ 判成下载再丢弃，等于两边都不动、用户的选择不生效。
  /// 所以本地有内容的那篇 download 在这里**改写成 upload**；只有云端有的
  /// （本地根本没有）仍不动——它既不该被下载，更不该被删。
  SyncPlan _applyReconcile(
    SyncPlan plan,
    PostRestoreReconcile mode,
    Map<String, SyncSnapshot> currentEntries,
  ) {
    final uploads = <String>[];
    final downloads = <String>[];
    for (final op in plan.operations) {
      switch (op.kind) {
        case SyncOperationKind.deleteRemote:
          break;
        case SyncOperationKind.upload:
          if (mode == PostRestoreReconcile.merge ||
              mode == PostRestoreReconcile.overwriteRemote) {
            uploads.add(op.id);
          }
        case SyncOperationKind.download:
          if (mode == PostRestoreReconcile.merge ||
              mode == PostRestoreReconcile.keepRemote) {
            downloads.add(op.id);
          } else if (mode == PostRestoreReconcile.overwriteRemote &&
              currentEntries.containsKey(op.id)) {
            uploads.add(op.id);
          }
      }
    }
    uploads.sort();
    downloads.sort();
    return SyncPlan(
      operations: [
        for (final id in uploads)
          SyncOperation(kind: SyncOperationKind.upload, id: id),
        for (final id in downloads)
          SyncOperation(kind: SyncOperationKind.download, id: id),
      ],
    );
  }
}
