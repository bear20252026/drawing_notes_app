// DN-204（第三轮专家审计 2026-10-13）：恢复换根后的同步隔离——
// 「基线有、本地无」在这条链路里不是用户删除，绝不能升级成云端 DELETE。
//
// 场景取自审计原文：10-01 备份 A、B；10-10 新增 C 并同步（基线记 A、B、C）；
// 恢复 10-01 的备份后本地只剩 A、B，而基线还在原地。
// 本文件钉四条不变量：
//  ① 未裁决（reportOnly）：一个字节都不写，只把差异报出来；
//  ② 任何已选方向下都**不发删除**；
//  ③ 方向过滤真的生效（只下载 / 只上传）；
//  ④ 反向锁：基线可信时删除墓碑照旧生成（本条改的是恢复态，不是删除语义）。

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

/// 最小内存 WebDAV：记下载/删除/PUT 三条腿，够钉「有没有写过云端」。
class _Server {
  final Map<String, List<int>> files = {};

  /// 收到过的 DELETE 相对路径——DN-204 的第一现场。
  final List<String> deletes = [];

  /// 收到过的 PUT 相对路径（含 manifest.json，断言时自行排除）。
  final List<String> puts = [];

  void seedDoc(String id, int updatedAt) {
    files[id] = _docBytes(updatedAt);
  }

  void seedManifest(Map<String, int> idToUpdatedAt) {
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
  }

  /// 云端清单当前的条目 id（断言 manifest 有没有被本轮改写）。
  Set<String> manifestIds() {
    final raw = files['manifest.json'];
    if (raw == null) return {};
    final decoded = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    return (decoded['entries'] as Map).keys.cast<String>().toSet();
  }

  MockClient client() => MockClient((request) async {
    final rel = _rel(request.url);
    switch (request.method) {
      case 'MKCOL':
        return http.Response('', 201);
      case 'GET':
        if (rel.isNotEmpty && files.containsKey(rel)) {
          return http.Response.bytes(files[rel]!, 200);
        }
        return http.Response('', 404);
      case 'PUT':
        puts.add(rel);
        if (rel.isNotEmpty) files[rel] = request.bodyBytes;
        return http.Response('', 201);
      case 'DELETE':
        deletes.add(rel);
        files.remove(rel);
        return http.Response('', 204);
      default:
        return http.Response('', 405);
    }
  });

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
  final Set<String> unreadable = {};

  void put(String id, int updatedAt) => updatedAtById[id] = updatedAt;

  @override
  Future<SyncLocalInventory> listDocuments() async => SyncLocalInventory(
    readable: [
      for (final e in updatedAtById.entries)
        if (!unreadable.contains(e.key))
          SyncDocMeta(id: e.key, updatedAt: e.value, size: _docBytes(e.value).length),
    ],
    unreadable: unreadable.toSet(),
  );

  @override
  Future<Uint8List?> readDocument(String id) async =>
      updatedAtById.containsKey(id) && !unreadable.contains(id)
      ? _docBytes(updatedAtById[id]!)
      : null;

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
  _Baseline(this.value);
  SyncManifest? value;
  int saves = 0;
  @override
  Future<SyncManifest?> load() async => value;
  @override
  Future<void> save(SyncManifest manifest) async {
    value = manifest;
    saves++;
  }
}

class _Gate implements PostRestoreBaselineGate {
  _Gate(this.stale);
  bool stale;
  @override
  Future<bool> isBaselineStaleAfterRestore() async => stale;
}

SyncService _service({
  required _Docs docs,
  required _Server server,
  required _Baseline baseline,
  required _Gate gate,
  PostRestoreReconcile? reconcile,
  ConflictHandler conflictHandler = const LwwConflictHandler(),
}) => SyncService(
  transport: WebDavSyncClient(baseUrl: Uri.parse(_base), client: server.client()),
  documentStore: docs,
  baselineStore: baseline,
  cipher: const NoopSyncCipher(),
  conflictHandler: conflictHandler,
  baselineGate: gate,
  reconcile: reconcile,
);

