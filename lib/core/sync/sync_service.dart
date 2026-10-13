// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 本地优先同步编排器（P3-W3，lead 收口）。
//
// 职责：串起
//   本地文档存储（SyncDocumentStore，字节 + 元数据）
//   WebDAV transport（WebDavSyncClient，GET/PUT/DELETE/MKCOL）
//   SyncBaselineStore（本地上次成功同步的 manifest，用于检测删除与脏标记）
//   SyncPlanner（纯逻辑比对 → 有序操作）
// 执行「拉远端 manifest → 比对 → 上传/下载/删远端 → 回写两端 manifest」闭环。
//
// 依赖全部可注入：单元/集成测试用内存 store + MockClient，零网络。

import 'dart:convert';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/post_restore_baseline.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';

/// 一个待同步文档的元数据（用于构成本地 manifest）。
class SyncDocMeta {
  const SyncDocMeta({
    required this.id,
    required this.updatedAt,
    required this.size,
    this.digest,
  });

  final String id;
  final int updatedAt; // epoch ms
  final int size; // 字节

  /// DN-206：内容摘要（SHA-256 前 16 位十六进制）。可空——存储层没算就不报，
  /// 同步侧按「不可比」处理，绝不当成「与远端不同」。
  final String? digest;
}

/// 本地文档清单快照（DN-107，P0 数据安全）。
///
/// 为什么要它：旧契约 `listDocuments()` 只能返回**读得出来**的文档，同步侧
/// 便把「清单里没有」推导成「用户删除了」——受密笔记一旦处于锁定态，再次
/// 同步就会生成删除墓碑并真的 `DELETE` 掉云端副本。
///
/// **读取不到 ≠ 用户删除。** 本类把三种状态拆开表达：
/// - [readable]：可参与内容比对与上传的文档；
/// - [unreadable]：**确认存在但当前不可读取**（锁定 / 权限不足 / 暂时不可
///   访问）。既不产生删除墓碑，也不参与上传，按基线快照原样保留，等它恢复
///   可读后再自然继续同步；
/// - 两者都不在：才是「本次确实看不到」，再结合基线判断是否为用户删除。
class SyncLocalInventory {
  const SyncLocalInventory({
    required this.readable,
    this.unreadable = const <String>{},
  });

  /// 可读取的文档元数据。
  final List<SyncDocMeta> readable;

  /// 确认存在但当前不可读取的文档 id。
  final Set<String> unreadable;

  /// 可读取文档的 id 集合（便捷）。
  Set<String> get readableIds => {for (final d in readable) d.id};
}

/// 本地文档存储门面（本地优先的「本地半边」）。
abstract class SyncDocumentStore {
  /// 列出本地文档清单快照。
  ///
  /// **必须如实报告「存在但不可读取」的那部分**（见 [SyncLocalInventory]）：
  /// 只报「读得出来的」，同步侧就会把锁定误判成删除（DN-107，P0）。
  Future<SyncLocalInventory> listDocuments();

  /// 读取文档字节；不存在返回 null。
  Future<Uint8List?> readDocument(String id);

  /// 写入文档字节（覆盖）。写入后文档 updatedAt 应保留字节内携带的时间。
  Future<void> writeDocument(String id, Uint8List bytes);

  /// 删除本地文档。
  Future<void> deleteDocument(String id);
}

/// 本地上次成功同步的 manifest 持久化（检测删除墓碑 + 脏标记）。
abstract class SyncBaselineStore {
  Future<SyncManifest?> load();
  Future<void> save(SyncManifest manifest);
}

/// 同步进度回调（设置页用于渲染进度条/状态文案）。
typedef SyncProgressCallback = void Function(SyncProgress progress);

/// 一次同步的结果摘要。
class SyncResult {
  const SyncResult({
    required this.uploaded,
    required this.downloaded,
    required this.deletedRemote,
    this.conflictedDocIds = const [],
    this.failedDocIds = const [],
    this.unreadableDocIds = const [],
    this.unprotectedRemoteDocIds = const [],
    this.skippedMissingDocIds = const [],
    this.remoteChangedDocIds = const [],
    this.conditionalWritesUnavailable = false,
    this.postRestorePolicy,
    this.postRestoreDiff,
  });

  final int uploaded;
  final int downloaded;
  final int deletedRemote;

  /// 本次同步中「本地与云端都有改动」的真冲突文档 id（LWW 由较新者胜，此列表仅为可见性）。
  final List<String> conflictedDocIds;

  /// 本轮执行失败的操作 id（M2：单操作隔离后失败项不中断整轮，
  /// 基线/远端清单均不回写它们，下轮自动重试；调用方可用此列表提示用户）。
  ///
  /// 注意：**「不回写」的判据不是本列表**，而是执行结果里「失败 ∪ 缺失跳过」
  /// 的并集（DN-001）——只盯着本列表会把 [skippedMissingDocIds] 那类
  /// 「一个字节都没同步却没抛错」的操作当成成功。
  final List<String> failedDocIds;

  /// [failedDocIds] 中因**解密认证失败**而失败的那部分（修复 1②）：
  /// 口令换过 ⇒ 云端旧密文永远解不开，重试不会变好，必须与网络抖动分开
  /// 上报，否则用户只看到一句泛化「同步失败」。也绝不当作当轮毒丸反复消耗。
  final List<String> unreadableDocIds;

