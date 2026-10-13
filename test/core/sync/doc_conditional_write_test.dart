// DN-201（第三轮专家审计 2026-10-13）：文档级条件写入。
//
// 上一轮的 DN-104 只把 `If-Match` 用在 manifest.json 上，**每篇笔记的正文**仍是
// 无条件 PUT：两台设备先各读到云端 v1、各自改完再各自上传，后上传的那台会把
// 前一台刚写好的版本整片盖掉——而那可能是那份内容唯一的云端副本。审计要求的
// 处置是「先把两个版本都保留下来，再请用户裁决，不能继续静默覆盖」。
//
// 本文件钉四条：
//  ① 覆盖前用 HEAD 拿远端 ETag ⇒ 已存在的对象走 If-Match、不存在的走 If-None-Match: *；
//  ② 被 412 挡回时：不覆盖、不删除，云端那一版另存成本地副本，id 进 remoteChangedDocIds；
//  ③ 服务器给不了条件写入（不响应 HEAD / 没有 ETag）时**照常能同步**，
//     但必须把「防不住互相覆盖」如实上报——可用性不降级，诚实性也不能丢；
//  ④ 正常路径不受影响（没有并发时行为与既有一致）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/post_restore_baseline.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';

const _base = 'https://dav.example.com/sync/';

/// 支持 HEAD / If-Match / If-None-Match 的最小 WebDAV 桩。
class _Server {
  final Map<String, List<int>> files = {};

  /// 每个对象的版本标识；成功 PUT 后自增（真实服务端按内容/版本变）。
  final Map<String, String> etags = {};

  /// 收到过的 (方法, 路径, If-Match, If-None-Match)。
  final List<(String, String, String?, String?)> requests = [];

  /// 桩的行为开关。
  bool headUnsupported = false; // 405：这台服务器不响应 HEAD
  bool suppressEtags = false; // 存在但不给 ETag
  bool failHead = false; // HEAD 直接 500
  String? hijackOnPutPath; // 该路径在 PUT 落笔前被别的设备改掉

  void seed(String path, int updatedAt, {String etag = 'v1'}) {
    files[path] = _docBytes(updatedAt);
    etags[path] = etag;
  }

  /// 写一份**结构合法**的远端清单（`_readRemoteManifest` 要按条目解析，
  /// 拿 `_docBytes` 糊弄它会得到空清单，进而让墓碑/下载分支根本不被触发）。
  void seedManifestWith(Map<String, int> idToUpdatedAt) {
    final entries = {
      for (final e in idToUpdatedAt.entries)
        e.key: {
          'id': e.key,
          'updatedAt': e.value,
          'size': _docBytes(e.value).length,
        },
    };
    files['manifest.json'] = utf8.encode(
      jsonEncode({'entries': entries, 'deletedIds': <String>[]}),
    );
    etags['manifest.json'] = 'm1';
  }

  /// 模拟「探测/读取之后，另一台设备抢先写了同一个对象」。
  void _hijackIfTargeted(String rel) {
    final target = hijackOnPutPath;
    if (target == null || target != rel) return;
    hijackOnPutPath = null;
    files[rel] = _docBytes(999);
    etags[rel] = 'v-other';
  }

  MockClient client() => MockClient((request) async {
    final rel = _rel(request.url);
    final ifMatch = request.headers['if-match'];
    final ifNoneMatch = request.headers['if-none-match'];
    requests.add((request.method, rel, ifMatch, ifNoneMatch));
    switch (request.method) {
      case 'MKCOL':
        return http.Response('', 201);
      case 'HEAD':
        if (headUnsupported) return http.Response('', 405);
        if (failHead) return http.Response('', 500);
        if (!files.containsKey(rel)) return http.Response('', 404);
        return http.Response(
          '',
          200,
          headers: suppressEtags ? {} : {'etag': etags[rel]!},
        );
      case 'GET':
        if (failGet.contains(rel)) return http.Response('', 500);
        if (files.containsKey(rel)) {
          return http.Response.bytes(files[rel]!, 200);
        }
        return http.Response('', 404);
      case 'PUT':
        _hijackIfTargeted(rel);
        if (ifNoneMatch == '*' && files.containsKey(rel)) {
          return http.Response('', 412);
        }
        if (ifMatch != null && etags[rel] != ifMatch) {
          return http.Response('', 412);
        }
        files[rel] = request.bodyBytes;
        etags[rel] = 'v${(int.tryParse((etags[rel] ?? 'v0').substring(1)) ?? 0) + 1}';
        return http.Response('', 201);
      case 'DELETE':
        _hijackIfTargetedDelete(rel);
        if (ifMatch != null && etags[rel] != ifMatch) {
          return http.Response('', 412);
        }
        files.remove(rel);
        etags.remove(rel);
        return http.Response('', 204);
      default:
        return http.Response('', 405);
    }
  });

