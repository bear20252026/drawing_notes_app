// 由 Claude 团队生成 | Drawing Notes App
// SyncService 集成测试：用内存文档存储 + MockClient 模拟 WebDAV 服务器，
// 验证「拉 manifest → 比对 → 上传/下载/删远端 → 回写两端 manifest」闭环。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
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
}) =>
    SyncService(
      transport: WebDavSyncClient(baseUrl: Uri.parse(_base), client: server.client()),
      documentStore: store,
      baselineStore: baseline ?? _MemoryBaseline(),
    );

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
}
