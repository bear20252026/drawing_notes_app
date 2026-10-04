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
  });

  final String id;
  final int updatedAt; // epoch ms
  final int size; // 字节
}

/// 本地文档存储门面（本地优先的「本地半边」）。
abstract class SyncDocumentStore {
  /// 列出当前所有文档的元数据（无文档返回空列表）。
  Future<List<SyncDocMeta>> listDocuments();

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
  });

  final int uploaded;
  final int downloaded;
  final int deletedRemote;

  /// 本次同步中「本地与云端都有改动」的真冲突文档 id（LWW 由较新者胜，此列表仅为可见性）。
  final List<String> conflictedDocIds;

  /// 本轮执行失败的操作 id（M2：单操作隔离后失败项不中断整轮，
  /// 基线/远端清单均不回写它们，下轮自动重试；调用方可用此列表提示用户）。
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

  bool get changed => uploaded > 0 || downloaded > 0 || deletedRemote > 0;

  @override
  String toString() =>
      'SyncResult(upload=$uploaded, download=$downloaded, '
      'deleteRemote=$deletedRemote, conflicts=${conflictedDocIds.length}, '
      'failed=${failedDocIds.length}, unreadable=${unreadableDocIds.length}, '
      'unprotectedRemote=${unprotectedRemoteDocIds.length})';
}

/// 单轮执行结果（M2：成功与失败的操作分离，清单回写只认成功项）。
class _ExecuteOutcome {
  const _ExecuteOutcome({
    required this.succeeded,
    required this.failedIds,
    required this.unreadableIds,
  });

  final List<SyncOperation> succeeded;
  final List<String> failedIds;

  /// 失败项中认证失败（密钥/AAD 与密文不匹配）的子集——确定性失败。
  final List<String> unreadableIds;
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

  static const String manifestPath = 'manifest.json';

  void _emit(SyncProgress p) => onProgress?.call(p);

  /// 执行一次完整同步。
  ///
  /// 步骤：ensureCollection → GET 远端 manifest → 构本地 manifest（含删除墓碑）
  /// → plan → 执行操作 → 回写远端 + 本地 manifest 基线。
  Future<SyncResult> syncNow() async {
    _emit(SyncProgress.starting());
    // 1. 确保远端集合存在。
    _emit(SyncProgress.phase(SyncProgressPhase.connecting));
    await transport.ensureCollection();

    // 2. 拉远端 manifest（不存在则视为空）。
    final remoteBytes = await transport.getBytes(manifestPath);
    // B9 修复（审计 2026-09-07）：远端 manifest 是未认证/可被篡改数据——
    // `jsonDecode(...) as Map` 无防护强转会抛裸 TypeError；改为类型检查后
    // 抛 FormatException（与 sync_cipher 错误口径一致，调用方可统一处理）。
    SyncManifest remoteManifest;
    if (remoteBytes == null) {
      remoteManifest = const SyncManifest();
    } else {
      final manifestJson = await cipher.openManifestJson(
        utf8.decode(remoteBytes),
      );
      // 修复 1②：解不开远端 manifest 时上面抛 [SyncKeyMismatchException]
      // 直接终止整轮（既有 fail-closed 语义：宁可不同步，也不按残缺清单
      // 行动）。类型可判别 ⇒ SyncController 不再对它做退避重试。
      final decoded = jsonDecode(manifestJson);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('远端清单格式损坏');
      }
      remoteManifest = SyncManifest.fromJson(decoded);
    }

    // 3. 构本地 manifest：当前文档 + 删除墓碑（基线有但当前无 → 墓碑）。
    final currentDocs = await documentStore.listDocuments();
    final currentEntries = <String, SyncSnapshot>{
      for (final d in currentDocs)
        d.id: SyncSnapshot(id: d.id, updatedAt: d.updatedAt, size: d.size),
    };
    final baseline = await baselineStore.load() ?? const SyncManifest();
    final deletedIds = <String>{};
    for (final id in baseline.entries.keys) {
      if (!currentEntries.containsKey(id) &&
          !baseline.deletedIds.contains(id)) {
        deletedIds.add(id);
      }
    }
    final localManifest = SyncManifest(
      entries: currentEntries,
      deletedIds: deletedIds,
    );

    // 4. 计划 + 冲突检测。
    _emit(SyncProgress.phase(SyncProgressPhase.planning));
    final basePlan = planner.plan(localManifest, remoteManifest);
    final conflicts = detectSyncConflicts(
      currentEntries,
      remoteManifest,
      baseline,
    );

