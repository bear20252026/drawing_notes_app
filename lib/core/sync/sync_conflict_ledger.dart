// 冲突台账（SYNC-003 前半句）：把每一轮检测到的冲突**持久化**下来，让「当时
// 发生了什么、按什么处理了」在同步结束、页面关掉、应用重启之后仍然可查。
//
// 为什么需要它：[SyncResult.conflictedDocIds] 只有 id，而且只活一轮——冲突是
// 唯一一类「程序替用户做了不可逆决定」的事件（keepLocal/keepRemote 都会盖掉
// 一侧的内容），用户回头想查「那篇到底怎么处理的」时，现有的任何出口都答不上来。
//
// 本文件只放纯值类型 + 契约 + 内存实现，不碰 io（与 `sync_push_waivers.dart`
// 同构）：文件实现见 `file_sync_conflict_ledger_store.dart`。
//
// ── 一条必须说清的边界：改判只能作用于「下一次」──────────────
// [ConflictLedgerEntry.resolutionOverride] 是用户对该文档的长期裁决，**不是**对已发生那次的
// 撤销。理由是物理的：keepLocal/keepRemote 一旦执行，输掉那一侧的字节就已经不存在
// （只有 keepBoth 会留副本），没有任何存储层操作能把它们找回来。所以台账提供的是
// 「下次这篇再冲突时按你选的方向走」，而不是「回到过去重选」——UI 必须照这个措辞，
// 不能暗示可以撤销。

import 'sync_conflict.dart';

/// 一条冲突台账记录：一篇文档的冲突历史 + 用户的选择。
///
/// 同一篇文档可以反复冲突（另一台设备又改了同一篇），所以记录是**按 docId 合并**
/// 的：[count] 与 [firstDetectedAtMs] 保留历史，[lastConflict] 是最近一次的事实。
class ConflictLedgerEntry {
  const ConflictLedgerEntry({
    required this.docId,
    required this.firstDetectedAtMs,
    required this.lastDetectedAtMs,
    required this.count,
    required this.lastConflict,
    this.resolutionOverride,
    this.overriddenAtMs,
  });

  final String docId;

  /// 这篇文档**第一次**报冲突的时刻（epoch ms）。
  final int firstDetectedAtMs;

  /// 最近一次报冲突的时刻（epoch ms）。
  final int lastDetectedAtMs;

  /// 累计冲突次数。>1 说明这篇在反复分叉——那正是最值得设 [resolutionOverride] 的情形
  /// （LWW 在两台设备之间来回打架，每次都要人手选一次）。
  final int count;

  /// 最近一次冲突的完整事实（含实际生效的裁决，见
  /// [SyncConflict.resolvedResolution]）。
  final SyncConflict lastConflict;

  /// 用户对该文档的改判：**下一次**这篇再冲突时按这个方向处理（null = 没有）。
  ///
  /// 为什么会有人需要它：同一篇笔记在两台设备上被同时编辑时，每次同步都会重新
  /// 弹一次裁决窗。记录一次长期方向，之后由 [SyncConflictLedgerStore] 的读取方
  /// （冲突处理器）直接采用，不再重复问。
  ///
  /// 它**不撤销**已经发生的那次覆盖——见文件头那条边界。
  final ConflictResolution? resolutionOverride;

  /// 改判设定的时刻（epoch ms）；没有改判时为 null。
  final int? overriddenAtMs;

  /// 有没有设定改判（UI 用，省掉各处 `resolutionOverride != null` 的重复）。
  bool get hasOverride => resolutionOverride != null;

