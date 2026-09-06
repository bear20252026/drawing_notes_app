// 由 Claude 团队生成 | Drawing Notes App
// SyncService 集成测试：用内存文档存储 + MockClient 模拟 WebDAV 服务器，
// 验证「拉 manifest → 比对 → 上传/下载/删远端 → 回写两端 manifest」闭环。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';

// P1 安全契约：传输层强制 https（WebDavSyncClient._requireHttps），
// 同步测试统一用 https 基址（http 行为由 webdav_sync_client_test 专项覆盖）。
const _base = 'https://dav.example.com/sync/';

/// 内存 WebDAV 服务器：key = 相对路径（如 'a' / 'manifest.json'）。
class _MemoryServer {
  final Map<String, List<int>> files = {};

  /// 故障注入：GET/PUT/DELETE 这些相对路径返回 500（验证 M2 单操作隔离与毒丸防护）。
  final Set<String> failGet = {};
  final Set<String> failPut = {};
  final Set<String> failDelete = {};

  String _rel(Uri url) {
    final path = url.path;
    const prefix = '/sync/';
    if (!path.startsWith(prefix)) return '';
    final rel = path.substring(prefix.length);
    return rel.isEmpty ? '' : rel;
  }

  /// 预置一个远端文档（路径 = id），并把 manifest 中登记它的快照。
  void seedDoc(String id, int updatedAt) {
    final bytes = utf8.encode(jsonEncode({'updatedAt': updatedAt}));
    files[id] = bytes;
  }

  /// 预置远端 manifest。size 取真实字节长度（与 _localDocBytes 一致），
  /// 否则 sameTsDiverged 检测无法在测试中构造「同 ts 不同 size」分支。
  void seedManifest(Map<String, int> idToUpdatedAt) {
    final entries = {
      for (final e in idToUpdatedAt.entries)
        e.key: {
          'id': e.key,
          'updatedAt': e.value,
          'size': utf8.encode(jsonEncode({'updatedAt': e.value})).length,
        },
    };
    files['manifest.json'] = utf8.encode(
      jsonEncode({'entries': entries, 'deletedIds': <String>[]}),
    );
  }

  MockClient client() => MockClient((request) async {
    final rel = _rel(request.url);
    switch (request.method) {
      case 'MKCOL':
        return http.Response('', 201);
      case 'GET':
        if (failGet.contains(rel)) return http.Response('', 500);
        if (rel.isNotEmpty && files.containsKey(rel)) {
          return http.Response.bytes(files[rel]!, 200);
        }
        return http.Response('', 404);
      case 'PUT':
        if (failPut.contains(rel)) return http.Response('', 500);
        if (rel.isNotEmpty) files[rel] = request.bodyBytes;
        return http.Response('', 201);
      case 'DELETE':
        if (failDelete.contains(rel)) return http.Response('', 500);
        if (rel.isNotEmpty) files.remove(rel);
        return http.Response('', 204);
      default:
        return http.Response('', 405);
    }
  });
}

/// 内存文档存储：doc 内容即 `{"updatedAt": ts}`，用于模拟真实文档序列化带时间。
class _MemoryDocStore implements SyncDocumentStore {
  final Map<String, _Doc> docs = {};

  @override
  Future<List<SyncDocMeta>> listDocuments() async => docs.entries
      .map(
        (e) => SyncDocMeta(
          id: e.key,
          updatedAt: e.value.updatedAt,
          size: e.value.bytes.length,
        ),
      )
      .toList();

