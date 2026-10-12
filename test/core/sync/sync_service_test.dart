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

  /// 故障注入（DN-001）：GET 这些相对路径**即便文件真实存在也返回 404**。
  /// 与 [failGet]（500 → 抛异常）分列：`getBytes` 返回 null 是另一条分支，
  /// 旧实现把它计成成功，进而让基线盖上一条「本地根本没有」的远端快照。
  final Set<String> notFoundGet = {};

  /// 收到过的 DELETE 相对路径（DN-001：断言「缺失跳过」不会升级为删除墓碑）。
  final List<String> deletes = [];

  /// DN-104：远端清单版本号。每次成功 PUT manifest 自增，GET manifest 时作为
  /// ETag 返回。用于模拟「另一台设备在我们读取之后改了清单」。
  int manifestVersion = 0;

  /// DN-104：PUT 携带过的 (相对路径, If-Match)。记路径是因为**文档上传**也走
  /// PUT（不带 If-Match），只看 If-Match 列表会把上传那条 `null` 混进来。
  final List<(String, String?)> puts = [];

  /// 只取清单 PUT 的 If-Match 序列（DN-104 断言用）。
  List<String?> get manifestPuts =>
      [for (final p in puts) if (p.$1 == 'manifest.json') p.$2];

  /// DN-104：GET manifest 返回**之后**触发一次（模拟另一台设备紧接着写回）。
  void Function()? afterGetManifest;

  /// DN-104：置 true 时 GET manifest **不返回 ETag**——模拟不支持条件写入的
  /// WebDAV 服务端，用于验证客户端退回无条件 PUT。
  bool suppressManifestEtag = false;

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
        if (notFoundGet.contains(rel)) return http.Response('', 404);
        if (rel.isNotEmpty && files.containsKey(rel)) {
          // DN-104：manifest 带 ETag（真实 WebDAV 服务端行为）。
          final headers = rel == 'manifest.json' && !suppressManifestEtag
              ? {'etag': 'v$manifestVersion'}
              : <String, String>{};
          final resp = http.Response.bytes(files[rel]!, 200, headers: headers);
          if (rel == 'manifest.json') {
            final hook = afterGetManifest;
            afterGetManifest = null; // 只触发一次
            hook?.call();
          }
          return resp;
        }
        return http.Response('', 404);
      case 'PUT':
        if (failPut.contains(rel)) return http.Response('', 500);
        final ifMatch = request.headers['if-match'] ?? request.headers['If-Match'];
        puts.add((rel, ifMatch));
        // DN-104：manifest 走条件写入——版本对不上即 412（别的设备抢先改过）。
        if (rel == 'manifest.json' &&
            ifMatch != null &&
            ifMatch != 'v$manifestVersion') {
          return http.Response('', 412);
        }
        if (rel.isNotEmpty) files[rel] = request.bodyBytes;
        if (rel == 'manifest.json') manifestVersion++;
        return http.Response('', 201);
      case 'DELETE':
        if (failDelete.contains(rel)) return http.Response('', 500);
        deletes.add(rel);
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
  Future<SyncLocalInventory> listDocuments() async => SyncLocalInventory(
    readable: docs.entries
        .map(
          (e) => SyncDocMeta(
            id: e.key,
            updatedAt: e.value.updatedAt,
            size: e.value.bytes.length,
          ),
        )
        .toList(),
  );

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

/// 「列出来了、却读不到」的本地存储门面（DN-001）：`listDocuments` 照常上报，
/// `readDocument` 对 [blockRead] 里的 id 返回 null。真实对应两条生产路径——
/// ① `listDocuments` 之后文件被删（同一轮内的竞争窗口）；
/// ② 保险库锁定：`note_block_doc_sync_store.readDocument` 把
///    `BlockDocLockedException` 折成 null（N2 口径：按缺失处理，不解锁受密内容）。
class _VanishingDocStore implements SyncDocumentStore {
  _VanishingDocStore(this.inner);

  final _MemoryDocStore inner;
  final Set<String> blockRead = {};

  Map<String, _Doc> get docs => inner.docs;

  @override
  Future<SyncLocalInventory> listDocuments() => inner.listDocuments();

  @override
  Future<Uint8List?> readDocument(String id) async =>
      blockRead.contains(id) ? null : inner.readDocument(id);