  /// DELETE 的桩侧并发：只改版本标识、不删文件（模拟别人刚写过这一篇）。
  void _hijackIfTargetedDelete(String rel) {
    final target = hijackDeletePath;
    if (target == null || target != rel) return;
    hijackDeletePath = null;
    etags[rel] = 'v-other';
    files[rel] = _docBytes(777);
  }

  String? hijackDeletePath;

  /// GET 这些路径返回 500（用于「副本没能保住」那条分支）。
  final Set<String> failGet = {};

  /// 条件头断言：某路径最近一次 PUT 带的 If-Match / If-None-Match。
  (String?, String?) putHeadersFor(String rel) {
    final hit = requests.lastWhere(
      (r) => r.$1 == 'PUT' && r.$2 == rel,
      orElse: () => ('NONE', '', null, null),
    );
    return (hit.$3, hit.$4);
  }

  static String _rel(Uri url) {
    const prefix = '/sync/';
    final path = url.path;
    if (!path.startsWith(prefix)) return '';
    return path.substring(prefix.length);
  }
}

Uint8List _docBytes(int updatedAt) =>
    Uint8List.fromList(utf8.encode(jsonEncode({'updatedAt': updatedAt})));

class _Docs implements SyncDocumentStore {
  final Map<String, int> updatedAtById = {};

  @override
  Future<SyncLocalInventory> listDocuments() async => SyncLocalInventory(
    readable: [
      for (final e in updatedAtById.entries)
        SyncDocMeta(
          id: e.key,
          updatedAt: e.value,
          size: _docBytes(e.value).length,
        ),
    ],
  );

