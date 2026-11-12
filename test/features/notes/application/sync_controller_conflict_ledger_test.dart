// SYNC-003 控制器接线锁：SyncController 把「一轮同步检测到的冲突」交给台账，
// 并把改判方向写回去。
//
// 这里只钉三件事，都是「错了不会报错、只会悄悄丢」的形状：
//  ① 成功的一轮之后台账里**有**那条冲突（`SyncResult.conflicts` → ledger）；
//  ② 失败的一轮**不记账**——失败轮次的基线没推进，记了就是假历史，下一轮还会
//     重新报同一冲突，用户会看到一条自己从未处理过的「历史」；
//  ③ 改判经控制器转发到注入 store（页面拿同一个控制器读台账，两条路径必须
//     落在同一份数据上）。
//
// 用真实本地回环 HTTP（transport 由控制器内建，无注入点）——与
// sync_controller_test.dart / sync_controller_rotation_test.dart 同口径：
// 刻意不装 TestWidgetsFlutterBinding，binding 会把 HttpClient 请求全量劫持为 400。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict_ledger.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';

final _saltBytes = Uint8List.fromList(List<int>.generate(16, (i) => 100 + i));
final _saltBase64 = base64Encode(_saltBytes);
const _passphrase = 'ledger-test-passphrase';
const _docId = 'doc-c';

class _Docs implements SyncDocumentStore {
  final Map<String, Uint8List> docs = {
    _docId: Uint8List.fromList(utf8.encode('{"id":"$_docId","updatedAt":20}')),
  };

  @override
  Future<SyncLocalInventory> listDocuments() async => SyncLocalInventory(
    readable: [
      for (final e in docs.entries)
        SyncDocMeta(id: e.key, updatedAt: 20, size: e.value.length),
    ],
  );

  @override
  Future<Uint8List?> readDocument(String id) async => docs[id];

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async =>
      docs[id] = bytes;

  @override
  Future<void> deleteDocument(String id) async => docs.remove(id);
}

class _Baseline implements SyncBaselineStore {
  SyncManifest? value;

  @override
  Future<SyncManifest?> load() async => value;

  @override
  Future<void> save(SyncManifest manifest) async => value = manifest;
}

/// 回环假 WebDAV：MKCOL→201、GET→按路径给密封字节（缺则 404）、PUT→201。
class _FakeDav {
  _FakeDav({
    required this.manifestBytes,
    required this.docBytes,
    this.alwaysFail = false,
  });

  /// null = 该路径返回 404（「远端没有这份清单」，与空正文不是一回事）。
  final List<int>? manifestBytes;
  final List<int> docBytes;
  final bool alwaysFail;
  late final HttpServer _server;

  Future<void> start() async {
    _server = await HttpServer.bind('127.0.0.1', 0);
    _server.listen((request) async {
      await request.drain<void>();
      if (alwaysFail) {
        request.response.statusCode = 500;
        await request.response.close();
        return;
      }
      final rel = request.uri.path.replaceFirst('/sync/', '');
      switch (request.method) {
        case 'MKCOL':
          request.response.statusCode = 201;
        case 'GET':
          final List<int>? body = rel == 'manifest.json'
              ? manifestBytes
              : (rel == _docPath ? docBytes : null);
          if (body == null) {
            request.response.statusCode = 404;
          } else {
            request.response.add(body);
          }
        case 'PUT':
          request.response.statusCode = 201;
        default:
          request.response.statusCode = 405;
      }
      await request.response.close();
    });
  }

  /// AesSyncCipher 的远端路径是 HMAC(key, docId)，不是 docId 本身。
  late String _docPath;

  Future<void> bindDocPath(SyncCipher cipher) async {
    _docPath = cipher.remotePath(_docId);
  }

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}/sync/');

  Future<void> close() => _server.close(force: true);
}