  /// keepBoth 裁决下**没能保住的云端副本**（取不回 / 解不开 / 本地落副本失败）：
  /// 这些文档本轮**跳过上传**——拿本地版本 PUT 上去会毁掉云端唯一副本，
  /// 违反「冲突必须对用户可见、禁止静默覆盖任一侧」。单列一个字段而非并进
  /// [unreadableDocIds]：那不是「某操作执行失败」，而是为保护远端主动跳过，
  /// 混用会让下轮的处置口径漂移。
  final List<String> unprotectedRemoteDocIds;

  /// 本轮因「文件不存在」被**显式跳过**的文档 id（DN-001）：
  /// 上传腿 `readDocument` 返回 null（文件在 `listDocuments` 之后消失，或
  /// 保险库锁定——`note_block_doc_sync_store.readDocument` 的 N2 口径就是
  /// 「按缺失处理，不解锁受密内容」），下载腿远端 `getBytes` 返回 null（404）。
  ///
  /// 与 [unprotectedRemoteDocIds] 同一分工：**主动跳过 ≠ 执行失败**（见该字段
  /// 注释与本仓 keepBoth 守卫用例「跳过不等于执行失败」），故不并进
  /// [failedDocIds]。但保护力度完全一致——它们与失败项共用同一个
  /// 「本轮未同步」通道：清单不新增条目、基线不推进、不产生删除墓碑，
  /// 下轮按旧状态自动重试（自愈，不静默）。单列一份只为让调用方能给出
  /// 与「网络抖动」不同的可执行措辞（本地文件被删了/口令锁着/云端无此对象）。
  final List<String> skippedMissingDocIds;

  /// DN-204：本轮处于「恢复后基线隔离」时实际采用的调和方向；基线可信时为 null。
  ///
  /// [PostRestoreReconcile.reportOnly] 意味着**一个字节都没动**（不上传、不下载、
  /// 不删除、基线不推进）——UI 必须据此措辞，绝不能把它当「同步完成/已是最新」，
  /// 那是把「同步被按住」藏起来。
  final PostRestoreReconcile? postRestorePolicy;

  /// DN-204：隔离轮次算出的两端差异（含被拦下的删除墓碑清单）；正常轮次为 null。
  final PostRestoreDiff? postRestoreDiff;

  /// DN-201：本轮被服务端以 412 挡回来的文档——远端内容在本机读过之后又变了。
  /// 处置是**不覆盖、不删除**，并尽力把云端那一版另存成本地副本（两端都不丢）。
  ///
  /// 与 [failedDocIds] 分列的理由同 `unprotectedRemoteDocIds`：这不是「某个操作
  /// 执行失败」，而是「按并发纪律主动不让写」，措辞与下一步动作完全不同
  /// （失败⇒重试；这里⇒两份都在，需要你确认留哪份）。
  final List<String> remoteChangedDocIds;

  /// DN-201：本轮至少有一次覆盖写**没能条件化**（这台服务器不返回 ETag，
  /// 或不响应 HEAD）。此时「两台设备同时改同一篇笔记」防不住互相覆盖——
  /// 必须说出来，不能在注释里承认却在界面上假装安全。
  final bool conditionalWritesUnavailable;

  bool get changed => uploaded > 0 || downloaded > 0 || deletedRemote > 0;

  @override
  String toString() =>
      'SyncResult(upload=$uploaded, download=$downloaded, '
      'deleteRemote=$deletedRemote, conflicts=${conflictedDocIds.length}, '
      'failed=${failedDocIds.length}, unreadable=${unreadableDocIds.length}, '
      'unprotectedRemote=${unprotectedRemoteDocIds.length}, '
      'skippedMissing=${skippedMissingDocIds.length}, '
      'remoteChanged=${remoteChangedDocIds.length}, '
      'unconditionalWrite=$conditionalWritesUnavailable, '
      'postRestore=${postRestorePolicy?.name ?? 'none'})';
}

/// 单轮执行结果（M2：成功与失败的操作分离，清单回写只认成功项）。
///
/// 四种语义互斥且穷尽（DN-001 钉死前三条，DN-201 补第四条）：
/// - [succeeded]：真成功——两端字节确实落地，**只有它**能推进清单/基线。
/// - [failedIds]：真失败（网络/5xx/解密认证失败）——享受毒丸保护。
/// - [skippedMissingIds]：一侧「文件不存在」而显式跳过——同样享受保护。
/// - [remoteChangedIds]：条件写入被 412 挡回——按并发纪律**主动不让写**，
///   云端内容与本地版本都还在——同样享受保护。
/// 「不回写」的判据一律走 [notSyncedIds]（失败 ∪ 跳过 ∪ 被挡回），不要单独盯
/// [failedIds]：那正是 DN-001 伪成功的成因。
class _ExecuteOutcome {
  const _ExecuteOutcome({
    required this.succeeded,
    required this.failedIds,
    required this.unreadableIds,
    required this.skippedMissingIds,
    this.remoteChangedIds = const [],
    this.conditionalWritesUnavailable = false,
  });

  final List<SyncOperation> succeeded;
  final List<String> failedIds;

  /// 失败项中认证失败（密钥/AAD 与密文不匹配）的子集——确定性失败。
  final List<String> unreadableIds;

  /// 因「文件不存在」跳过的文档 id：上传腿本地读不到字节（文件在
  /// `listDocuments` 之后消失 / 保险库锁定），下载腿远端 404。
  /// 本轮没有任何数据落地，故与失败项同等处置，但原因不同、措辞不同。
  final List<String> skippedMissingIds;

