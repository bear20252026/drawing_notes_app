// P2 修复回归锁（审计 2026-10）：时钟偏快的一端用未来时间戳把 LWW 变成
// 「静默覆盖另一侧的真实编辑」。
//
// 缺陷时序（B 是受害设备）：
//   1. A 设备时钟偏快 1 小时，上传文档 → 远端戳 = T（未来）。
//   2. B 下载该文档 → B 的基线也变成 T。
//   3. B 用真实时间继续编辑 → local = t < T，而 remote == base == T。
//   旧检测要求「两端都相对基线改过」才算冲突，remote == base ⇒ 不报冲突，
//   planner 判 local < remote ⇒ download ⇒ B 的新编辑被未来戳的旧文档无提示
//   覆盖，违反「冲突必须对用户可见、禁止静默覆盖任一侧」。
//
// 修复后的两条判据：结构性（一端相对基线未变却在比大小中赢 ⇒ 该端戳不可信，
// 不依赖时钟）+ 时钟性（远端戳晚于本地当前时间超容差），并让无用户裁决时的
// 兜底方向保住「真有改动的那一侧」。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';

const _base = 'https://dav.example.com/sync/';
const _hourMs = 60 * 60 * 1000;

Uint8List _bytes(int updatedAt) =>
    Uint8List.fromList(utf8.encode(jsonEncode({'updatedAt': updatedAt})));

SyncSnapshot _snap(String id, int updatedAt) =>
    SyncSnapshot(id: id, updatedAt: updatedAt, size: _bytes(updatedAt).length);

void main() {
  group('detectSyncConflicts：未来戳必须报冲突', () {
    test('B 的时序：remote == base（未来戳）+ local 真实编辑 → 冲突且默认保本地', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final future = now + _hourMs;

      final conflicts = detectSyncConflicts(
        {'d': _snap('d', now)}, // 本地真实时间的新编辑
        SyncManifest(entries: {'d': _snap('d', future)}), // 远端 = 未来戳
        SyncManifest(entries: {'d': _snap('d', future)}), // 基线 = 同一未来戳
        nowMs: now,
      );

      expect(conflicts, hasLength(1));
      final c = conflicts.single;
      expect(c.docId, 'd');
      expect(c.remoteNewer, isTrue, reason: '未来戳在比大小中总是赢');
      expect(c.remoteTimestampUntrusted, isTrue);
      expect(c.lwwTimestampSuspect, isTrue);
      // 默认裁决不得跟随那个不可信的时间戳。
      expect(c.suggestedResolution, ConflictResolution.keepLocal);
    });

    test('正常远端更新（远端确实相对基线改过、戳在过去）→ 不报冲突', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final conflicts = detectSyncConflicts(
        {'d': _snap('d', now - 2 * _hourMs)},
        SyncManifest(entries: {'d': _snap('d', now - _hourMs)}),
        SyncManifest(entries: {'d': _snap('d', now - 2 * _hourMs)}),
        nowMs: now,
      );
      expect(conflicts, isEmpty, reason: '仅远端改过 → 正常下载，不该打扰用户');
    });

    test('镜像时序：local == base 却因戳较新要覆盖远端真实改动 → 冲突且默认保远端', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final conflicts = detectSyncConflicts(
        {'d': _snap('d', now)}, // 本地一字未动（等于基线）
        SyncManifest(entries: {'d': _snap('d', now - _hourMs)}), // 远端改过，但戳偏旧
        SyncManifest(entries: {'d': _snap('d', now)}),
        nowMs: now,
      );

      expect(conflicts, hasLength(1));
      final c = conflicts.single;
      expect(c.localUnchangedSinceBaseline, isTrue);
      expect(c.lwwTimestampSuspect, isTrue);
      expect(c.suggestedResolution, ConflictResolution.keepRemote);
    });

    test('双边都改过 + 远端未来戳 → 冲突且默认不偏向未来戳', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final conflicts = detectSyncConflicts(
        {'d': _snap('d', now - 1000)},
        SyncManifest(entries: {'d': _snap('d', now + _hourMs)}),
        SyncManifest(entries: {'d': _snap('d', now - _hourMs)}),
        nowMs: now,
      );

      expect(conflicts, hasLength(1));
      expect(conflicts.single.remoteTimestampUntrusted, isTrue);
      expect(conflicts.single.suggestedResolution, ConflictResolution.keepLocal);
    });

    test('小漂移（远端戳晚于本地但在容差内）+ 远端确实改过 → 不误报', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final conflicts = detectSyncConflicts(
        {'d': _snap('d', now - 60_000)},
        SyncManifest(entries: {'d': _snap('d', now + 30_000)}),
        SyncManifest(entries: {'d': _snap('d', now - 120_000)}),
        nowMs: now,
      );

      // 双边都改过 → 仍是真冲突（该报），但时间戳不被判为可疑：
      // 默认裁决保持原 LWW 方向，避免正常双端编辑被反向硬掰。
      expect(conflicts, hasLength(1));
      expect(conflicts.single.lwwTimestampSuspect, isFalse);
      expect(conflicts.single.suggestedResolution, ConflictResolution.keepRemote);
    });
  });

  group('applyConflictResolutions：无用户裁决时不得沿用静默覆盖的方向', () {
    test('可疑戳 + 空裁决 → download 被兜底反转为 upload', () {
      final plan = SyncPlan(operations: [
        SyncOperation(kind: SyncOperationKind.download, id: 'd'),
      ]);
      final conflicts = [
        const SyncConflict(
          docId: 'd',
          localUpdatedAt: 100,
          localSize: 1,
          remoteUpdatedAt: 900,
          remoteSize: 1,
          remoteTimestampUntrusted: true,
        ),
      ];

      final out = applyConflictResolutions(plan, conflicts, const {});
      expect(out.operations.single.kind, SyncOperationKind.upload);
      // 用户显式选了保留云端，仍按用户意思走（不得自作主张）。
      final userChose = applyConflictResolutions(plan, conflicts, {
        'd': ConflictResolution.keepRemote,
      });
      expect(userChose.operations.single.kind, SyncOperationKind.download);
    });

    test('时间戳正常 + 空裁决 → 原计划原样返回（LWW 语义不变）', () {
      final plan = SyncPlan(operations: [
        SyncOperation(kind: SyncOperationKind.download, id: 'd'),
      ]);
      final conflicts = [
        const SyncConflict(
          docId: 'd',
          localUpdatedAt: 100,
          localSize: 1,
          remoteUpdatedAt: 900,
          remoteSize: 1,
        ),
      ];
      expect(applyConflictResolutions(plan, conflicts, const {}), same(plan));
    });
  });

  group('SyncService 端到端：未来戳不得吃掉本地编辑', () {
    test('默认 LwwConflictHandler（无弹窗）也保住本地版本', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final future = now + _hourMs;

      final store = _Docs()..docs['d'] = _bytes(now);
      final server = _Dav()
        ..files['d'] = _bytes(future)
        ..files['manifest.json'] = utf8.encode(
          jsonEncode({
            'entries': {
              'd': {'id': 'd', 'updatedAt': future, 'size': _bytes(future).length},
            },
            'deletedIds': <String>[],
          }),
        );
      final baseline = _Baseline()
        ..value = SyncManifest(entries: {'d': _snap('d', future)});

      final service = SyncService(
        transport: WebDavSyncClient(
          baseUrl: Uri.parse(_base),
          client: server.client(),
        ),
        documentStore: store,
        baselineStore: baseline,
        cipher: const NoopSyncCipher(),
        conflictHandler: const LwwConflictHandler(),
      );

      final r = await service.syncNow();

      // 冲突必须对用户可见。
      expect(r.conflictedDocIds, contains('d'));
      // 且不能被静默下载覆盖：本地版本上传出去，本地内容不变。
      expect(r.downloaded, 0);
      expect(r.uploaded, 1);
      expect(store.docUpdatedAt('d'), now, reason: '本地真实编辑必须存活');
      expect(server.docUpdatedAt('d'), now, reason: '云端收敛到真实编辑');
    });
  });
}