  @override
  Future<Uint8List?> readDocument(String id) async => docs[id]?.bytes;

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async {
    final ts =
        (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['updatedAt']
            as int;
    docs[id] = _Doc(id, bytes, ts);
  }

  @override
  Future<void> deleteDocument(String id) async => docs.remove(id);
}

class _Doc {
  _Doc(this.id, this.bytes, this.updatedAt);
  final String id;
  final Uint8List bytes;
  final int updatedAt;
}

class _MemoryBaseline implements SyncBaselineStore {
  SyncManifest? value;
  @override
  Future<SyncManifest?> load() async => value;
  @override
  Future<void> save(SyncManifest manifest) async => value = manifest;
}

Uint8List _localDocBytes(int updatedAt) =>
    Uint8List.fromList(utf8.encode(jsonEncode({'updatedAt': updatedAt})));

SyncService _service(
  _MemoryDocStore store,
  _MemoryServer server, {
  _MemoryBaseline? baseline,
  SyncCipher cipher = const NoopSyncCipher(),
  SyncProgressCallback? onProgress,
  ConflictHandler? conflictHandler,
}) => SyncService(
  transport: WebDavSyncClient(
    baseUrl: Uri.parse(_base),
    client: server.client(),
  ),
  documentStore: store,
  baselineStore: baseline ?? _MemoryBaseline(),
  cipher: cipher,
  conflictHandler: conflictHandler ?? const LwwConflictHandler(),
  onProgress: onProgress,
);

AesSyncCipher _aes() => AesSyncCipher(key: List<int>.generate(32, (i) => i));

void main() {
  group('SyncService 首次同步', () {
    test('本地新文档 → 上传并写入远端 manifest', () async {
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(10), 10);
      final server = _MemoryServer();
      final s = _service(store, server);

      final result = await s.syncNow();

      expect(result.uploaded, 1);
      expect(result.downloaded, 0);
      expect(server.files.containsKey('a'), isTrue);
      final remoteManifest = jsonDecode(
        utf8.decode(server.files['manifest.json']!),
      );
      expect((remoteManifest['entries'] as Map).containsKey('a'), isTrue);
    });

    test('无变化 → 结果为空', () async {
      final store = _MemoryDocStore();
      final baseline = _MemoryBaseline();
      final s = _service(store, _MemoryServer(), baseline: baseline);
      final r = await s.syncNow();
      expect(r.changed, isFalse);
    });
  });

  group('SyncService 远端较新', () {
    test('远端更新 → 下载并回写，二轮同步无动作', () async {
      final store = _MemoryDocStore();
      store.docs['b'] = _Doc('b', _localDocBytes(10), 10);
      final server = _MemoryServer();
      server.seedDoc('b', 20);
      server.seedManifest({'b': 20});
      final s = _service(store, server);

      final first = await s.syncNow();
      expect(first.downloaded, 1);
      expect(first.uploaded, 0);
      // 下载后本地 updatedAt 应变为远端值。
      expect(store.docs['b']!.updatedAt, 20);

      final second = await s.syncNow();
      expect(second.changed, isFalse);
    });
  });

  group('SyncService 本地删除', () {
    test('本地删除 + 远端存在 → 删远端并清 manifest', () async {
      final store = _MemoryDocStore(); // 本地无文档（已删）
      final server = _MemoryServer();
      server.seedDoc('a', 10);
      server.seedManifest({'a': 10});
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(
          entries: {'a': const SyncSnapshot(id: 'a', updatedAt: 10, size: 1)},
        );
      final s = _service(store, server, baseline: baseline);

      final r = await s.syncNow();
      expect(r.deletedRemote, 1);
      expect(server.files.containsKey('a'), isFalse);
      final remoteManifest = jsonDecode(
        utf8.decode(server.files['manifest.json']!),
      );
      expect((remoteManifest['entries'] as Map).containsKey('a'), isFalse);
    });
  });

  group('SyncService 仅远端存在', () {
    test('其它设备新建 → 拉取到本地', () async {
      final store = _MemoryDocStore();
      final server = _MemoryServer();
      server.seedDoc('c', 30);
      server.seedManifest({'c': 30});
      final s = _service(store, server);

      final r = await s.syncNow();
      expect(r.downloaded, 1);
      expect(store.docs.containsKey('c'), isTrue);
    });
  });