void main() {
  setUp(() => KekSessionCache.bypassIsolateForTests = true);
  tearDown(() => KekSessionCache.bypassIsolateForTests = false);

  test('loadConflictLedger / setConflictResolutionOverride 转发到注入 store',
      () async {
    final ledger = MemorySyncConflictLedgerStore();
    final controller = SyncController(
      configStore: WebDavConfigStore(),
      secretStore: MemorySyncSecretStore(),
      conflictLedgerStore: ledger,
    );

    expect(await controller.loadConflictLedger(), isEmpty);

    // 先记一条真实冲突，再改判——顺序不能反（未知 docId 不造条目）。
    await ledger.record([
      const SyncConflict(
        docId: _docId,
        localUpdatedAt: 20,
        localSize: 7,
        remoteUpdatedAt: 30,
        remoteSize: 9,
      ),
    ], nowMs: 1000);
    await controller.setConflictResolutionOverride(
      _docId,
      ConflictResolution.keepBoth,
    );

    final loaded = await controller.loadConflictLedger();
    expect(loaded.single.resolutionOverride, ConflictResolution.keepBoth);

    await controller.setConflictResolutionOverride(_docId, null);
    expect((await controller.loadConflictLedger()).single.hasOverride, isFalse);
  });

  test('成功一轮后：冲突进了台账（含当时的事实与裁决）', () async {
    final cipher = AesSyncCipher(
      key: await deriveMasterKey(_passphrase, _saltBytes),
    );
    final docPlain = utf8.encode('{"id":"$_docId","updatedAt":30}');
    final docSealed = await cipher.encryptDocumentBytes(
      Uint8List.fromList(docPlain),
      _docId,
    );
    final manifestJson = jsonEncode(
      SyncManifest(
        entries: {
          _docId: SyncSnapshot(
            id: _docId,
            updatedAt: 30,
            size: docSealed.length,
          ),
        },
      ).toJson(),
    );
    final manifestSealed = await cipher.sealManifestJson(manifestJson);

    final dav = _FakeDav(
      manifestBytes: utf8.encode(manifestSealed),
      docBytes: docSealed,
    );
    await dav.start();
    await dav.bindDocPath(cipher);
    addTearDown(dav.close);

    final ledger = MemorySyncConflictLedgerStore();
    final baseline = _Baseline()
      ..value = SyncManifest(
        entries: {_docId: const SyncSnapshot(id: _docId, updatedAt: 10, size: 5)},
      );
    final controller = SyncController(
      configStore: WebDavConfigStore(),
      secretStore: MemorySyncSecretStore(),
      documentStore: _Docs(),
      baselineStore: baseline,
      conflictLedgerStore: ledger,
    );

    final outcome = await controller.syncNow(
      baseUrl: dav.baseUrl,
      username: 'u',
      password: 'p',
      passphrase: _passphrase,
      syncSalt: _saltBase64,
      conflictHandler: _Scripted({
        _docId: ConflictResolution.keepRemote,
      }),
    );

    expect(outcome.error, isNull);
    expect(outcome.result, isNotNull);

    // 台账里必须有那条冲突，且带着「当时实际怎么处理的」。
    final entries = await controller.loadConflictLedger();
    expect(entries, hasLength(1));
    expect(entries.single.docId, _docId);
    expect(entries.single.count, 1);
    expect(entries.single.lastConflict.remoteUpdatedAt, 30);
    expect(
      entries.single.lastConflict.resolvedResolution,
      ConflictResolution.keepRemote,
      reason: '台账记的是实际生效的裁决，不是「检测到冲突」这件事本身',
    );
    expect(entries.single.hasOverride, isFalse, reason: '记账不改判');
  });

  test('失败一轮后：台账仍然空（失败轮次不写假历史）', () async {
    // 服务器一律 500，连 manifest 都拿不到，所以不需要构造文档密文路径。
    final dav = _FakeDav(
      manifestBytes: const [],
      docBytes: const [],
      alwaysFail: true,
    );
    await dav.start();
    addTearDown(dav.close);

    final ledger = MemorySyncConflictLedgerStore();
    final controller = SyncController(
      configStore: WebDavConfigStore(),
      secretStore: MemorySyncSecretStore(),
      documentStore: _Docs(),
      baselineStore: _Baseline(),
      conflictLedgerStore: ledger,
    );

    final outcome = await controller.syncNow(
      baseUrl: dav.baseUrl,
      username: 'u',
      password: 'p',
      passphrase: _passphrase,
      syncSalt: _saltBase64,
      conflictHandler: const LwwConflictHandler(),
    );

    expect(outcome.result, isNull, reason: '服务器一直 500，这轮应当失败');
    expect(
      await controller.loadConflictLedger(),
      isEmpty,
      reason: '失败轮次的基线没推进，记账等于伪造一条不存在的历史',
    );
  });

  test('没有冲突的一轮：台账不变（不写空条目）', () async {
    // 远端没有 manifest、本地也没有新文档 ⇒ 无冲突。
    final dav = _FakeDav(manifestBytes: null, docBytes: const []);
    await dav.start();
    addTearDown(dav.close);

    final ledger = MemorySyncConflictLedgerStore();
    final controller = SyncController(
      configStore: WebDavConfigStore(),
      secretStore: MemorySyncSecretStore(),
      documentStore: _EmptyDocs(),
      baselineStore: _Baseline(),
      conflictLedgerStore: ledger,
    );

    final outcome = await controller.syncNow(
      baseUrl: dav.baseUrl,
      username: 'u',
      password: 'p',
      passphrase: _passphrase,
      syncSalt: _saltBase64,
      conflictHandler: const LwwConflictHandler(),
    );

    expect(outcome.error, isNull);
    expect(outcome.result!.conflicts, isEmpty);
    expect(await controller.loadConflictLedger(), isEmpty);
  });
}

class _EmptyDocs implements SyncDocumentStore {
  @override
  Future<SyncLocalInventory> listDocuments() async =>
      const SyncLocalInventory(readable: []);

  @override
  Future<Uint8List?> readDocument(String id) async => null;

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async {}

  @override
  Future<void> deleteDocument(String id) async {}
}

class _Scripted implements ConflictHandler {
  _Scripted(this.map);
  final Map<String, ConflictResolution> map;

  @override
  Future<Map<String, ConflictResolution>> resolve(
    List<SyncConflict> conflicts,
  ) async => map;
}