  /// DN-201：条件写入被 412 挡回的文档——远端在我们读过之后又变了，本轮
  /// **没有覆盖也没有删除**，且（尽力地）已把云端那一版另存成本地副本。
  /// 与 [failedIds] 分列：那不是「操作执行失败」，而是「按并发纪律主动不让写」，
  /// 处置措辞完全不同（前者是重试，后者是两端都还留着、等你处理）。
  final List<String> remoteChangedIds;

  /// DN-201：本轮至少有一次覆盖写没能条件化（服务器不响应 HEAD、不给 ETag，
  /// 或探测本身失败）。此时多设备同改同一篇**防不住互相覆盖**，必须让用户知道。
  final bool conditionalWritesUnavailable;

  /// 本轮**没有任何字节落地**的 id 全集：清单不新增条目、基线不推进、
  /// 不产生删除墓碑的唯一判据（单一通道，避免第二套语义重叠的机制）。
  Set<String> get notSyncedIds => {
    ...failedIds,
    ...skippedMissingIds,
    ...remoteChangedIds,
  };
}

/// keepBoth 远端副本的取回结果（[_preserveRemoteCopies] 的返回形状）。
typedef _RemoteCopies = ({
  List<SyncSnapshot> copies,
  List<String> unprotectedDocIds,
});

/// WebDAV 本地优先同步服务。
class SyncService {
  SyncService({
    required this.transport,
    required this.documentStore,
    required this.baselineStore,
    this.planner = const SyncPlanner(),
    // S-04（审计 2026-09-27）：加密方案必选——默认 NoopSyncCipher（明文
    // 透传）是 fail-open 陷阱，未来新增调用点漏配即静默明文上云。现网
    // 调用点（设置页）与测试助手均显式传 cipher，收紧为 required。
    required this.cipher,
    this.conflictHandler = const LwwConflictHandler(),
    this.onProgress,
    required this.baselineGate,
    this.reconcile,
  });

  /// WebDAV 传输客户端。
  final WebDavSyncClient transport;

  /// 本地文档存储。
  final SyncDocumentStore documentStore;

  /// 本地同步基线持久化。
  final SyncBaselineStore baselineStore;

  final SyncPlanner planner;

  /// 端到端加密（默认 [NoopSyncCipher]：明文透传，保现有行为与既有测试）。
  final SyncCipher cipher;

  /// 冲突裁决处理器（默认 [LwwConflictHandler]：不覆盖，保 LWW 语义）。
  final ConflictHandler conflictHandler;

  /// 同步进度回调（默认为 null：不发射，保现有测试行为）。
  final SyncProgressCallback? onProgress;

  /// DN-204：恢复换根后基线是否失效的判据。**刻意 required**——「没接闸」与
  /// 「已确认基线可信」必须是两种写得出来的状态，合成一个就是 fail-open：
  /// 那正是本轮审计里「备份打包不到基线」这条能活到今天的成因。
  /// 没有恢复感知的调用点显式传 [AlwaysTrustedBaselineGate]。
  final PostRestoreBaselineGate baselineGate;

  /// DN-204：隔离态下用户裁决的调和方向；null = 用户还没选 ⇒ [PostRestoreReconcile.reportOnly]。
  final PostRestoreReconcile? reconcile;

  static const String manifestPath = 'manifest.json';

  /// DN-104：清单条件写入的最大尝试次数（1 次原始 + 2 次 412 后重试）。
  static const int _maxManifestCasAttempts = 3;

  void _emit(SyncProgress p) => onProgress?.call(p);

  /// 读取远端清单并带回 ETag（DN-104 条件写入的读侧）。
  ///
  /// B9 修复（审计 2026-09-07）：远端 manifest 是未认证/可被篡改数据——
  /// `jsonDecode(...) as Map` 无防护强转会抛裸 TypeError；改为类型检查后抛
  /// FormatException（与 sync_cipher 错误口径一致，调用方可统一处理）。
  /// 修复 1②：解不开远端 manifest 时 [cipher.openManifestJson] 抛
  /// [SyncKeyMismatchException] 直接终止整轮（fail-closed：宁可不同步，也不按
  /// 残缺清单行动；类型可判别 ⇒ SyncController 不对它做退避重试）。
  ///
  /// `etag` 为 null 表示服务器未返回 ETag ⇒ 不支持条件写入，调用方退回无条件
  /// PUT（不能假设所有 WebDAV 服务端行为相同）。
  ///
  /// `exists`（DN-202）：远端**是否已经有这份清单**。etag 为 null 有两种完全不同的
  /// 成因——「文件不存在（404）」与「存在但服务器不给 ETag」——而写侧的处置相反：
  /// 不存在时要 `If-None-Match: *`（首次创建不得盖掉别人刚创建的清单），存在而不给
  /// ETag 时才退回无条件写。少了这个标志就只能把两种情况当成一种。
  Future<({SyncManifest manifest, String? etag, bool exists})>
      _readRemoteManifest() async {
    final fetched = await transport.fetchBytes(manifestPath);
    if (fetched == null) {
      return (manifest: const SyncManifest(), etag: null, exists: false);
    }
    final manifestJson = await cipher.openManifestJson(
      utf8.decode(fetched.bytes),
    );
    final decoded = jsonDecode(manifestJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('远端清单格式损坏');
    }
    return (
      manifest: SyncManifest.fromJson(decoded),
      etag: fetched.etag,
      exists: true,
    );
  }

