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
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';

const _base = 'http://dav.example.com/sync/';

/// 内存 WebDAV 服务器：key = 相对路径（如 'a' / 'manifest.json'）。
class _MemoryServer {
  final Map<String, List<int>> files = {};

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

  /// 预置远端 manifest。
  void seedManifest(Map<String, int> idToUpdatedAt) {
    final entries = {
      for (final e in idToUpdatedAt.entries)
        e.key: {'id': e.key, 'updatedAt': e.value, 'size': 0},
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
            if (rel.isNotEmpty && files.containsKey(rel)) {
              return http.Response.bytes(files[rel]!, 200);
            }
            return http.Response('', 404);
          case 'PUT':
            if (rel.isNotEmpty) files[rel] = request.bodyBytes;
            return http.Response('', 201);
          case 'DELETE':
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
      .map((e) => SyncDocMeta(
            id: e.key,
            updatedAt: e.value.updatedAt,
            size: e.value.bytes.length,
          ))
      .toList();

  @override
  Future<Uint8List?> readDocument(String id) async => docs[id]?.bytes;

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async {
    final ts = (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['updatedAt']
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
}) =>
    SyncService(
      transport: WebDavSyncClient(baseUrl: Uri.parse(_base), client: server.client()),
      documentStore: store,
      baselineStore: baseline ?? _MemoryBaseline(),
      cipher: cipher,
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
      final remoteManifest = jsonDecode(utf8.decode(server.files['manifest.json']!));
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
      final baseline = _MemoryBaseline()..value = SyncManifest(
            entries: {'a': const SyncSnapshot(id: 'a', updatedAt: 10, size: 1)},
          );
      final s = _service(store, server, baseline: baseline);

      final r = await s.syncNow();
      expect(r.deletedRemote, 1);
      expect(server.files.containsKey('a'), isFalse);
      final remoteManifest = jsonDecode(utf8.decode(server.files['manifest.json']!));
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
      final opened = jsonDecode(await cipher.openManifestJson(rawManifest))
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
      expect(utf8.decode(storeB.docs['a']!.bytes), jsonEncode({'updatedAt': 10}));

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
      final manifest = jsonDecode(utf8.decode(server.files['manifest.json']!))
          as Map<String, dynamic>;
      expect((manifest['entries'] as Map).containsKey('a'), isTrue);
    });
  });

  group('SyncService 进度与冲突可见性', () {
    test('onProgress 按阶段发射进度（started→connecting→planning→uploading→done）', () async {
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(10), 10);
      store.docs['b'] = _Doc('b', _localDocBytes(10), 10);
      final server = _MemoryServer();
      final phases = <SyncProgressPhase>[];
      final docs = <String>[];
      final s = _service(store, server, onProgress: (p) {
        phases.add(p.phase);
        if (p.currentDocId != null) docs.add(p.currentDocId!);
      });

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
    });

    test('本地与云端都改动（相对基线）→ 报真冲突；仅单侧改动不报冲突', () async {
      final store = _MemoryDocStore();
      store.docs['a'] = _Doc('a', _localDocBytes(20), 20); // 本地改 10→20
      store.docs['b'] = _Doc('b', _localDocBytes(12), 12); // 本地改 10→12（旧于远端）
      final server = _MemoryServer();
      server.seedDoc('a', 15); // 远端改 10→15
      server.seedDoc('b', 30); // 远端改 10→30（新于本地）
      server.seedManifest({'a': 15, 'b': 30});
      final baseline = _MemoryBaseline()
        ..value = SyncManifest(entries: {
          'a': _snap('a', 10),
          'b': _snap('b', 10),
        });
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
        ..value = SyncManifest(entries: {
          'a': _snap('a', 10),
          'c': _snap('c', 10),
        });
      final s = _service(store, server, baseline: baseline);

      final r = await s.syncNow();
      // a：仅本地改 → 上传不冲突；c：仅远端改 → 下载不冲突。
      expect(r.conflictedDocIds, isEmpty);
      expect(r.uploaded, 1);
      expect(r.downloaded, 1);
    });
  });
}

SyncSnapshot _snap(String id, int updatedAt) => SyncSnapshot(
      id: id,
      updatedAt: updatedAt,
      size: _localDocBytes(updatedAt).length,
    );