    // 4b. 用户裁决（如注入了 handler）→ 覆盖为有效计划。
    final resolutions = conflicts.isEmpty
        ? const <String, ConflictResolution>{}
        : await conflictHandler.resolve(conflicts);
    final resolvedPlan = applyConflictResolutions(
      basePlan,
      conflicts,
      resolutions,
    );
    // keepBoth 的云端副本在**上传之前**取回（此时远端还是原始版本）；
    // 取不回或解不开的那些文档本轮不得上传，否则 PUT 会把云端唯一副本盖掉。
    final preserved = await _preserveRemoteCopies(conflicts, resolutions);
    final keptCopies = preserved.copies;
    final unprotected = preserved.unprotectedDocIds.toSet();
    final plan = unprotected.isEmpty
        ? resolvedPlan
        : SyncPlan(
            operations: [
              for (final op in resolvedPlan.operations)
                if (!(op.kind == SyncOperationKind.upload &&
                    unprotected.contains(op.id)))
                  op,
            ],
          );

    // 5. 执行（M2：单操作隔离——失败项记入 outcome，不中断整轮）。
    final executed = await _execute(plan);
    final failedIds = executed.failedIds.toSet();

    // 6. 回写远端 manifest + 本地基线（只认成功项：失败操作两端都不回写，
    // 下轮按旧基线自动重试；失败明细进 SyncResult.failedDocIds）。
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
    final newManifest = SyncManifest(entries: newEntries);
    await transport.putBytes(
      manifestPath,
      utf8.encode(
        await cipher.sealManifestJson(jsonEncode(newManifest.toJson())),
      ),
    );
    // M4：keepBoth 副本只进本地基线（远端无此文件，进远端清单会导致
    // 其他设备下载 404 空转）；下轮它们作为本地新增正常上传。
    // 毒丸防误删：仅远端文档下载失败时，绝不能让它随 {...newEntries} 进入
    // 基线——否则下轮「本地无 + 基线有」会被误判为本地删除墓碑，把从未成功
    // 下载的远端文档 deleteRemote 掉（数据丢失）。远端 manifest 保留该条目
    // （远端文件真实存在），基线剔除后下轮它仍是「仅远端 → download」自动重试。
    // 本地已有该文档的下载失败不受影响（墓碑推导要求本地缺失才会触发）。
    final baselineEntries = <String, SyncSnapshot>{...newEntries};
    for (final op in plan.operations) {
      if (op.kind == SyncOperationKind.download &&
          failedIds.contains(op.id) &&
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
    );
    _emit(SyncProgress.complete());
    return result;
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
  Future<_RemoteCopies> _preserveRemoteCopies(
    List<SyncConflict> conflicts,
    Map<String, ConflictResolution> resolutions,
  ) async {
    final copies = <SyncSnapshot>[];
    final unprotected = <String>[];
    for (final c in conflicts) {
      if (resolutions[c.docId] != ConflictResolution.keepBoth) continue;
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

  /// 顺序执行计划中的操作（M2 毒丸防护）。
  ///
  /// 每个操作独立 try/catch：单个文档因网络抖动/远端 5xx/数据损坏失败时，
  /// 只记入失败表并继续其余操作，不中断整轮；调用方按成功项回写清单，
  /// 失败项下轮自动重试。失败有意不记 AuditLogger（审计链 1000 条封顶，
  /// 大批量失败会挤掉安全事件；失败明细经 SyncResult.failedDocIds 上报 UI）。
  Future<_ExecuteOutcome> _execute(SyncPlan plan) async {
    final total = plan.operations.length;
    final succeeded = <SyncOperation>[];
    final failedIds = <String>[];
    final unreadableIds = <String>[];
    var done = 0;
    for (final op in plan.operations) {
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
            if (bytes != null) {
              final wire = await cipher.encryptDocumentBytes(bytes, op.id);
              await transport.putBytes(cipher.remotePath(op.id), wire);
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
            if (bytes != null) {
              final plain = await cipher.decryptDocumentBytes(bytes, op.id);
              await documentStore.writeDocument(op.id, plain);
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
            await transport.deleteRemaining(cipher.remotePath(op.id));
            break;
        }
        succeeded.add(op);
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
    );
  }

  /// 释放资源（交给上层组合根调用）。
  void close() => transport.close();
}