/// 内存文档存储：内容即 `{"updatedAt": ts}`。
class _Docs implements SyncDocumentStore {
  final Map<String, Uint8List> docs = {};

  int docUpdatedAt(String id) =>
      (jsonDecode(utf8.decode(docs[id]!)) as Map<String, dynamic>)['updatedAt']
          as int;

  @override
  Future<List<SyncDocMeta>> listDocuments() async => [
    for (final e in docs.entries)
      SyncDocMeta(id: e.key, updatedAt: docUpdatedAt(e.key), size: e.value.length),
  ];

  @override
  Future<Uint8List?> readDocument(String id) async => docs[id];

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async =>
      docs[id] = bytes;

  @override
  Future<void> deleteDocument(String id) async => docs.remove(id);
}

/// 内存 WebDAV 服务器（只用到 GET/PUT/MKCOL）。
class _Dav {
  final Map<String, List<int>> files = {};

  int docUpdatedAt(String id) =>
      (jsonDecode(utf8.decode(files[id]!)) as Map<String, dynamic>)['updatedAt']
          as int;

  MockClient client() => MockClient((request) async {
    final rel = request.url.path.replaceFirst('/sync/', '');
    switch (request.method) {
      case 'MKCOL':
        return http.Response('', 201);
      case 'GET':
        final body = files[rel];
        return body == null
            ? http.Response('', 404)
            : http.Response.bytes(body, 200);
      case 'PUT':
        files[rel] = request.bodyBytes;
        return http.Response('', 201);
      default:
        return http.Response('', 405);
    }
  });
}

class _Baseline implements SyncBaselineStore {
  SyncManifest? value;

  @override
  Future<SyncManifest?> load() async => value;

  @override
  Future<void> save(SyncManifest manifest) async => value = manifest;
}