  ConflictLedgerEntry copyWith({
    int? lastDetectedAtMs,
    int? count,
    SyncConflict? lastConflict,
    ConflictResolution? resolutionOverride,
    bool clearOverride = false,
    int? overriddenAtMs,
  }) {
    return ConflictLedgerEntry(
      docId: docId,
      firstDetectedAtMs: firstDetectedAtMs,
      lastDetectedAtMs: lastDetectedAtMs ?? this.lastDetectedAtMs,
      count: count ?? this.count,
      lastConflict: lastConflict ?? this.lastConflict,
      resolutionOverride: clearOverride
          ? null
          : (resolutionOverride ?? this.resolutionOverride),
      overriddenAtMs: clearOverride
          ? null
          : (overriddenAtMs ?? this.overriddenAtMs),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConflictLedgerEntry &&
          runtimeType == other.runtimeType &&
          docId == other.docId &&
          firstDetectedAtMs == other.firstDetectedAtMs &&
          lastDetectedAtMs == other.lastDetectedAtMs &&
          count == other.count &&
          lastConflict == other.lastConflict &&
          resolutionOverride == other.resolutionOverride &&
          overriddenAtMs == other.overriddenAtMs;

  @override
  int get hashCode => Object.hash(
    docId,
    firstDetectedAtMs,
    lastDetectedAtMs,
    count,
    lastConflict,
    resolutionOverride,
    overriddenAtMs,
  );

  @override
  String toString() =>
      'ConflictLedgerEntry($docId, count: $count, '
      'last: ${lastConflict.resolvedResolution?.name ?? 'auto'}, '
      'resolutionOverride: ${resolutionOverride?.name ?? 'none'})';
}

/// [ConflictLedgerEntry] 的读写契约。
///
/// 只有三个方法，因为只有三件事会发生：读台账、记一轮冲突、改判。
abstract class SyncConflictLedgerStore {
  /// 读出全部台账条目，按 [ConflictLedgerEntry.lastDetectedAtMs] **倒序**
  /// （最近发生的在最前）。空台账返回空列表。
  ///
  /// 读不出来（不存在 / 损坏）时返回空列表——见文件实现里对
  /// `sidecar_read_guard` 的引用：这与「文件不存在」不是一回事，后者要落审计。
  Future<List<ConflictLedgerEntry>> load();

  /// 把一轮同步检测到的冲突记进台账（**合并**，不是覆盖）。
  ///
  /// [conflicts] 里的 [SyncConflict.resolvedResolution] 应已由 SyncService 回填
  /// （未回填即是 null = 「没人选，按默认走了」，那是真实信息，照记）。
  ///
  /// 同一 docId 已有记录时：更新最近一次的事实、累加 [ConflictLedgerEntry.count]、
  /// 刷新 [ConflictLedgerEntry.lastDetectedAtMs]，**保留** firstDetectedAtMs。
  ///
  /// **绝不触碰 [ConflictLedgerEntry.resolutionOverride]**：改判是用户的长期决定，
  /// 不该因为又冲突了一次就被清掉。清除只能由 [setOverride] 显式进行。
  Future<void> record(List<SyncConflict> conflicts, {int? nowMs});

  /// 设定/清除一篇文档的改判（`resolution == null` 即清除）。
  ///
  /// 文档不在台账里时**不新增条目**：改判要依附于一条真实发生过的冲突记录，
  /// 否则台账里会出现只有改判、没有事实的空壳行。
  Future<void> setOverride(
    String docId,
    ConflictResolution? resolution, {
    int? nowMs,
  });
}

/// 内存实现（测试与未装配时的安全兜底）。
class MemorySyncConflictLedgerStore implements SyncConflictLedgerStore {
  MemorySyncConflictLedgerStore({List<ConflictLedgerEntry>? initial})
    : _entries = {
        for (final e in initial ?? const <ConflictLedgerEntry>[]) e.docId: e,
      };

  final Map<String, ConflictLedgerEntry> _entries;

  @override
  Future<List<ConflictLedgerEntry>> load() async {
    final list = [..._entries.values];
    list.sort((a, b) => b.lastDetectedAtMs.compareTo(a.lastDetectedAtMs));
    return List.unmodifiable(list);
  }

  @override
  Future<void> record(List<SyncConflict> conflicts, {int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    for (final c in conflicts) {
      final existing = _entries[c.docId];
      if (existing == null) {
        _entries[c.docId] = ConflictLedgerEntry(
          docId: c.docId,
          firstDetectedAtMs: now,
          lastDetectedAtMs: now,
          count: 1,
          lastConflict: c,
          resolutionOverride: null,
          overriddenAtMs: null,
        );
        continue;
      }
      _entries[c.docId] = existing.copyWith(
        lastDetectedAtMs: now,
        count: existing.count + 1,
        lastConflict: c,
      );
    }
  }

  @override
  Future<void> setOverride(
    String docId,
    ConflictResolution? resolution, {
    int? nowMs,
  }) async {
    final existing = _entries[docId];
    if (existing == null) return; // 见契约：不凭空造条目
    if (resolution == null) {
      _entries[docId] = existing.copyWith(clearOverride: true);
      return;
    }
    _entries[docId] = existing.copyWith(
      resolutionOverride: resolution,
      overriddenAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