  /// 执行一次完整同步。
  ///
  /// 步骤：ensureCollection → GET 远端 manifest → 构本地 manifest（含删除墓碑）
  /// → plan → 执行操作 → 回写远端 + 本地 manifest 基线。
  ///
  /// DN-204：第 0 步先问闸门——数据根刚被备份恢复换掉时，基线描述的还是换根
  /// 之前的那批笔记，此时「基线有、本地无」不是用户删除，而是恢复的副作用。
  Future<SyncResult> syncNow() async {
    _emit(SyncProgress.starting());
    // 0. DN-204：基线是否已被换根甩在身后。用户没选方向时按 reportOnly 处理：
    //    只读、只报差异，一个字节都不写（既不误删云端，也不把恢复出来的旧版
    //    静默推上去）。
    final policy = await baselineGate.isBaselineStaleAfterRestore()
        ? (reconcile ?? PostRestoreReconcile.reportOnly)
        : null;
    if (policy == PostRestoreReconcile.reportOnly) {
      return _reportPostRestoreDiff();
    }
    // 1. 确保远端集合存在。
    _emit(SyncProgress.phase(SyncProgressPhase.connecting));
    await transport.ensureCollection();

    // 2. 拉远端 manifest（不存在则视为空）+ 记下 ETag 供 DN-104 条件写入。
    final remote = await _readRemoteManifest();
    final remoteManifest = remote.manifest;
    var manifestEtag = remote.etag;
    // DN-202：远端有没有这份清单，决定写侧用 `If-Match` 还是 `If-None-Match: *`。
    var manifestPresent = remote.exists;

    // 3. 构本地 manifest：当前文档 + 删除墓碑（基线有但当前无 → 墓碑）。
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
    final deletedIds = <String>{};
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
    }
    final localManifest = SyncManifest(
      entries: currentEntries,
      deletedIds: deletedIds,
    );

    // 4. 计划 + 冲突检测。
    _emit(SyncProgress.phase(SyncProgressPhase.planning));
    final basePlan = planner.plan(localManifest, remoteManifest);
    // DN-204：冲突判据同样不能用被换根甩在身后的基线——那份基线会让恢复出来
    // 的旧版本看起来像「本地一字未动、远端却更新」，从而触发一堆与事实无关的
    // 裁决。按首次同步处理：无基线 ⇒ 只看两端清单本身。
    final conflicts = detectSyncConflicts(
      currentEntries,
      remoteManifest,
      policy == null ? baseline : const SyncManifest(),
    );

    // 4b. 用户裁决（如注入了 handler）→ 覆盖为有效计划。
    final resolutions = conflicts.isEmpty
        ? const <String, ConflictResolution>{}
        : await conflictHandler.resolve(conflicts);
    // DN-206：有效裁决 = 用户显式选择 ∪ 平局/可疑时钟的兜底方向。
    // **留副本必须与计划用同一份**，否则「默认 keepBoth」这类兜底只改了方向、
    // 却没触发副本保留，平局下照样把云端那一版盖掉。
    final effective = effectiveConflictResolutions(conflicts, resolutions);
    final resolvedPlan = applyConflictResolutions(
      basePlan,
      conflicts,
      resolutions,
    );
    // keepBoth 的云端副本在**上传之前**取回（此时远端还是原始版本）；
    // 取不回或解不开的那些文档本轮不得上传，否则 PUT 会把云端唯一副本盖掉。
    final preserved = await _preserveRemoteCopies(conflicts, effective);
    final keptCopies = preserved.copies;
    final unprotected = preserved.unprotectedDocIds.toSet();
    final guardedPlan = unprotected.isEmpty
        ? resolvedPlan
        : SyncPlan(
            operations: [
              for (final op in resolvedPlan.operations)
                if (!(op.kind == SyncOperationKind.upload &&
                    unprotected.contains(op.id)))
                  op,
            ],
          );
    // DN-204：隔离态下按用户裁决的方向过滤。**删除墓碑任何方向都不放行**——
    // 它来自一份不描述当前数据根的基线，不是用户的删除意图。
    final plan = policy == null
        ? guardedPlan
        : _applyReconcile(guardedPlan, policy, currentEntries);

    // 5. 执行（M2：单操作隔离——失败/跳过项记入 outcome，不中断整轮）。
    final executed = await _execute(plan);
    // 「本轮没有任何字节落地」的 id 全集 = 真失败 ∪ 缺失跳过（DN-001）。
    // 清单/基线回写**只认这一个集合**：过去只看 failedIds，一侧文件不存在
    // （本地被删/保险库锁定、远端 404）的空操作会漏进成功项，把本地快照
    // 写进远端清单 + 基线 + 两端同指纹 ⇒ 下轮 planner「== → 忽略」与冲突检测
    // 「local == remote → continue」双双静默，云端永久缺内容且无自愈路径。
    final notSyncedIds = executed.notSyncedIds;

