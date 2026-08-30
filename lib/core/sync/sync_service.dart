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
  });

  final int uploaded;
  final int downloaded;
  final int deletedRemote;

  /// 本次同步中「本地与云端都有改动」的真冲突文档 id（LWW 由较新者胜，此列表仅为可见性）。
  final List<String> conflictedDocIds;

  bool get changed => uploaded > 0 || downloaded > 0 || deletedRemote > 0;

  @override
  String toString() =>
      'SyncResult(upload=$uploaded, download=$downloaded, '
      'deleteRemote=$deletedRemote, conflicts=${conflictedDocIds.length})';
}

/// WebDAV 本地优先同步服务。
class SyncService {
  SyncService({
    required this.transport,
    required this.documentStore,
    required this.baselineStore,
    this.planner = const SyncPlanner(),
    this.cipher = const NoopSyncCipher(),
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
    final remoteManifest = remoteBytes == null
        ? const SyncManifest()
        : SyncManifest.fromJson(
            jsonDecode(await cipher.openManifestJson(utf8.decode(remoteBytes)))
                as Map<String, dynamic>,
          );

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
    final plan = applyConflictResolutions(basePlan, conflicts, resolutions);
    await _preserveRemoteCopies(conflicts, resolutions);

    // 5. 执行。
    await _execute(plan, currentEntries, remoteManifest);

    // 6. 回写远端 manifest + 本地基线。
    _emit(SyncProgress.phase(SyncProgressPhase.writingManifest));
    final newEntries = <String, SyncSnapshot>{...remoteManifest.entries};
    for (final op in plan.operations) {
      if (op.kind == SyncOperationKind.deleteRemote) {
        newEntries.remove(op.id);
      } else if (op.kind == SyncOperationKind.upload) {
        final snap = currentEntries[op.id];
        if (snap != null) newEntries[op.id] = snap;
      }
      // download：远端快照已在新清单中（远端较新），无需改动。
    }
    final newManifest = SyncManifest(entries: newEntries);
    await transport.putBytes(
      manifestPath,
      utf8.encode(
        await cipher.sealManifestJson(jsonEncode(newManifest.toJson())),
      ),
    );
    await baselineStore.save(newManifest);

    final result = SyncResult(
      uploaded: plan.uploadCount,
      downloaded: plan.downloadCount,
      deletedRemote: plan.deleteCount,
      conflictedDocIds: List.unmodifiable(conflicts.map((c) => c.docId)),
    );
    _emit(SyncProgress.complete());
    return result;
  }

  /// keepBoth 裁决：把远端版本另存为本地副本（「两者皆保留」，不丢失任一侧）。
  /// 纯函数层仅把 keepBoth 视为「本地为主版本（强制上传）」；此处补齐「保留远端副本」。
  Future<void> _preserveRemoteCopies(
    List<SyncConflict> conflicts,
    Map<String, ConflictResolution> resolutions,
  ) async {
    for (final c in conflicts) {
      if (resolutions[c.docId] != ConflictResolution.keepBoth) continue;
      final remoteBytes = await transport.getBytes(cipher.remotePath(c.docId));
      if (remoteBytes == null) continue;
      final plain = await cipher.decryptDocumentBytes(remoteBytes, c.docId);
      final copyId =
          '${c.docId}~conflict~${DateTime.now().millisecondsSinceEpoch}';
      await documentStore.writeDocument(copyId, plain);
    }
  }

  /// 顺序执行计划中的操作。
  Future<void> _execute(
    SyncPlan plan,
    Map<String, SyncSnapshot> currentEntries,
    SyncManifest remoteManifest,
  ) async {
    final total = plan.operations.length;
    var done = 0;
    for (final op in plan.operations) {
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
      done++;
    }
  }

  /// 释放资源（交给上层组合根调用）。
  void close() => transport.close();
}