  @override
  Future<Uint8List?> readDocument(String id) async =>
      updatedAtById.containsKey(id) ? _docBytes(updatedAtById[id]!) : null;

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async {
    final ts =
        (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['updatedAt']
        as int;
    updatedAtById[id] = ts;
  }

  @override
  Future<void> deleteDocument(String id) async => updatedAtById.remove(id);
}

class _Baseline implements SyncBaselineStore {
  SyncManifest? value;
  @override
  Future<SyncManifest?> load() async => value;
  @override
  Future<void> save(SyncManifest manifest) async => value = manifest;
}

SyncService _service(_Server server, _Docs docs, _Baseline baseline) =>
    SyncService(
      transport: WebDavSyncClient(
        baseUrl: Uri.parse(_base),
        client: server.client(),
      ),
      documentStore: docs,
      baselineStore: baseline,
      cipher: const NoopSyncCipher(),
      conflictHandler: const LwwConflictHandler(),
      baselineGate: const AlwaysTrustedBaselineGate(),
    );

/// 本机比云端新 ⇒ 本轮必然产生一次上传的场景。
({
  _Server server,
  _Docs docs,
  _Baseline baseline,
}) _uploadSetup({int local = 200, int remote = 100, bool seedRemote = true}) {
  final docs = _Docs()..updatedAtById['a'] = local;
  final server = _Server()
    ..seedManifestWith(seedRemote ? {'a': remote} : <String, int>{});
  if (seedRemote) server.seed('a', remote);
  final baseline = _Baseline()
    ..value = SyncManifest(
      entries: {
        'a': SyncSnapshot(id: 'a', updatedAt: remote, size: _docBytes(remote).length),
      },
    );
  return (server: server, docs: docs, baseline: baseline);
}

void main() {
  group('DN-201 传输层 probe（HEAD）', () {
    WebDavSyncClient client(MockClient m) =>
        WebDavSyncClient(baseUrl: Uri.parse(_base), client: m);

    test('存在且有 ETag ⇒ presentWithETag，etag 原样带出', () async {
      final c = client(
        MockClient((r) async => http.Response('', 200, headers: {'etag': 'v7'})),
      );
      final p = await c.probe('a');
      expect(p.state, WebDavProbeState.presentWithETag);
      expect(p.etag, 'v7');
      expect(p.canConditionallyWrite, isTrue);
    });

    test('存在但没有 ETag 头 ⇒ presentWithoutETag（不得塌进「不存在」）', () async {
      final c = client(MockClient((r) async => http.Response('', 200)));
      final p = await c.probe('a');
      expect(p.state, WebDavProbeState.presentWithoutETag);
      expect(p.isAbsent, isFalse);
    });

    test('404 ⇒ absent；405/501 ⇒ presentUnknown；5xx ⇒ 抛出', () async {
      expect(
        (await client(MockClient((r) async => http.Response('', 404)))
                .probe('a'))
            .state,
        WebDavProbeState.absent,
      );
      expect(
        (await client(MockClient((r) async => http.Response('', 405)))
                .probe('a'))
            .state,
        WebDavProbeState.presentWithoutETag,
      );
      expect(
        (await client(MockClient((r) async => http.Response('', 501)))
                .probe('a'))
            .state,
        WebDavProbeState.presentWithoutETag,
      );
      await expectLater(
        client(MockClient((r) async => http.Response('', 500))).probe('a'),
        throwsA(isA<WebDavSyncException>()),
      );
    });
  });

  group('DN-201 文档级条件写入', () {
    test('覆盖已存在的远端文档 ⇒ 带 If-Match，不再无条件盖掉', () async {
      final s = _uploadSetup();
      final result = await _service(s.server, s.docs, s.baseline).syncNow();

      final (ifMatch, ifNoneMatch) = s.server.putHeadersFor('a');
      expect(ifMatch, 'v1', reason: '已存在的对象必须带 If-Match 覆盖写');
      expect(ifNoneMatch, isNull, reason: '已存在时不得带 If-None-Match');
      expect(result.uploaded, 1);
      expect(result.remoteChangedDocIds, isEmpty);
      expect(result.conditionalWritesUnavailable, isFalse);
    });

    test('远端还没有这个对象 ⇒ 走 If-None-Match: *（只创建，不覆盖）', () async {
      final s = _uploadSetup(seedRemote: false);
      final result = await _service(s.server, s.docs, s.baseline).syncNow();

      final (ifMatch, ifNoneMatch) = s.server.putHeadersFor('a');
      expect(ifMatch, isNull);
      expect(ifNoneMatch, '*', reason: '远端没有 ⇒ 只创建，不覆盖别人刚写的');
      expect(result.uploaded, 1);
    });

    test('探测之后被别的设备抢写 ⇒ 412：不覆盖，云端版本另存为本地副本', () async {
      final s = _uploadSetup();
      s.server.hijackOnPutPath = 'a'; // PUT 落笔前 a 被改成 v-other

      final result = await _service(s.server, s.docs, s.baseline).syncNow();

      expect(result.uploaded, 0, reason: '这一篇本轮一个字节都没往云端写');
      expect(result.remoteChangedDocIds, ['a']);
      expect(
        jsonDecode(utf8.decode(s.server.files['a']!))['updatedAt'],
        999,
        reason: '云端那一版必须原样活着（不许被本机版本盖掉）',
      );
      // 两份都在：云端那版已作为本地副本落盘（id 带 -conflict-）。
      final copies = s.docs.updatedAtById.keys.where((k) => k.contains('-conflict-'));
      expect(copies, hasLength(1), reason: 'keepBoth 同口径：两端都留一份');
      expect(s.docs.updatedAtById[copies.single], 999);
      // 清单/基线都不许推进这一篇（否则下轮它会被当成「已同步」）。
      final entries =
          jsonDecode(utf8.decode(s.server.files['manifest.json']!))['entries']
              as Map;
      expect(
        (entries['a'] as Map)['updatedAt'],
        100,
        reason: '清单里仍是云端那一版：本机版本一个字节都没登记上去',
      );
      expect(s.baseline.value!.entries['a']!.updatedAt, isNot(200));
    });

    test('412 之后连副本都保不住 ⇒ 记失败，同样不回写清单/基线', () async {
      final s = _uploadSetup();
      s.server.hijackOnPutPath = 'a';
      s.server.failGet.add('a'); // 取回云端那一版时 500

      final result = await _service(s.server, s.docs, s.baseline).syncNow();

      expect(result.remoteChangedDocIds, isEmpty);
      expect(result.failedDocIds, ['a']);
      expect(
        jsonDecode(utf8.decode(s.server.files['a']!))['updatedAt'],
        999,
        reason: '保不住副本也不能覆盖：失败退路不得变成新的覆盖路径',
      );
      expect(s.docs.updatedAtById.keys.where((k) => k.contains('-conflict-')), isEmpty);
    });

    test('服务器不响应 HEAD ⇒ 照常同步，但如实上报「防不住互相覆盖」', () async {
      final s = _uploadSetup();
      s.server.headUnsupported = true;

      final result = await _service(s.server, s.docs, s.baseline).syncNow();

      expect(
        result.uploaded,
        1,
        reason: '不能因为多一个 HEAD 探测就断掉同步（可用性不降级）',
      );
      final (ifMatch, ifNoneMatch) = s.server.putHeadersFor('a');
      expect(ifMatch, isNull);
      expect(ifNoneMatch, isNull, reason: '退回既有的无条件写，不新增任何条件头');
      expect(result.conditionalWritesUnavailable, isTrue);
      expect(result.remoteChangedDocIds, isEmpty);
    });

    test('对象存在却不给 ETag ⇒ 无条件写照常成功 + 上报', () async {
      final s = _uploadSetup();
      s.server.suppressEtags = true;

      final result = await _service(s.server, s.docs, s.baseline).syncNow();

      expect(result.uploaded, 1);
      expect(result.conditionalWritesUnavailable, isTrue);
    });

    test('HEAD 本身报错（5xx）⇒ 退回既有写法，不记成同步失败', () async {
      final s = _uploadSetup();
      s.server.failHead = true;

      final result = await _service(s.server, s.docs, s.baseline).syncNow();

      expect(result.failedDocIds, isEmpty);
      expect(result.uploaded, 1);
      expect(result.conditionalWritesUnavailable, isTrue);
    });

    test('删除也带条件：远端在我们读过之后又被改过 ⇒ 不删云端', () async {
      final docs = _Docs(); // 本地已删除 a
      final server = _Server()
        ..seedManifestWith({'a': 100})
        ..seed('a', 100, etag: 'v1');
      server.hijackDeletePath = 'a'; // 别的设备刚改过这一篇
      final baseline = _Baseline()
        ..value = SyncManifest(
          entries: {
            'a': SyncSnapshot(id: 'a', updatedAt: 100, size: _docBytes(100).length),
          },
        );

      final result = await _service(server, docs, baseline).syncNow();

      expect(result.deletedRemote, 0);
      expect(result.remoteChangedDocIds, ['a']);
      expect(
        server.files.containsKey('a'),
        isTrue,
        reason: '删除也是一种覆盖：云端那份本机没见过的内容不能被删掉',
      );
    });

    test('反向锁：没有并发时行为与既有实现一致（下载/删除照常）', () async {
      final docs = _Docs();
      final server = _Server()
        ..seedManifestWith({'b': 150})
        ..seed('b', 150, etag: 'v1');
      final result = await _service(server, docs, _Baseline()).syncNow();

      expect(result.downloaded, 1);
      expect(result.remoteChangedDocIds, isEmpty);
      expect(result.conditionalWritesUnavailable, isFalse);
      expect(docs.updatedAtById['b'], 150);
    });
  });
}
