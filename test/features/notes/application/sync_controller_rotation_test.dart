// 修复 1②端到端锁：SyncController 的有界重试必须把「口令轮换 ⇒ 旧云端
// 密文不可解」这类确定性失败一次收敛，同时**不削弱**网络类失败的既有
// 退避重试（两项都要证据，否则「不无限重试」可能只是把重试整条关了）。
//
// 用真实本地回环 HTTP（transport 由 controller 内建，无注入点）——与
// sync_controller_test.dart 同口径：刻意不装 TestWidgetsFlutterBinding，
// binding 会把 HttpClient 请求全量劫持为 400。
// KDF 走 KekSessionCache.bypassIsolateForTests（测试口径确定性派生，快），
// 使「服务器侧用旧口令派生的 key」与「控制器派生的旧 key」逐字节相同。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';

final _saltBytes = Uint8List.fromList(List<int>.generate(16, (i) => 100 + i));
final _saltBase64 = base64Encode(_saltBytes);

class _Docs implements SyncDocumentStore {
  final Map<String, Uint8List> docs = {
    'doc-1': Uint8List.fromList(utf8.encode('{"id":"doc-1"}')),
  };

  @override
  Future<List<SyncDocMeta>> listDocuments() async => [
    for (final e in docs.entries)
      SyncDocMeta(id: e.key, updatedAt: 100, size: e.value.length),
  ];

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
  int saveCalls = 0;

  @override
  Future<SyncManifest?> load() async => value;

  @override
  Future<void> save(SyncManifest manifest) async {
    saveCalls++;
    value = manifest;
  }
}

/// 回环假 WebDAV：按路径计数，用于证明「一次即收敛」与「重试仍然在」。
class _FakeDav {
  _FakeDav({this.manifestBytes, this.alwaysFail = false});

  final List<int>? manifestBytes;
  final bool alwaysFail;
  final counts = <String, int>{};
  final uploadedSizes = <String, int>{};

  late final HttpServer _server;

  int get n => counts['GET manifest.json'] ?? 0;

  /// 按方法前缀计数（MKCOL 打的是集合根本身，rel 为空串，标签带尾空格）。
  int _byMethod(String method) => counts.entries
      .where((e) => e.key.startsWith('$method '))
      .fold(0, (s, e) => s + e.value);

  int get putCount => _byMethod('PUT');
  int get mkcolCount => _byMethod('MKCOL');

  Future<void> start() async {
    _server = await HttpServer.bind('127.0.0.1', 0);
    _server.listen((request) async {
      final builder = BytesBuilder();
      await for (final chunk in request) {
        builder.add(chunk);
      }
      final body = builder.takeBytes();
      final rel = request.uri.path.replaceFirst('/sync/', '');
      final label = '${request.method} $rel';
      counts[label] = (counts[label] ?? 0) + 1;
      if (alwaysFail) {
        request.response.statusCode = 500;
        await request.response.close();
        return;
      }
      switch (request.method) {
        case 'MKCOL':
          request.response.statusCode = 201;
        case 'GET':
          if (rel == 'manifest.json' && manifestBytes != null) {
            request.response.add(manifestBytes!);
          } else {
            request.response.statusCode = 404;
          }
        case 'PUT':
          uploadedSizes[rel] = body.length;
          request.response.statusCode = 201;
        default:
          request.response.statusCode = 405;
      }
      await request.response.close();
    });
  }

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}/sync/');

  Future<void> close() => _server.close(force: true);
}

SyncController _controller(SyncDocumentStore docs, SyncBaselineStore baseline) =>
    SyncController(
      configStore: WebDavConfigStore(),
      secretStore: MemorySyncSecretStore(),
      documentStore: docs,
      baselineStore: baseline,
    );

void main() {
  setUp(() => KekSessionCache.bypassIsolateForTests = true);
  tearDown(() => KekSessionCache.bypassIsolateForTests = false);

  test('改过口令（同盐）→ 一轮即收敛：远端清单只被取一次，不退避重试', () async {
    final oldKey = await deriveMasterKey('P1', _saltBytes);
    final sealedManifest = utf8.encode(
      await AesSyncCipher(
        key: oldKey,
      ).sealManifestJson(
        jsonEncode(
          SyncManifest(
            entries: {
              'doc-1': const SyncSnapshot(id: 'doc-1', updatedAt: 50, size: 8),
            },
          ).toJson(),
        ),
      ),
    );
    final dav = _FakeDav(manifestBytes: sealedManifest);
    await dav.start();
    addTearDown(dav.close);

    final outcome = await _controller(_Docs(), _Baseline()).syncNow(
      baseUrl: dav.baseUrl,
      username: 'u',
      password: 'p',
      passphrase: 'P2', // 换过口令，盐不变 ⇒ 新 key
      syncSalt: _saltBase64,
      conflictHandler: const LwwConflictHandler(),
    );

    expect(outcome.result, isNull);
    expect(
      outcome.error,
      isA<SyncKeyMismatchException>(),
      reason: '分型必须保住，否则 UI 只剩泛化文案',
    );
    expect(dav.n, 1, reason: '认证失败不得反复取远端清单（旧行为 4 轮）');
    expect(dav.mkcolCount, 1);
    expect(dav.putCount, 0, reason: '失败轮不得将任何一侧的残缺状态写出去');
  });

  test('口令未变 → 同一套装配正常同步（证明分型不是误伤）', () async {
    final oldKey = await deriveMasterKey('P1', _saltBytes);
    final sealedManifest = utf8.encode(
      await AesSyncCipher(
        key: oldKey,
      ).sealManifestJson(jsonEncode(const SyncManifest().toJson())),
    );
    final dav = _FakeDav(manifestBytes: sealedManifest);
    await dav.start();
    addTearDown(dav.close);
    final baseline = _Baseline();

    final outcome = await _controller(_Docs(), baseline).syncNow(
      baseUrl: dav.baseUrl,
      username: 'u',
      password: 'p',
      passphrase: 'P1',
      syncSalt: _saltBase64,
      conflictHandler: const LwwConflictHandler(),
    );

    expect(outcome.error, isNull);
    expect(outcome.result!.uploaded, 1);
    expect(dav.uploadedSizes, hasLength(2), reason: '1 个文档 + 1 个 manifest');
    expect(dav.uploadedSizes['manifest.json'], greaterThan(0));
    expect(baseline.saveCalls, 1);
  });

  test('服务器 500（瞬时失败）→ 仍然按策略重试满 4 轮（防线未被削弱）', () async {
    final dav = _FakeDav(alwaysFail: true);
    await dav.start();
    addTearDown(dav.close);

    final outcome = await _controller(_Docs(), _Baseline()).syncNow(
      baseUrl: dav.baseUrl,
      username: 'u',
      password: 'p',
      passphrase: 'P1',
      syncSalt: _saltBase64,
      conflictHandler: const LwwConflictHandler(),
    );

    expect(outcome.result, isNull);
    expect(dav.mkcolCount, 4, reason: '瞬时失败仍走既有有界重试');
  });
}