/// 审计原文场景的现网形状：基线记着 a、b、c；恢复出来的库只剩 a（且是旧版）；
/// 云端有 a（新版）、b、c。
void _seedRestoredWorld({
  required _Docs docs,
  required _Server server,
  required _Baseline baseline,
}) {
  docs.put('a', 10); // 恢复出来的 a 是 10-01 的旧版本
  server
    ..seedDoc('a', 50)
    ..seedDoc('b', 40)
    ..seedDoc('c', 40)
    ..seedManifest({'a': 50, 'b': 40, 'c': 40});
  baseline.value = SyncManifest(
    entries: {
      'a': SyncSnapshot(id: 'a', updatedAt: 50, size: _docBytes(50).length),
      'b': SyncSnapshot(id: 'b', updatedAt: 40, size: _docBytes(40).length),
      'c': SyncSnapshot(id: 'c', updatedAt: 40, size: _docBytes(40).length),
    },
  );
}

void main() {
  group('DN-204 未裁决：只报差异，零写入', () {
    test('reportOnly 不删云端、不上传、不下载，也不推进基线与远端清单', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);
      final before = Map<String, List<int>>.from(server.files);

      final r = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: _Gate(true),
      ).syncNow();

      expect(r.deletedRemote, 0);
      expect(r.uploaded, 0);
      expect(r.downloaded, 0);
      expect(server.deletes, isEmpty, reason: '恢复副作用不是用户删除：一条 DELETE 都不许发');
      expect(
        server.puts.where((p) => p != 'manifest.json'),
        isEmpty,
        reason: '没裁决就不许把任何文档写上去',
      );
      expect(server.files, equals(before), reason: '云端字节原样不动');
      expect(baseline.saves, 0, reason: '基线不推进 ⇒ 隔离继续挂着，直到用户选方向');
      expect(r.postRestorePolicy, PostRestoreReconcile.reportOnly);
    });

    test('差异把「本该删云端的那几篇」单独说清楚', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);

      final r = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: _Gate(true),
      ).syncNow();

      final diff = r.postRestoreDiff!;
      expect(diff.suppressedTombstoneIds, ['b', 'c']);
      expect(diff.remoteOnlyIds, ['b', 'c']);
      expect(diff.divergedIds, ['a'], reason: 'a 两端都有且指纹不同');
      expect(diff.localOnlyIds, isEmpty);
      expect(diff.isEmpty, isFalse);
    });

    test('受密未解锁的那篇不算「云端有、本地没有」（DN-107 判据只有一份）', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);
      docs.put('b', 40);
      docs.unreadable.add('b');

      final r = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: _Gate(true),
      ).syncNow();

      expect(r.postRestoreDiff!.remoteOnlyIds, ['c']);
      expect(r.postRestoreDiff!.suppressedTombstoneIds, ['c']);
    });
  });

  group('DN-204 已选方向：删除墓碑任何方向都不放行', () {
    test('合并：两端独有的都回来，仍不删云端，基线跟着推进', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);

      final r = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: _Gate(true),
        reconcile: PostRestoreReconcile.merge,
      ).syncNow();

      expect(server.deletes, isEmpty);
      expect(r.deletedRemote, 0);
      expect(r.downloaded, 3, reason: 'a 取云端较新版，b、c 从云端找回');
      expect(docs.updatedAtById.keys, containsAll(<String>['a', 'b', 'c']));
      expect(baseline.value!.entries.keys, containsAll(<String>['a', 'b', 'c']));
      expect(r.postRestorePolicy, PostRestoreReconcile.merge);
    });

    test('合并：旧基线不再制造一堆与事实无关的冲突裁决', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);

      final r = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: _Gate(true),
        reconcile: PostRestoreReconcile.merge,
      ).syncNow();

      // 可信基线下 a 会被判成「远端没改过却比本地新」⇒ 弹一次无意义的裁决；
      // 隔离态按首次同步处理，冲突集合应为空。
      expect(r.conflictedDocIds, isEmpty);
    });

    test('以云端为准：只下载，本地独有那篇不上传', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);
      docs.put('x', 60); // 恢复库里独有的一篇

      final r = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: _Gate(true),
        reconcile: PostRestoreReconcile.keepRemote,
      ).syncNow();

      expect(server.deletes, isEmpty);
      expect(server.files.containsKey('x'), isFalse, reason: 'keepRemote 不上报本地内容');
      expect(r.uploaded, 0);
      expect(r.downloaded, 3);
    });

    test('覆盖云端：只上传，不下载，仍然不删云端', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);
      docs.put('x', 60);

      final r = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: _Gate(true),
        reconcile: PostRestoreReconcile.overwriteRemote,
      ).syncNow();

      expect(server.deletes, isEmpty);
      expect(r.deletedRemote, 0);
      expect(server.files.containsKey('x'), isTrue);
      expect(r.uploaded, 2, reason: 'x 与更旧的 a 都按本机版本推上去');
      expect(r.downloaded, 0, reason: '方向已定为覆盖云端，本轮不从云端取回');
      expect(docs.updatedAtById.containsKey('b'), isFalse);
      // 「覆盖云端」对两端都有、内容不同的那篇必须真的把本机版本推上去：
      // planner 按时间戳判的是 download，若不转写成 upload，这个方向就是空转。
      expect(
        jsonDecode(utf8.decode(server.files['a']!))['updatedAt'],
        10,
        reason: '云端 a 已被恢复出来的旧版本替换（这是用户显式选的方向）',
      );
      expect(server.manifestIds(), containsAll(<String>['a', 'b', 'c', 'x']));
    });
  });

  group('DN-204 反向锁：基线可信时删除语义不变', () {

    test('未换根（gate 判可信）⇒ 基线有、本地无照旧生成云端 DELETE', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);

      final r = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: _Gate(false),
      ).syncNow();

      expect(server.deletes, containsAll(<String>['b', 'c']));
      expect(r.deletedRemote, 2);
      expect(r.postRestoreDiff, isNull, reason: '非隔离轮不该带差异');
      expect(r.postRestorePolicy, isNull);
    });

    test('可信基线下 a 仍按既有冲突判据上报（本批没有削弱冲突可见性）', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);

      final r = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: _Gate(false),
      ).syncNow();

      expect(r.conflictedDocIds, contains('a'));
    });
  });

  group('DN-204 选完方向的第二轮：同一批删除不得延后一轮补发', () {
    test('覆盖云端之后隔离解除，第二轮也不发 DELETE', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      final gate = _Gate(true);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);
      docs.put('x', 60);

      await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: gate,
        reconcile: PostRestoreReconcile.overwriteRemote,
      ).syncNow();
      expect(server.deletes, isEmpty);
      // 一轮走完，基线已推进 ⇒ 判据不再触发隔离（文件侧用 mtime 表达同一件事）。
      gate.stale = false;

      final second = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: gate,
      ).syncNow();

      expect(
        server.deletes,
        isEmpty,
        reason: '基线若记着「云端有 b、c 而本地没有」，第二轮就会把它们删掉——'
            '那是本条缺陷换了个时间点复发',
      );
      expect(second.deletedRemote, 0);
      // 如实记录本批的残余口径：b、c 仍留在云端，第二轮作为「仅远端」被拉回本地。
      // 既没有删数据，也没有把用户选的方向当成永久状态。
      expect(second.downloaded, 2);
      expect(docs.updatedAtById.keys, containsAll(<String>['b', 'c']));
    });

    test('以云端为准之后第二轮也不发 DELETE', () async {
      final docs = _Docs();
      final server = _Server();
      final baseline = _Baseline(null);
      final gate = _Gate(true);
      _seedRestoredWorld(docs: docs, server: server, baseline: baseline);
      docs.put('x', 60);

      await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: gate,
        reconcile: PostRestoreReconcile.keepRemote,
      ).syncNow();
      gate.stale = false;

      final second = await _service(
        docs: docs,
        server: server,
        baseline: baseline,
        gate: gate,
      ).syncNow();

      expect(server.deletes, isEmpty);
      expect(second.deletedRemote, 0);
      expect(second.uploaded, 1, reason: 'x 在下一轮按普通「本地新增」上传');
    });
  });
}
