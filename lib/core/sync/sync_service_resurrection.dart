// 由 Claude 团队生成 | Drawing Notes App
// SyncService 的 A3-2 一侧：云端已删除、本地只剩旧副本时**不再把它推回云端**。
// 同库 part——私有成员互相可见，拆文件不改行为。
part of 'sync_service.dart';

/// 复活抑制（任务 #22 的 A3-2，按业主批准的**甲**方案实施）。
///
/// 规则只有一条：[detectRemoteDeletes] 判为 `staleCopy` 的那些文档，本轮
/// **不发上传**。其余照旧——本机真改过的（`localHasEdits`）与无从比对的
/// （`unknowable`）都照常上传。因为「让删除赢」要删的是**用户本机的画布**，
/// 那是 §10 里的**乙**，本方案不含任何本地删除动作。
///
/// 为什么这一条是安全的：
/// - 不发上传 ⇒ 云端仍然没有这一篇，删除的意图得到尊重（旧行为是复活它）；
/// - 本地文件一个字节都不动，被按住的 id 进 [SyncResult] 供 UI **每轮持续可见**；
/// - 判据的因果腿（墓碑 `baseRev` + `baseSize`）**不依赖本地基线**。这一点是
///   设计上的关键：抑制上传之后基线里不会再有这篇（基线沿用来自云端清单），
///   如果只靠基线判「一字未动」，第二轮就会退化成 `unknowable ⇒` 又上传，
///   变成隔一轮复活一次的振荡。因果锚让这条状态能稳定成立下去。
///
/// 与 `applyConflictResolutions` 的关系：这些文档**不在** conflicts 里（远端
/// 没有条目时 `detectSyncConflicts` 直接 continue），所以不会撞上那条
/// 「计划里没有操作的冲突文档要补一条强制操作」的兜底——顺序上放在
/// keepBoth 副本保留之后、DN-204 隔离过滤之前，两条腿都不必重算判据。
extension SyncServiceResurrection on SyncService {
  /// 摘掉「把云端已删除的旧副本重新推上去」的那些上传操作。
  ///
  /// 返回被按住的 id（空表示本轮没有抑制任何东西，**计划对象原样返回**，
  /// 与项目里其它「无操作时不新建对象」的写法一致，便于既有引用相等断言）。
  ({SyncPlan plan, List<String> suppressedIds}) _holdStaleResurrections(
    SyncPlan plan,
    List<RemoteDeleteIssue> remoteDeletes,
  ) {
    if (remoteDeletes.isEmpty) {
      return (plan: plan, suppressedIds: const <String>[]);
    }
    final stale = <String>{
      for (final issue in remoteDeletes)
        if (issue.kind == RemoteDeleteKind.staleCopy) issue.docId,
    };
    if (stale.isEmpty) {
      return (plan: plan, suppressedIds: const <String>[]);
    }
    final suppressed = <String>[];
    final kept = <SyncOperation>[];
    for (final op in plan.operations) {
      if (op.kind == SyncOperationKind.upload && stale.contains(op.id)) {
        suppressed.add(op.id);
        continue;
      }
      kept.add(op);
    }
    if (suppressed.isEmpty) {
      return (plan: plan, suppressedIds: const <String>[]);
    }
    return (
      plan: SyncPlan(operations: kept),
      suppressedIds: List.unmodifiable(suppressed),
    );
  }
}