  @override
  Future<void> writeDocument(String id, Uint8List bytes) =>
      inner.writeDocument(id, bytes);

  @override
  Future<void> deleteDocument(String id) => inner.deleteDocument(id);
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
  SyncDocumentStore store,
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

  group('SyncService DN-001 文件不存在是显式结果（不得计成功）', () {
    test('上传腿本地文件消失 → 不计成功、清单不新增条目、基线不推进；下轮自愈', () async {
      final store = _VanishingDocStore(_MemoryDocStore());
      store.docs['a'] = _Doc('a', _localDocBytes(10), 10);
      store.docs['z'] = _Doc('z', _localDocBytes(11), 11);
      // 清单列完之后才读不到（listDocuments 与 readDocument 之间的竞争，
      // 或保险库锁定：受密内容按缺失处理、不解锁）。
      store.blockRead.add('a');
      final server = _MemoryServer();
      final baseline = _MemoryBaseline();
      final s = _service(store, server, baseline: baseline);

      final r1 = await s.syncNow();
      // 缺失不是成功：本轮只算 z 真上了云。
      expect(r1.uploaded, 1);
      expect(r1.skippedMissingDocIds, ['a']);
      // 跳过 ≠ 执行失败（与本仓 keepBoth 守卫用例「跳过不等于执行失败」同分工）。
      expect(r1.failedDocIds, isEmpty);
      // 远端清单不得为它凭空造条目（云端一个字节都没有）。
      final entries = _remoteEntries(server);
      expect(entries.containsKey('a'), isFalse);
      expect(entries.containsKey('z'), isTrue);
      // 基线同样不推进。
      expect(baseline.value!.entries.containsKey('a'), isFalse);
      expect(server.deletes, isEmpty);

      // 自愈：文件恢复可读后它仍被当作待处理（旧实现在这里永久静默）。
      store.blockRead.clear();
      final r2 = await s.syncNow();
      expect(r2.uploaded, 1);
      expect(r2.skippedMissingDocIds, isEmpty);
      expect(server.files.containsKey('a'), isTrue);
      expect(baseline.value!.entries.containsKey('a'), isTrue);
    });

    test('上传跳过的既有文档：清单与基线都保留旧快照，两端指纹仍不同 ⇒ 下轮仍判上传', () async {
      final store = _VanishingDocStore(_MemoryDocStore());
      store.docs['b'] = _Doc('b', _localDocBytes(20), 20); // 本地较新
      store.blockRead.add('b');
      final server = _MemoryServer()
        ..seedDoc('b', 10)
        ..seedManifest({'b': 10});
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(entries: {'b': _snap('b', 10)});
      final s = _service(store, server, baseline: baseline);

      final r1 = await s.syncNow();
      expect(r1.uploaded, 0);
      expect(r1.skippedMissingDocIds, ['b']);
      // 关键：回写的清单仍是云端旧值 10，而不是本地快照 20——旧实现盖上 20
      // 后「本地 == 远端」，冲突检测与 planner 双双静默。
      expect((_remoteEntries(server)['b'] as Map)['updatedAt'], 10);
      expect(baseline.value!.entries['b']!.updatedAt, 10);
      expect(server.files['b']!.length, _localDocBytes(10).length);

      store.blockRead.clear();
      final r2 = await s.syncNow();
      expect(r2.uploaded, 1);
      expect(r2.skippedMissingDocIds, isEmpty);
      expect((_remoteEntries(server)['b'] as Map)['updatedAt'], 20);
      expect(baseline.value!.entries['b']!.updatedAt, 20);
    });

    test('下载腿远端 404 → 不计成功、不产生删除墓碑；清单条目保留待下轮重试', () async {
      final store = _MemoryDocStore();
      // 清单登记了 ghost@30，但对象根本不存在（崩溃窗口 / 残缺远端）。
      final server = _MemoryServer()..seedManifest({'ghost': 30});
      final baseline = _MemoryBaseline();
      final s = _service(store, server, baseline: baseline);

      final r1 = await s.syncNow();
      expect(r1.downloaded, 0);
      expect(r1.skippedMissingDocIds, ['ghost']);
      expect(r1.failedDocIds, isEmpty);
      expect(store.docs.containsKey('ghost'), isFalse);
      // 基线绝不能收下这条「本地根本没有」的远端快照——那正是删除墓碑的种子。
      expect(baseline.value!.entries.containsKey('ghost'), isFalse);
      // 没核实过的条目保留在远端清单里（不擅自清账）。
      expect(_remoteEntries(server).containsKey('ghost'), isTrue);

      // 第二轮：仍是「仅远端 → 下载」，绝不升级成 deleteRemote。
      final r2 = await s.syncNow();
      expect(r2.downloaded, 0);
      expect(r2.skippedMissingDocIds, ['ghost']);
      expect(server.deletes, isEmpty);
      expect(_remoteEntries(server).containsKey('ghost'), isTrue);

      // 对象补上后自愈。
      server.seedDoc('ghost', 30);
      final r3 = await s.syncNow();
      expect(r3.downloaded, 1);
      expect(r3.skippedMissingDocIds, isEmpty);
      expect(store.docs['ghost']!.updatedAt, 30);
    });

    test('服务器对活对象误报 404 → 三轮都不 DELETE 真实云端文件，恢复后补齐下载', () async {
      final store = _MemoryDocStore();
      final server = _MemoryServer()
        ..seedDoc('live', 30)
        ..seedManifest({'live': 30})
        ..notFoundGet.add('live'); // 文件在，GET 却报 404
      final baseline = _MemoryBaseline();
      final s = _service(store, server, baseline: baseline);

      final r1 = await s.syncNow();
      expect(r1.downloaded, 0);
      expect(r1.skippedMissingDocIds, ['live']);
      // 旧实现计成功 ⇒ 基线盖上 live@30 ⇒ 下轮「本地无 + 基线有」判成本地
      // 删除墓碑 ⇒ 真实云端文件被删（数据丢失）。连续三轮都必须无 DELETE。
      await s.syncNow();
      final r3 = await s.syncNow();
      expect(r3.skippedMissingDocIds, ['live']);
      expect(server.deletes, isEmpty);
      expect(server.files.containsKey('live'), isTrue);
      expect(_remoteEntries(server).containsKey('live'), isTrue);

      server.notFoundGet.clear();
      final r4 = await s.syncNow();
      expect(r4.downloaded, 1);
      expect(store.docs['live']!.updatedAt, 30);
    });

    test('三语义分立并钉死：真成功 / 真失败（毒丸保护）/ 缺失跳过（不回写基线）', () async {
      final store = _VanishingDocStore(_MemoryDocStore());
      store.docs['okUp'] = _Doc('okUp', _localDocBytes(11), 11);
      store.docs['failUp'] = _Doc('failUp', _localDocBytes(12), 12);
      store.docs['missUp'] = _Doc('missUp', _localDocBytes(13), 13);
      store.blockRead.add('missUp');
      final server = _MemoryServer()
        ..seedDoc('okDown', 21)
        ..seedDoc('failDown', 22)
        ..seedManifest({'okDown': 21, 'failDown': 22, 'missDown': 23})
        ..failGet.add('failDown') // 真失败：500（抛异常路径）
        ..failPut.add('failUp'); //  真失败：500（抛异常路径）
      // missDown：清单登记了、对象却不存在 → 下载腿 404（返回 null 路径）。
      final baseline = _MemoryBaseline();
      final s = _service(store, server, baseline: baseline);

      final r = await s.syncNow();
      // ① 真成功：计数 + 远端清单 + 基线三处一起推进（既有行为一字不变）。
      expect(r.uploaded, 1);
      expect(r.downloaded, 1);
      // ② 真失败：走毒丸保护的 failedDocIds。
      expect(r.failedDocIds.toSet(), {'failUp', 'failDown'});
      expect(r.unreadableDocIds, isEmpty);
      // ③ 缺失跳过：独立通道，且不混进失败表。
      expect(r.skippedMissingDocIds.toSet(), {'missUp', 'missDown'});

      final entries = _remoteEntries(server);
      expect(entries.containsKey('okUp'), isTrue);
      expect(entries.containsKey('okDown'), isTrue);
      expect(entries.containsKey('failUp'), isFalse);
      expect(entries.containsKey('missUp'), isFalse);
      expect(entries.containsKey('missDown'), isTrue); // 未核实 ⇒ 保留登记

      final base = baseline.value!.entries;
      expect(base.containsKey('okUp'), isTrue);
      expect(base.containsKey('okDown'), isTrue);
      expect(base.containsKey('failUp'), isFalse);
      expect(base.containsKey('failDown'), isFalse); // 毒丸保护
      expect(base.containsKey('missUp'), isFalse);
      expect(base.containsKey('missDown'), isFalse); // 同一保护，不同原因

      // 本地落地只发生在真成功的下载上。
      expect(store.inner.docs.containsKey('okDown'), isTrue);
      expect(store.inner.docs.containsKey('failDown'), isFalse);
      expect(store.inner.docs.containsKey('missDown'), isFalse);
      // 无论失败还是跳过，都绝不升级为删除。
      expect(server.deletes, isEmpty);
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

  group('远端 manifest 解析防护（B9/B10）', () {
    test('manifest 非 JSON 对象 → FormatException（不裸抛 TypeError）', () async {
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(10), 10);
      final server = _MemoryServer();
      // 远端可被写入任意内容（他人设备/篡改）——数组不是合法 manifest。
      server.files['manifest.json'] = utf8.encode('[1,2,3]');
      final s = _service(store, server);

      expect(s.syncNow(), throwsFormatException);
    });

    test('manifest 条目字段类型畸形 → FormatException（fail-closed）', () async {
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(10), 10);
      final server = _MemoryServer();
      server.files['manifest.json'] = utf8.encode(
        jsonEncode({
          'entries': {
            'a': {'id': 'a', 'updatedAt': 'not-an-int'},
          },
        }),
      );
      final s = _service(store, server);

      expect(s.syncNow(), throwsFormatException);
    });
  });

  group('SyncService DN-107 锁定笔记不得被误判为删除（P0 数据安全）', () {
    test('已同步的受密笔记重新锁定 → 连续三轮同步都不得 DELETE 云端副本', () async {
      final server = _MemoryServer();
      final store = _MemoryDocStore();
      final baseline = _MemoryBaseline();

      // 第一轮：笔记处于解锁态，正常同步一次（建立基线 + 云端副本）。
      store.docs['secret'] = _Doc('secret', _localDocBytes(1000), 1000);
      server.seedDoc('secret', 1000);
      server.seedManifest({'secret': 1000});
      final first = await _service(store, server, baseline: baseline).syncNow();
      expect(first.failedDocIds, isEmpty);
      expect(server.deletes, isEmpty, reason: '首轮为正常同步，不应产生任何删除');
      expect(_remoteEntries(server).containsKey('secret'), isTrue);

      // 应用关闭重开、笔记尚未解锁：文件仍在本地磁盘，但读不出来。
      final locked = _LockedDocStore(store)..locked.add('secret');
      expect(locked.docs.containsKey('secret'), isTrue, reason: '文件确实还在本地');

      // 连续三轮同步：每轮都必须「什么都不做」——读取不到 ≠ 用户删除。
      for (var round = 1; round <= 3; round++) {
        final r = await _service(locked, server, baseline: baseline).syncNow();
        expect(server.deletes, isEmpty, reason: '第 $round 轮：绝不允许 DELETE 云端副本');
        expect(r.deletedRemote, 0, reason: '第 $round 轮：删除计数必须为 0');
        expect(
          _remoteEntries(server).containsKey('secret'),
          isTrue,
          reason: '第 $round 轮：云端清单不得移除该笔记',
        );
        expect(locked.docs.containsKey('secret'), isTrue, reason: '第 $round 轮：本地文件不得被删');
      }

      // 解锁后恢复正常：内容未变，仍是「无需操作」。
      final unlocked = _LockedDocStore(store)..locked.clear();
      final after = await _service(unlocked, server, baseline: baseline).syncNow();
      expect(after.deletedRemote, 0);
      expect(server.deletes, isEmpty);
      expect(_remoteEntries(server).containsKey('secret'), isTrue);
    });

    test('锁定笔记不在基线中（从未同步过）→ 不上传也不删除', () async {
      final server = _MemoryServer();
      server.seedManifest(<String, int>{});
      final store = _MemoryDocStore();
      store.docs['never-synced'] = _Doc('never-synced', _localDocBytes(5), 5);
      final locked = _LockedDocStore(store)..locked.add('never-synced');

      final r = await _service(locked, server, baseline: _MemoryBaseline()).syncNow();

      expect(server.deletes, isEmpty, reason: '从未同步过的锁定笔记不得触发任何删除');
      expect(r.uploaded, 0, reason: '锁定期间不解锁内容，不得上传');
      expect(_remoteEntries(server).containsKey('never-synced'), isFalse);
      expect(locked.docs.containsKey('never-synced'), isTrue, reason: '本地文件必须原样保留');
    });
  });

  group('SyncService DN-104 多设备清单并发（条件写入）', () {
    test('设备 B 抢先写回 → 设备 A 收 412 后合并重试，双方条目都保留', () async {
      final server = _MemoryServer();
      server.seedManifest(<String, int>{}); // A 先读到空清单（ETag v0）
      final baseline = _MemoryBaseline();

      final storeA = _MemoryDocStore();
      storeA.docs['doc-a'] = _Doc('doc-a', _localDocBytes(100), 100);

      // 模拟「A 读到清单之后、写回之前，B 抢先写入了 doc-b」。
      server.afterGetManifest = () {
        server.files['manifest.json'] = utf8.encode(
          jsonEncode({
            'entries': {
              'doc-b': {
                'id': 'doc-b',
                'updatedAt': 200,
                'size': _localDocBytes(200).length,
              },
            },
            'deletedIds': <String>[],
          }),
        );
        server.manifestVersion++;
      };

      final result = await _service(storeA, server, baseline: baseline).syncNow();

      expect(result.failedDocIds, isEmpty, reason: '412 应被合并重试消化，不记为失败');
      expect(
        server.manifestPuts,
        ['v0', 'v1'],
        reason: '必须走 If-Match 条件写入，并在 412 后换新 ETag 重试',
      );
      // 核心断言：双方合法更新都在最终清单里。
      final entries = _remoteEntries(server);
      expect(entries.containsKey('doc-a'), isTrue, reason: '本设备的新增不能被覆盖');
      expect(entries.containsKey('doc-b'), isTrue, reason: '对方设备的新增不能被丢掉');
    });

    test('服务器不返回 ETag → 退回无条件写（兼容不支持条件写入的服务端）', () async {
      final server = _MemoryServer()..suppressManifestEtag = true;
      server.seedManifest(<String, int>{});
      final store = _MemoryDocStore();
      store.docs['doc-a'] = _Doc('doc-a', _localDocBytes(100), 100);

      final result = await _service(
        store,
        server,
        baseline: _MemoryBaseline(),
      ).syncNow();

      expect(result.failedDocIds, isEmpty);
      expect(server.manifestPuts, [null], reason: '无 ETag 时不得发送 If-Match');
      expect(_remoteEntries(server).containsKey('doc-a'), isTrue);
    });
  });
}

/// 「存在但锁定」的本地存储门面（DN-107，P0 数据安全）：`listDocuments()`
/// 把 [locked] 里的 id 归入 `unreadable`，真实对应 `NoteBlockDocSyncStore`
/// 捕获 `BlockDocLockedException` 后**如实上报**（而不是从清单里静默消失）。
class _LockedDocStore implements SyncDocumentStore {
  _LockedDocStore(this.inner);

  final _MemoryDocStore inner;
  final Set<String> locked = {};

  Map<String, _Doc> get docs => inner.docs;

  @override
  Future<SyncLocalInventory> listDocuments() async {
    final all = await inner.listDocuments();
    return SyncLocalInventory(
      readable: [
        for (final d in all.readable)
          if (!locked.contains(d.id)) d,
      ],
      unreadable: {
        ...all.unreadable,
        for (final d in all.readable)
          if (locked.contains(d.id)) d.id,
      },
    );
  }

  @override
  Future<Uint8List?> readDocument(String id) async =>
      locked.contains(id) ? null : inner.readDocument(id);

  @override
  Future<void> writeDocument(String id, Uint8List bytes) =>
      inner.writeDocument(id, bytes);

  @override
  Future<void> deleteDocument(String id) => inner.deleteDocument(id);
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

/// 读回远端 manifest 的条目表（DN-001 用例反复断言清单是否被推进）。
Map _remoteEntries(_MemoryServer server) =>
    (jsonDecode(utf8.decode(server.files['manifest.json']!))
            as Map)['entries']
        as Map;