  group('SyncService 端到端加密', () {
    test('上传时服务端只见密文 blob + sealed manifest，本机可解密还原', () async {
      final cipher = _aes();
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(10), 10);
      final server = _MemoryServer();
      final s = _service(store, server, cipher: cipher);

      final r = await s.syncNow();
      expect(r.uploaded, 1);

      // 远端 manifest 是 sealed（密文 envelope），不是明文 {"entries":...}。
      final rawManifest = utf8.decode(server.files['manifest.json']!);
      final seal = jsonDecode(rawManifest) as Map<String, dynamic>;
      expect(seal.containsKey('mode'), isTrue);
      expect(seal['mode'], 'sync-manifest');
      // 用同一 cipher 打开后能还原出合法 manifest。
      final opened =
          jsonDecode(await cipher.openManifestJson(rawManifest))
              as Map<String, dynamic>;
      expect((opened['entries'] as Map).containsKey('a'), isTrue);

      // 远端文档路径 = HMAC(docId)，非明文 'a'；内容为密文。
      final remoteKey = cipher.remotePath('a');
      expect(remoteKey != 'a', isTrue);
      expect(server.files.containsKey(remoteKey), isTrue);
      expect(server.files.containsKey('a'), isFalse);
      // 密文可用同一 cipher 解回原文。
      final plain = await cipher.decryptDocumentBytes(
        Uint8List.fromList(server.files[remoteKey]!),
        'a',
      );
      expect(utf8.decode(plain), jsonEncode({'updatedAt': 10}));
    });

    test('另一台同密钥设备可下载并解密回明文；二轮无变化', () async {
      final cipher = _aes();
      // 第一台设备上传。
      final storeA = _MemoryDocStore();
      storeA.docs['a'] = _Doc('a', _localDocBytes(10), 10);
      final server = _MemoryServer();
      await _service(storeA, server, cipher: cipher).syncNow();

      // 第二台设备（空本地）用同一密钥同步 → 下载并解密。
      final storeB = _MemoryDocStore();
      final s = _service(storeB, server, cipher: cipher);
      final r1 = await s.syncNow();
      expect(r1.downloaded, 1);
      expect(
        utf8.decode(storeB.docs['a']!.bytes),
        jsonEncode({'updatedAt': 10}),
      );

      // 第二台设备再次同步 → 无变化。
      final r2 = await s.syncNow();
      expect(r2.uploaded, 0);
      expect(r2.downloaded, 0);
    });

    test('未配置 cipher（Noop）时上传/下载为明文，服务端可读 manifest', () async {
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(10), 10);
      final server = _MemoryServer();
      final s = _service(store, server);

      final r = await s.syncNow();
      expect(r.uploaded, 1);
      expect(server.files.containsKey('a'), isTrue);
      expect(server.files.containsKey('manifest.json'), isTrue);
      final manifest =
          jsonDecode(utf8.decode(server.files['manifest.json']!))
              as Map<String, dynamic>;
      expect((manifest['entries'] as Map).containsKey('a'), isTrue);
    });
  });

  group('SyncService 进度与冲突可见性', () {
    test(
      'onProgress 按阶段发射进度（started→connecting→planning→uploading→done）',
      () async {
        final store = _MemoryDocStore();
        store.docs['a'] = _Doc('a', _localDocBytes(10), 10);
        store.docs['b'] = _Doc('b', _localDocBytes(10), 10);
        final server = _MemoryServer();
        final phases = <SyncProgressPhase>[];
        final docs = <String>[];
        final s = _service(
          store,
          server,
          onProgress: (p) {
            phases.add(p.phase);
            if (p.currentDocId != null) docs.add(p.currentDocId!);
          },
        );

        final r = await s.syncNow();
        expect(r.uploaded, 2);
        expect(phases.first, SyncProgressPhase.started);
        expect(phases.contains(SyncProgressPhase.connecting), isTrue);
        expect(phases.contains(SyncProgressPhase.planning), isTrue);
        expect(phases.contains(SyncProgressPhase.uploading), isTrue);
        expect(phases.contains(SyncProgressPhase.writingManifest), isTrue);
        expect(phases.last, SyncProgressPhase.done);
        // 上传的两个文档 id 都在进度中上报。
        expect(docs, contains('a'));
        expect(docs, contains('b'));
      },
    );

    test('本地与云端都改动（相对基线）→ 报真冲突；仅单侧改动不报冲突', () async {
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(20), 20); // 本地改 10→20
      store.docs['b'] = _Doc('b', _localDocBytes(12), 12); // 本地改 10→12（旧于远端）
      final server = _MemoryServer();
      server.seedDoc('a', 15); // 远端改 10→15
      server.seedDoc('b', 30); // 远端改 10→30（新于本地）
      server.seedManifest({'a': 15, 'b': 30});
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(
          entries: {'a': _snap('a', 10), 'b': _snap('b', 10)},
        );
      final s = _service(store, server, baseline: baseline);

      final r = await s.syncNow();
      // a、b 双边都改 → 真冲突；c 未改动基线不涉及。
      expect(r.conflictedDocIds.toSet(), {'a', 'b'});
      // LWW：a 本地较新(20>15)上传，b 远端较新(30>12)下载。
      expect(r.uploaded, 1);
      expect(r.downloaded, 1);
    });

    test('仅单侧改动（另一侧未变）→ 不冲突', () async {
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(20), 20); // a 本地改
      store.docs['c'] = _Doc('c', _localDocBytes(10), 10); // c 本地未变（基线值）
      final server = _MemoryServer();
      server.seedDoc('a', 10); // a 远端未变（基线值）
      server.seedDoc('c', 15); // c 远端改
      server.seedManifest({'a': 10, 'c': 15});
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(
          entries: {'a': _snap('a', 10), 'c': _snap('c', 10)},
        );
      final s = _service(store, server, baseline: baseline);

      final r = await s.syncNow();
      // a：仅本地改 → 上传不冲突；c：仅远端改 → 下载不冲突。
      expect(r.conflictedDocIds, isEmpty);
      expect(r.uploaded, 1);
      expect(r.downloaded, 1);
    });

    test('注入 handler：裁决反转 LWW（keepLocal 拒远端、keepRemote 拒本地）', () async {
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(20), 20); // 本地较旧 vs 远端
      store.docs['b'] = _Doc('b', _localDocBytes(30), 30); // 本地较新 vs 远端
      final server = _MemoryServer();
      server.seedDoc('a', 30); // 远端较新 30
      server.seedDoc('b', 12); // 远端较旧 12
      server.seedManifest({'a': 30, 'b': 12});
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(
          entries: {'a': _snap('a', 10), 'b': _snap('b', 10)},
        );
      // 反转：a 远端新但保留本地；b 本地新但保留远端。
      final s = _service(
        store,
        server,
        baseline: baseline,
        conflictHandler: _ScriptedHandler({
          'a': ConflictResolution.keepLocal,
          'b': ConflictResolution.keepRemote,
        }),
      );

      final r = await s.syncNow();
      expect(r.conflictedDocIds.toSet(), {'a', 'b'});
      // a 被强制上传（本地 20 覆盖远端 30），b 被强制下载（远端 12 覆盖本地 30）。
      expect(r.uploaded, 1);
      expect(r.downloaded, 1);
      expect((server.files['a']), isNotNull);
      expect(
        (jsonDecode(utf8.decode(server.files['a']!))
            as Map<String, dynamic>)['updatedAt'],
        20,
      );
      expect(store.docs['b']!.updatedAt, 12);
    });

    test('注入 handler：keepBoth 本地为主 + 远端另存副本（不丢任一侧）', () async {
      final store = _MemoryDocStore();
      store.docs['c'] = _Doc('c', _localDocBytes(25), 25);
      final server = _MemoryServer();
      server.seedDoc('c', 40);
      server.seedManifest({'c': 40});
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(entries: {'c': _snap('c', 10)});
      final s = _service(
        store,
        server,
        baseline: baseline,
        conflictHandler: _ScriptedHandler({'c': ConflictResolution.keepBoth}),
      );

      final r = await s.syncNow();
      expect(r.conflictedDocIds, contains('c'));
      // 本地为主版本：c 被上传（更新为 25）。
      expect(r.uploaded, 1);
      expect(
        (jsonDecode(utf8.decode(server.files['c']!))
            as Map<String, dynamic>)['updatedAt'],
        25,
      );
      // 远端版本另存为本地副本（id 含 '-conflict-'；旧 '~' 格式过不了
      // 下游 _pathFor 白名单，见 _safeCopyId），updatedAt=40。
      final copyKey = store.docs.keys.firstWhere(
        (k) => k.contains('-conflict-'),
      );
      expect(store.docs[copyKey]!.updatedAt, 40);
    });

    test('默认 LwwConflictHandler：不覆盖（LWW 语义不变）', () async {
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(20), 20); // 本地较新
      final server = _MemoryServer();
      server.seedDoc('a', 12);
      server.seedManifest({'a': 12});
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(entries: {'a': _snap('a', 10)});
      final s = _service(store, server, baseline: baseline);

      final r = await s.syncNow();
      expect(r.uploaded, 1);
      expect(r.downloaded, 0);
      expect(
        (jsonDecode(utf8.decode(server.files['a']!))
            as Map<String, dynamic>)['updatedAt'],
        20,
      );
    });
  });

  group('SyncService M2 单操作失败隔离', () {
    test('单个上传失败 → 不中断整轮，其余文档照常同步，失败项进 failedDocIds', () async {
      final store = _MemoryDocStore();
      store.docs['good1'] = _Doc('good1', _localDocBytes(11), 11);
      store.docs['bad'] = _Doc('bad', _localDocBytes(12), 12);
      store.docs['good2'] = _Doc('good2', _localDocBytes(13), 13);
      final server = _MemoryServer()..failPut.add('bad');
      final s = _service(store, server);

      final r = await s.syncNow();

      // 失败被隔离：good1/good2 照常上传。
      expect(r.uploaded, 2);
      expect(r.failedDocIds, ['bad']);
      expect(server.files.containsKey('good1'), isTrue);
      expect(server.files.containsKey('good2'), isTrue);
      expect(server.files.containsKey('bad'), isFalse);
      // 失败项不进远端 manifest（两端都不回写失败项）。
      final remoteManifest =
          jsonDecode(utf8.decode(server.files['manifest.json']!))
              as Map<String, dynamic>;
      final entries = remoteManifest['entries'] as Map;
      expect(entries.containsKey('bad'), isFalse);
      expect(entries.containsKey('good1'), isTrue);
      // 下一轮（故障恢复后）重试成功。
      server.failPut.clear();
      final r2 = await s.syncNow();
      expect(r2.uploaded, 1);
      expect(r2.failedDocIds, isEmpty);
    });

    test('单个下载失败 → 不中断整轮，其余文档照常下载，失败项不进基线', () async {
      final store = _MemoryDocStore();
      final server = _MemoryServer()
        ..seedDoc('good', 20)
        ..seedDoc('bad', 21)
        ..seedManifest({'good': 20, 'bad': 21})
        ..failGet.add('bad');
      final s = _service(store, server);

      final r = await s.syncNow();

      expect(r.downloaded, 1);
      expect(r.failedDocIds, ['bad']);
      expect(store.docs.containsKey('good'), isTrue);
      expect(store.docs.containsKey('bad'), isFalse);
      // 基线只收录成功项：'bad' 下轮仍是「仅远端 → 下载」。
      // （通过下一轮重试成功来验证，而非直接窥探 baseline 内部。）
      server.failGet.clear();
      final r2 = await s.syncNow();
      expect(r2.downloaded, 1);
      expect(r2.failedDocIds, isEmpty);
      expect(store.docs['bad']!.updatedAt, 21);
    });

    test('毒丸防误删：仅远端文档下载失败 → 远端文档必须完好、二轮补齐', () async {
      final store = _MemoryDocStore();
      final server = _MemoryServer();
      server.seedDoc('poison', 30);
      server.seedManifest({'poison': 30});
      server.failGet.add('poison');
      final s = _service(store, server);

      final r1 = await s.syncNow();
      expect(r1.downloaded, 0);
      expect(r1.failedDocIds, ['poison']);

      // 关键断言：远端文档没有被当作「本地删除墓碑」而 deleteRemote。
      expect(server.files.containsKey('poison'), isTrue);
      final remoteManifest =
          jsonDecode(utf8.decode(server.files['manifest.json']!))
              as Map<String, dynamic>;
      expect((remoteManifest['entries'] as Map).containsKey('poison'), isTrue);

      // 网络恢复后二轮补齐。
      server.failGet.clear();
      final r2 = await s.syncNow();
      expect(r2.downloaded, 1);
      expect(store.docs['poison']!.updatedAt, 30);
    });

    test('本地已有文档的下载失败 → 不影响本地版本与基线收录', () async {
      // 本地存在该文档，下载失败只跳过更新，不产生毒丸问题。
      final store = _MemoryDocStore();
      store.docs['d'] = _Doc('d', _localDocBytes(10), 10);
      final server = _MemoryServer()
        ..seedDoc('d', 20)
        ..seedManifest({'d': 20})
        ..failGet.add('d');
      final s = _service(store, server);

      final r = await s.syncNow();
      expect(r.failedDocIds, ['d']);
      // 本地版本保持 10 不被破坏。
      expect(store.docs['d']!.updatedAt, 10);
    });
  });

  group('SyncService M4 keepBoth 副本收敛', () {
    test('keepBoth 副本当轮进入基线（避免下轮重传）', () async {
      final store = _MemoryDocStore();
      store.docs['c'] = _Doc('c', _localDocBytes(25), 25);
      final server = _MemoryServer();
      server.seedDoc('c', 40);
      server.seedManifest({'c': 40});
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(entries: {'c': _snap('c', 10)});
      final s = _service(
        store,
        server,
        baseline: baseline,
        conflictHandler: _ScriptedHandler({'c': ConflictResolution.keepBoth}),
      );

      final r1 = await s.syncNow();
      expect(r1.conflictedDocIds, contains('c'));
      expect(r1.uploaded, 1);

      // M4：副本已入基线 → 第二轮把副本当「本地新增」正常上传（不再是
      // 原实现的「重传一次主版本路径」）；第三轮起完全稳定。
      final r2 = await s.syncNow();
      expect(r2.uploaded, 1);
      expect(r2.failedDocIds, isEmpty);
      final r3 = await s.syncNow();
      expect(r3.changed, isFalse);
      expect(r3.uploaded, 0);
    });
  });

  group('SyncService M6 sameTsDiverged（同 ts 不同 size）', () {
    test('同 updatedAt 不同 size → 报冲突；默认 LWW 保留本地', () async {
      final store = _MemoryDocStore();
      // 本地：updatedAt=20，size = _localDocBytes(20).length
      store.docs['x'] = _Doc('x', _localDocBytes(20), 20);
      final server = _MemoryServer();
      // 远端：updatedAt=20，但 size 被篡改为 999（模拟同毫秒双端编辑 /
      // 时钟偏移巧合导致的内容分叉）。
      server.seedDoc('x', 20);
      final realSize = _localDocBytes(20).length;
      // 手动写 manifest，让 size 与本地不同。
      final entries = {
        'x': {'id': 'x', 'updatedAt': 20, 'size': 999},
      };
      server.files['manifest.json'] = utf8.encode(
        jsonEncode({'entries': entries, 'deletedIds': <String>[]}),
      );
      // 基线：updatedAt=10（两端相对基线都「变过」的语义不重要，因为
      // sameTsDiverged 不依赖基线比较）。
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(entries: {'x': _snap('x', 10)});
      final s = _service(store, server, baseline: baseline);

      final r = await s.syncNow();
      // M6：同 ts 不同 size 必须报冲突（旧实现会被 planner 「== → 忽略」吞掉）。
      expect(r.conflictedDocIds, contains('x'));
      // 默认 LwwConflictHandler 不覆盖 → 走 LWW 兜底：ts 相等时保留本地
      // （本地上传覆盖远端，让远端收敛到本地版本）。
      expect(r.uploaded, 1);
      expect(r.downloaded, 0);
      expect(
        (jsonDecode(utf8.decode(server.files['x']!))
            as Map<String, dynamic>)['updatedAt'],
        20,
      );
      // 真实 size 未被 999 污染。
      expect(server.files['x']!.length, realSize);
    });

    test('同 updatedAt 同 size → 不冲突（真·无变化）', () async {
      final store = _MemoryDocStore();
      store.docs['y'] = _Doc('y', _localDocBytes(20), 20);
      final server = _MemoryServer();
      server.seedDoc('y', 20);
      server.seedManifest({'y': 20});
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(entries: {'y': _snap('y', 10)});
      final s = _service(store, server, baseline: baseline);

      final r = await s.syncNow();
      // 同 ts 同 size → 真无变化，不报冲突。
      expect(r.conflictedDocIds, isEmpty);
      expect(r.uploaded, 0);
      expect(r.downloaded, 0);
      expect(r.changed, isFalse);
    });
  });
}

class _ScriptedHandler implements ConflictHandler {
  _ScriptedHandler(this.map);
  final Map<String, ConflictResolution> map;
  @override
  Future<Map<String, ConflictResolution>> resolve(
    List<SyncConflict> conflicts,
  ) async => map;
}

SyncSnapshot _snap(String id, int updatedAt) => SyncSnapshot(
  id: id,
  updatedAt: updatedAt,
  size: _localDocBytes(updatedAt).length,
);