    // 6. 回写远端 manifest + 本地基线（只认成功项：失败/跳过操作两端都不回写，
    // 下轮按旧基线自动重试；明细进 SyncResult.failedDocIds 与
    // SyncResult.skippedMissingDocIds）。
    _emit(SyncProgress.phase(SyncProgressPhase.writingManifest));
    final newEntries = <String, SyncSnapshot>{...remoteManifest.entries};
    var uploaded = 0;
    var downloaded = 0;
    var deletedRemote = 0;
    for (final op in executed.succeeded) {
      switch (op.kind) {
        case SyncOperationKind.deleteRemote:
          newEntries.remove(op.id);
          deletedRemote++;
        case SyncOperationKind.upload:
          final snap = currentEntries[op.id];
          if (snap != null) newEntries[op.id] = snap;
          uploaded++;
        case SyncOperationKind.download:
          downloaded++;
        // download：远端快照已在新清单中（远端较新），无需改动。
      }
    }
    // DN-104：条件写入 + 有界重试。
    //
    // 远端清单是**多设备共享**的可变资源，而本流程是「GET manifest → 本地算
    // → PUT manifest」。两台设备都读到 M0、各自加上自己的新条目时，后写的
    // 那台会把前一台的条目整片覆盖：前一台的文档仍在远端（变成孤儿文件），
    // 却从清单里消失，其他设备再也发现不了它。
    //
    // 修法：写时带上读取时拿到的 ETag（`If-Match`）。被抢先则远端返回 412，
    // 此时**重新读取远端清单并把对方的新条目合并进来**（本轮我们改动过的 id
    // 以我们为准），再用新 ETag 重试，最多 [_maxManifestCasAttempts] 次。
    // 服务器不给 ETag（`manifestEtag == null`）时退回无条件写——兼容不支持
    // 条件写入的服务端，行为与既有实现一致。
    //
    // DN-202（第三轮专家审计 2026-10-13）：**首次创建**那条腿此前同样是无条件写。
    // 「资源不存在」时根本没有可读到的 ETag，于是 `ifMatch` 恒为 null ⇒ 两台设备
    // 同时第一次同步时，后写的那台把前一台刚创建的清单整片盖掉（前一台的条目从
    // 清单里消失，文件却还留在云端成为孤儿，别的设备再也发现不了它）。
    // 修法按审计给的两条分支分开处理：资源存在 ⇒ `If-Match`；资源不存在 ⇒
    // `If-None-Match: *`。412 一律走下面既有的「重读 + 合并 + 重试」。
    final touchedIds = <String>{
      for (final op in executed.succeeded)
        if (op.kind == SyncOperationKind.upload ||
            op.kind == SyncOperationKind.deleteRemote)
          op.id,
    };
    for (var attempt = 1; ; attempt++) {
      try {
        await transport.putBytes(
          manifestPath,
          utf8.encode(
            await cipher.sealManifestJson(
              jsonEncode(SyncManifest(entries: newEntries).toJson()),
            ),
          ),
          ifMatch: manifestEtag,
          overwrite: manifestPresent,
        );
        break;
      } on WebDavPreconditionFailedException {
        if (attempt >= _maxManifestCasAttempts) rethrow;
        final fresh = await _readRemoteManifest();
        manifestEtag = fresh.etag;
        // 412 之后远端的形状可能整个变了（别人刚创建 / 又被人删掉）：
        // 下一次尝试的条件头必须按**刚读到的事实**重算，不能沿用旧值。
        manifestPresent = fresh.exists;
        // 合并口径：不在本轮改动集里的 id 一律以**刚读到的远端**为准——
        // 对方的新增要保留，对方的删除也不能被我们按旧清单复活。
        final merged = <String, SyncSnapshot>{
          for (final e in fresh.manifest.entries.entries)
            if (!touchedIds.contains(e.key)) e.key: e.value,
        };
        for (final id in touchedIds) {
          final ours = newEntries[id];
          if (ours != null) merged[id] = ours; // 我们新增/更新；删除则不放入
        }
        newEntries
          ..clear()
          ..addAll(merged);
      }
    }
    // M4：keepBoth 副本只进本地基线（远端无此文件，进远端清单会导致
    // 其他设备下载 404 空转）；下轮它们作为本地新增正常上传。
    // 毒丸防误删：仅远端文档**没真正下载成功**时（真失败 / 远端 404 而跳过，
    // 两者都在 notSyncedIds 里），绝不能让它随 {...newEntries} 进入
    // 基线——否则下轮「本地无 + 基线有」会被误判为本地删除墓碑，把从未成功
    // 下载的远端文档 deleteRemote 掉（数据丢失；服务器对活对象误报 404 时
    // 更是直接删掉真实云端文件）。远端 manifest 保留该条目
    // （远端文件真实存在），基线剔除后下轮它仍是「仅远端 → download」自动重试。
    // 本地已有该文档的下载失败不受影响（墓碑推导要求本地缺失才会触发）。
    final baselineEntries = <String, SyncSnapshot>{...newEntries};
    for (final op in plan.operations) {
      if (op.kind == SyncOperationKind.download &&
          notSyncedIds.contains(op.id) &&
          !currentEntries.containsKey(op.id)) {
        baselineEntries.remove(op.id);
      }
    }
    for (final copy in keptCopies) {
      baselineEntries[copy.id] = copy;
    }
    // 没能保住云端副本的文档本轮一个字节都没同步（上传已跳过）：基线必须退回
    // 本轮开始时的值（远端清单仍保留该条目——远端文件真实存在）。若沿用
    // {...newEntries} 里的远端快照，基线等于谎称「云端那版就是上次同步态」，
    // 下轮冲突判据会退化成「远端没改过却比本地新」⇒ 用户不出裁决时的兜底
    // 方向正是上传 ⇒ 又变成静默盖掉云端。
    for (final id in unprotected) {
      final previous = baseline.entries[id];
      if (previous == null) {
        baselineEntries.remove(id);
      } else {
        baselineEntries[id] = previous;
      }
    }
    if (policy != null) {
      // DN-204：隔离轮的基线只能描述「本机现在真有」的那几篇。
      //
      // 沿用上面的 `{...newEntries}`（= 本轮结束时的云端清单）会把云端独有的
      // 篇目一并记进基线——而恢复出来的库里就是没有它们。下一轮（基线已推进，
      // 隔离解除）判据又是「基线有、本地无」⇒ 同一批删除墓碑重新生成，云端
      // 副本照旧被删掉，只是**延后一轮**发生。那正是本条要修的事，绝不能以
      // 「用户已经选了方向」为名把它放回管道里。
      //
      // 允许进基线的三来源：本轮列得出来的本地文档（含 DN-107 的「存在但读不到」，
      // 它按基线快照带回，本来就是本地文件）、keepBoth 刚落到本地的副本、
      // 本轮真下载成功的文档。
      final localIds = <String>{
        ...currentEntries.keys,
        for (final copy in keptCopies) copy.id,
        for (final op in executed.succeeded)
          if (op.kind == SyncOperationKind.download) op.id,
      };
      baselineEntries.removeWhere((id, _) => !localIds.contains(id));
    }
    // 已知两阶段提交窗口（M3·文档化取舍）：远端 manifest 已回写、本地基线
    // 未回写之间崩溃 → 两端 manifest 领先于本地基线。后果全部幂等无害：
    // - 本轮已上传成功的文档：下轮按旧基线重传一次（服务端覆盖同内容）；
    // - 本轮已下载成功的文档：本地已被 writeDocument 写入（自带文档时间戳），
    //   下轮重新判为「仅远端」再下一次；
    // - keepBoth 副本：下轮作为本地新增补传。
    // 选择不引入 WAL/journal：窗口仅毫秒级且收敛代价为一次幂等重传，
    // 复杂度收益不成比例。若未来改动基线结构，需重新评估此窗口。
    await baselineStore.save(SyncManifest(entries: baselineEntries));

