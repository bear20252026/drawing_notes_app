// DN-204（第三轮专家审计 2026-10-13）：恢复换根之后的同步基线隔离。
//
// 问题形状：数据根默认在 Application Support，而同步基线 `sync_state.json`
// 写在**数据根之外**的 Documents（见 `FileSyncBaselineStore`）。「备份全部数据」
// 打包的是数据根，因此基线不会随备份一起回退。于是：
//   10-01 备份 A、B → 10-10 新增 C 并同步（基线记 A、B、C）
//   → 恢复 10-01 的备份（本地只剩 A、B，基线仍是 A、B、C）
//   → 下一轮同步把「基线有、本地无」的 C 推导成**用户删除**，真的 DELETE 掉云端 C。
// 即使 ZIP 校验、目录交换、失败回滚全部正确，这件事照样发生。
//
// 处置（按审计建议，而不是简单清空基线）：换根后进入「恢复后首次同步」模式——
// **禁止自动推导删除墓碑**，先把两端差异摆给用户看，再由用户选择合并方向。
// 隔离判据不落在「谁记得写一条标记」上，而是从磁盘事实反推（见
// [PostRestoreBaselineGate]）：换根必然留下一个 `.old_<毫秒>` 恢复前快照（DN-208），
// 基线文件的修改时间早于该快照 ⇒ 这次换根之后一轮同步都没走完 ⇒ 基线不可信。
// 好处：崩溃窗口不存在（快照是换根动作自己产生的，不是第二步写出来的），
// 且成功回写基线后隔离**自动解除**，不需要任何清理代码。

/// 隔离态下用户裁决的**单次**调和方向。
///
/// 三者共同的前提：本轮**绝不产生删除墓碑**——从一份不描述当前数据根的基线
/// 推出来的「用户删除」不是删除，是恢复的副作用。
enum PostRestoreReconcile {
  /// 只报差异：不上传、不下载、不删除，也不推进基线/远端清单。
  /// 用户还没裁决时的默认姿态（`reconcile == null` 且处于隔离 ⇒ 按本项处理）。
  reportOnly,

  /// 合并：两端独有的都保留，同一篇两端都有且指纹不同时取较新版；仍不删云端。
  ///
  /// 如实记录一条残余：这里「取较新版」是纯时间戳 LWW，**不会**先给被盖掉的那一
  /// 侧留本地副本。隔离态下基线不可信，「两端都改过」这件事根本没有可靠的判据
  /// （`detectSyncConflicts` 正是靠基线才分得出「谁改过」），所以本条不冒充
  /// 冲突裁决；「无论哪边赢都先把两端内容各存一份」是批次 B（DN-201）的范围，
  /// 那里同时处理文档级 `If-Match`，不要在两处各起一套副本机制。
  merge,

  /// 以云端为准：只下载，本轮不上报任何本地内容。
  keepRemote,

  /// 用本机恢复出来的数据覆盖云端：只上传，不下载。
  /// 会让云端较新的版本被恢复出来的旧版替换——必须由用户显式选择并二次确认。
  overwriteRemote,
}

/// 恢复后两端差异（只读算出，供 UI 展示与用户裁决）。
class PostRestoreDiff {
  const PostRestoreDiff({
    this.localOnlyIds = const [],
    this.remoteOnlyIds = const [],
    this.divergedIds = const [],
    this.suppressedTombstoneIds = const [],
  });

  /// 本机恢复出来的库里有、云端清单上没有的篇目（「合并」/「覆盖云端」会上报）。
  final List<String> localOnlyIds;

  /// 云端有、恢复出来的库里没有的篇目（「合并」/「以云端为准」会下载）。
  final List<String> remoteOnlyIds;

  /// 两端都有、指纹（时间戳或大小）不同的篇目。
  final List<String> divergedIds;

  /// 旧基线本会推导成「用户已删除」因而本该删掉云端的篇目——本轮被拦下。
  /// 这一项是 DN-204 的直接证据，必须对用户可见。
  final List<String> suppressedTombstoneIds;

  bool get isEmpty =>
      localOnlyIds.isEmpty &&
      remoteOnlyIds.isEmpty &&
      divergedIds.isEmpty &&
      suppressedTombstoneIds.isEmpty;

  @override
  String toString() =>
      'PostRestoreDiff(localOnly=${localOnlyIds.length}, '
      'remoteOnly=${remoteOnlyIds.length}, diverged=${divergedIds.length}, '
      'suppressedDeletes=${suppressedTombstoneIds.length})';
}

/// 「当前同步基线是否已因数据根换根而失效」的判据口。
abstract class PostRestoreBaselineGate {
  /// 基线比最近一次换根更早 ⇒ 基线不描述当前数据根 ⇒ 必须走恢复后首次同步。
  Future<bool> isBaselineStaleAfterRestore();
}

/// 恒可信闸门：供**没有恢复感知**的调用点显式声明（测试、以及未来任何
/// 「本场景不存在换根」的编排）。刻意不做默认值——把「没接线」和「已确认
/// 可信」写成同一种状态，正是本仓 S-04/DN-107 反复踩过的 fail-open 陷阱。
class AlwaysTrustedBaselineGate implements PostRestoreBaselineGate {
  const AlwaysTrustedBaselineGate();

  @override
  Future<bool> isBaselineStaleAfterRestore() async => false;
}