    final result = SyncResult(
      uploaded: uploaded,
      downloaded: downloaded,
      deletedRemote: deletedRemote,
      conflictedDocIds: List.unmodifiable(conflicts.map((c) => c.docId)),
      failedDocIds: List.unmodifiable(executed.failedIds),
      unreadableDocIds: List.unmodifiable(executed.unreadableIds),
      unprotectedRemoteDocIds: List.unmodifiable(preserved.unprotectedDocIds),
      skippedMissingDocIds: List.unmodifiable(executed.skippedMissingIds),
      remoteChangedDocIds: List.unmodifiable(executed.remoteChangedIds),
      conditionalWritesUnavailable: executed.conditionalWritesUnavailable,
      postRestorePolicy: policy,
      postRestoreDiff: policy == null
          ? null
          : _diffOf(
              currentEntries: currentEntries,
              remoteManifest: remoteManifest,
              suppressedTombstoneIds: suppressedTombstones,
            ),
    );
    _emit(SyncProgress.complete());
    return result;
  }

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

  /// keepBoth 裁决：把远端版本另存为本地副本（「两者皆保留」，不丢失任一侧）。
  /// 纯函数层仅把 keepBoth 视为「本地为主版本（强制上传）」；此处补齐「保留远端副本」。
  /// P2 修复双问题：①旧 `copyId` 含 `~`，下游 `_pathFor` 白名单
  /// （`^[A-Za-z0-9_-]+$`）直接抛错——keepBoth 必崩；②`c.docId` 来自
  /// 未认证远端 manifest，消毒后才可作本地 id。单副本失败隔离，不中断整轮。
  /// M4：返回成功创建的副本快照（调用方并入本地基线；远端清单不含它们）。
  ///
  /// 诚实化修复（本批）：**没能保住云端副本**（取回抛错 / 解不开 / 本地落副本
  /// 失败）的文档 id 一并上报，调用方据此跳过该文档本轮的上传——旧写法静默
  /// `continue` 后本地版本照样 PUT，等于用「两者皆保留」的名义毁掉云端唯一副本，
  /// 违反「冲突必须对用户可见、禁止静默覆盖任一侧」。GET 返回 null（404，云端
  /// 根本没有这个对象，多发生在清单已回写、文档未落盘的崩溃窗口）时不跳过：
  /// 上传不会覆盖任何内容，跳过反而让该文档永远同步不上。
  /// 每轮对每个这类文档只尝试一次 GET，不抛异常、不进退避重试链。
  ///
  /// [effectiveResolutions]（DN-206）：传入的是 [effectiveConflictResolutions]
  /// 的结果而**不是**用户原始裁决——平局兜底方向也是 keepBoth，副本保留必须
  /// 认它，否则「默认不偏向任何一侧」会变成「默认把云端盖掉」。
  Future<_RemoteCopies> _preserveRemoteCopies(
    List<SyncConflict> conflicts,
    Map<String, ConflictResolution> effectiveResolutions,
  ) async {
    final copies = <SyncSnapshot>[];
    final unprotected = <String>[];
    for (final c in conflicts) {
      if (effectiveResolutions[c.docId] != ConflictResolution.keepBoth) continue;
      final Uint8List? remoteBytes;
      try {
        remoteBytes = await transport.getBytes(cipher.remotePath(c.docId));
      } catch (_) {
        // 取不回（网络/5xx/重定向门禁/超时）⇒ 无法确认云端副本内容，
        // 不能拿本地版本盖上去；本轮跳过该文档上传并在摘要里可见。
        if (!unprotected.contains(c.docId)) unprotected.add(c.docId);
        continue;
      }
      if (remoteBytes == null) continue; // 云端无此对象，无可覆盖。
      try {
        final plain = await cipher.decryptDocumentBytes(remoteBytes, c.docId);
        final copyId = _safeCopyId(c.docId);
        await documentStore.writeDocument(copyId, plain);
        copies.add(
          SyncSnapshot(
            id: copyId,
            updatedAt: c.remoteUpdatedAt,
            size: plain.length,
          ),
        );
      } catch (_) {
        // 解不开（口令/密钥错配、密文损坏）或本地落副本失败 ⇒ keepBoth 无法
        // 兑现，同上不覆盖云端。失败原因分型由摘要文案统一给出。
        if (!unprotected.contains(c.docId)) unprotected.add(c.docId);
      }
    }
    return (copies: copies, unprotectedDocIds: unprotected);
  }

  /// 冲突副本 id 消毒：仅保留白名单字符（下游 `_pathFor` 同口径），
  /// 截断 64 字，时间戳保唯一。
  static String _safeCopyId(String docId) {
    final clean = docId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final stem = clean.isEmpty
        ? 'doc'
        : clean.substring(0, clean.length.clamp(0, 64));
    return '$stem-conflict-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// DN-201：HEAD 探测远端版本；**探不到就按「无法条件写」返回，不抛出**。
  ///
  /// 为什么不因为一次探测失败就把这篇判成同步失败：那等于新增一个「服务器响应
  /// 形态不合我意 ⇒ 断同步」的开关，比现状（无条件写）更糟。探测失败退回既有
  /// 行为，同时把「这台服务器上防不住并发覆盖」如实上报到界面——诚实的降级
  /// 好过假装安全的降级。
  Future<WebDavPresence> _probeOrUnknown(String relativePath) async {
    try {
      return await transport.probe(relativePath);
    } catch (_) {
      return const WebDavPresence.presentUnknown();
    }
  }

  /// DN-201：条件写入被 412 挡回之后的处置——**先保两端，再上报，绝不重试覆盖**。
  ///
  /// 412 说的是一件很具体的事：远端这一篇在本机读过之后又被别的设备改过。此刻
  /// 本机手里一份、云端一份，是两份都真实存在的内容，任何一边的「顺手覆盖」都是
  /// 数据丢失。所以把云端那一版另存成本地副本（与 keepBoth 同一套 `_safeCopyId`
  /// 命名与消毒），id 记进 remoteChangedIds；连副本都没能留住时记 failedIds，
  /// 享受「清单/基线都不回写、下轮重试」的毒丸保护。
  ///
  /// 两条腿都在本轮**不写云端**——remoteChangedIds 与 failedIds 都并进
  /// `_ExecuteOutcome.notSyncedIds`，绝不出现「远端没动，本地清单却说同步过了」。
  Future<void> _handleRejectedWrite(
    String docId,
    String relativePath,
    List<String> remoteChangedIds,
    List<String> failedIds,
  ) async {
    try {
      final remoteBytes = await transport.getBytes(relativePath);
      if (remoteBytes == null) {
        // 远端对象在这一步已经消失：没有要保护的内容，本轮按未同步收工。
        if (!remoteChangedIds.contains(docId)) remoteChangedIds.add(docId);
        return;
      }
      final plain = await cipher.decryptDocumentBytes(remoteBytes, docId);
      await documentStore.writeDocument(_safeCopyId(docId), plain);
      if (!remoteChangedIds.contains(docId)) remoteChangedIds.add(docId);
    } on SyncKeyMismatchException {
      rethrow; // 确定性失败：交给外层，同时进 unreadableIds 供 UI 给可执行文案
    } catch (_) {
      if (!failedIds.contains(docId)) failedIds.add(docId);
    }
  }

  /// 顺序执行计划中的操作（M2 毒丸防护 + DN-001「缺失不是成功」）。
  ///
  /// 每个操作独立 try/catch：单个文档因网络抖动/远端 5xx/数据损坏失败时，
  /// 只记入失败表并继续其余操作，不中断整轮；调用方按成功项回写清单，
  /// 失败项下轮自动重试。失败有意不记 AuditLogger（审计链 1000 条封顶，
  /// 大批量失败会挤掉安全事件；失败明细经 SyncResult.failedDocIds 上报 UI）。
  ///
  /// DN-001：**「文件不存在」是显式结果，不是成功**。上传腿 `readDocument`
  /// 返回 null（`listDocuments` 之后文件消失，或保险库锁定——
  /// `note_block_doc_sync_store` 按缺失处理、不解锁受密内容）、下载腿远端
  /// `getBytes` 返回 null（404）时本轮一个字节都没落地：
  /// - 计成功 ⇒ 回写把**本地快照**盖进远端清单，一轮内清单+基线+本地三者
  ///   同指纹 ⇒ 冲突检测 `local == remote → continue` 与 planner「== → 忽略」
  ///   双双静默，云端永久缺该文档、UI 谎报「已同步」、无自愈路径；
  /// - 下载侧计成功还会让它带着远端条目进基线，下轮「本地无 + 基线有」被
  ///   误判成本地删除墓碑 ⇒ DELETE 掉真实云端文件。
  /// 因此这类 id 单列 [skippedMissingIds]，与失败项一样进
  /// `_ExecuteOutcome.notSyncedIds`（不回写清单/基线、不产生墓碑、下轮重试），
  /// 但**不**并进 `failedIds`——「跳过 ≠ 执行失败」是本仓既有分工（keepBoth
  /// 的 `unprotectedRemoteDocIds` 同理），混淆会让调用方给出错的处置措辞。
  Future<_ExecuteOutcome> _execute(SyncPlan plan) async {
    final total = plan.operations.length;
    final succeeded = <SyncOperation>[];
    final failedIds = <String>[];
    final unreadableIds = <String>[];
    final skippedMissingIds = <String>[];
    // DN-201：条件写入被服务端挡回（412）的文档——远端在我们读过之后又变了。
    final remoteChangedIds = <String>[];
    // DN-201：这一轮里至少有一次覆盖写没能条件化（服务器不响应 HEAD / 不给
    // ETag）。这不是「同步慢一点」，而是「多设备同改同一篇防不住互相覆盖」，
    // 必须让用户看见，不能只在代码注释里承认。
    var conditionalWritesUnavailable = false;
    var done = 0;
    for (final op in plan.operations) {
      // 只有真的把字节搬到另一端的操作才计入 succeeded（DN-001）。
      var landed = false;
      try {
        switch (op.kind) {
          case SyncOperationKind.upload:
            _emit(
              SyncProgress.phase(
                SyncProgressPhase.uploading,
                doneCount: done,
                totalCount: total,
                currentDocId: op.id,
              ),
            );
            final bytes = await documentStore.readDocument(op.id);
            if (bytes == null) {
              if (!skippedMissingIds.contains(op.id)) {
                skippedMissingIds.add(op.id);
              }
            } else {
              final wire = await cipher.encryptDocumentBytes(bytes, op.id);
              final path = cipher.remotePath(op.id);
              // DN-201：覆盖一篇云端笔记之前先问一次它的版本。清单里的
              // updatedAt/size 是我们自己算的指纹，服务端不认——能认的只有 ETag。
              final probe = await _probeOrUnknown(path);
              if (!probe.canConditionallyWrite && !probe.isAbsent) {
                conditionalWritesUnavailable = true;
              }
              try {
                await transport.putBytes(
                  path,
                  wire,
                  ifMatch: probe.etag,
                  // 探测时远端没有这个对象 ⇒ 只创建、不覆盖：从探测到落笔之间
                  // 别的设备可能刚把它写上来，无条件 PUT 会盖掉对方唯一的副本。
                  overwrite: !probe.isAbsent,
                );
                landed = true;
              } on WebDavPreconditionFailedException {
                await _handleRejectedWrite(
                  op.id,
                  path,
                  remoteChangedIds,
                  failedIds,
                );
              }
            }
            break;
          case SyncOperationKind.download:
            _emit(
              SyncProgress.phase(
                SyncProgressPhase.downloading,
                doneCount: done,
                totalCount: total,
                currentDocId: op.id,
              ),
            );
            final bytes = await transport.getBytes(cipher.remotePath(op.id));
            if (bytes == null) {
              if (!skippedMissingIds.contains(op.id)) {
                skippedMissingIds.add(op.id);
              }
            } else {
              final plain = await cipher.decryptDocumentBytes(bytes, op.id);
              await documentStore.writeDocument(op.id, plain);
              landed = true;
            }
            break;
          case SyncOperationKind.deleteRemote:
            _emit(
              SyncProgress.phase(
                SyncProgressPhase.deleting,
                doneCount: done,
                totalCount: total,
                currentDocId: op.id,
              ),
            );
            // 无「缺失」分支：deleteRemaining 对 404 返回 true（传输层既定
            // 契约「404 视为已删除」，幂等），本就该计成功并清掉清单条目。
            // DN-201：删除同样是一种覆盖。云端这一版如果在本机读过之后又被
            // 别的设备改过，把它删掉就是删掉一份本机从未见过的内容 ⇒ 带
            // `If-Match`，被挡回就不删（清单/基线都不回写，下轮重算）。
            final path = cipher.remotePath(op.id);
            final probe = await _probeOrUnknown(path);
            if (!probe.canConditionallyWrite && !probe.isAbsent) {
              conditionalWritesUnavailable = true;
            }
            try {
              await transport.deleteRemaining(path, ifMatch: probe.etag);
              landed = true;
            } on WebDavPreconditionFailedException {
              if (!remoteChangedIds.contains(op.id)) {
                remoteChangedIds.add(op.id);
              }
            }
            break;
        }
        if (landed) succeeded.add(op);
      } on SyncKeyMismatchException {
        // 修复 1②：认证失败是确定性结果——本轮对它只做一次尝试（循环自然
        // 向前，不重跑），并单独记账供 UI 给出「换回旧口令 / 全量重传」的
        // 可执行文案；仍留在 failedIds 里享受「不回写清单」的毒丸保护
        // （绝不因此删远端或覆盖任一侧）。
        if (!failedIds.contains(op.id)) failedIds.add(op.id);
        if (!unreadableIds.contains(op.id)) unreadableIds.add(op.id);
      } catch (_) {
        // 毒丸隔离：记失败、继续下一操作（manifest 回写跳过此项）。
        if (!failedIds.contains(op.id)) failedIds.add(op.id);
      }
      done++;
    }
    return _ExecuteOutcome(
      succeeded: succeeded,
      failedIds: failedIds,
      unreadableIds: unreadableIds,
      skippedMissingIds: skippedMissingIds,
      remoteChangedIds: remoteChangedIds,
      conditionalWritesUnavailable: conditionalWritesUnavailable,
    );
  }

  /// 释放资源（交给上层组合根调用）。
  void close() => transport.close();
}
