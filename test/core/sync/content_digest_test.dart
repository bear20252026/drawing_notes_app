// DN-206（第三轮专家审计 2026-10-13）：同步指纹必须有内容摘要。
//
// 缺陷形状很窄但要命：同一毫秒保存、字节数恰好相同的两次不同编辑，
// 在旧指纹（updatedAt + size）下**完全一样** ⇒ planner 的「== → 忽略」与
// 冲突检测的 `local == remote → continue` 双双静默，两端永久分叉，
// 而且没有任何自愈路径（下一次编辑之前谁都不会动它）。
//
// 本文件钉四组：
//  ① 摘要的 JSON 形状与向后兼容（缺键=null；畸形=整轮中止；只在有值时写键）；
//  ② `==` 刻意不含摘要 + `contentDiffersFrom` 的「缺摘要即不可比」——
//     这两条合起来保证升级后的第一轮不会把全库报成冲突（假红风暴）；
//  ③ 平局必须报冲突、默认裁决是 keepBoth（两边都留），且**副本保留真的被执行**
//     ——旧写法在这里默认「保留本地并上传」，等于静默盖掉云端那一版；
//  ④ 存储层：同 updatedAt、同字节数、不同内容 ⇒ 摘要真的不同（同源同一次编码）。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_sync_store.dart';
import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/post_restore_baseline.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';
import '../../helpers/temp_dir_cleanup.dart';

const _base = 'https://dav.example.com/sync/';

Uint8List _bytes(String content) => Uint8List.fromList(utf8.encode(content));

void main() {
  group('DN-206 摘要的相等性与 JSON 形状', () {
    test('同 ts 同 size 不同摘要：结构相等仍为 true（升级兼容的关键）', () {
      const a = SyncSnapshot(id: 'x', updatedAt: 20, size: 7, digest: 'aaaa');
      const b = SyncSnapshot(id: 'x', updatedAt: 20, size: 7, digest: 'bbbb');
      expect(a, equals(b));
      expect(a.contentDiffersFrom(b), isTrue);
    });

    test('任一侧缺摘要 ⇒ 不可比，绝不判成「内容不同」', () {
      const withDigest = SyncSnapshot(
        id: 'x',
        updatedAt: 20,
        size: 7,
        digest: 'aaaa',
      );
      const without = SyncSnapshot(id: 'x', updatedAt: 20, size: 7);
      expect(without.contentDiffersFrom(withDigest), isFalse);
      expect(withDigest.contentDiffersFrom(without), isFalse);
    });

    test('只在有摘要时写键；往返保真；缺键读回 null', () {
      final withDigest = SyncManifest(
        entries: {
          'x': const SyncSnapshot(
            id: 'x',
            updatedAt: 20,
            size: 7,
            digest: 'deadbeef00000000',
          ),
        },
      );
      final json = withDigest.toJson();
      final entry = (json['entries'] as Map)['x'] as Map<String, dynamic>;
      expect(entry['digest'], 'deadbeef00000000');

      final back = SyncManifest.fromJson(json);
      expect(back.entries['x']!.digest, 'deadbeef00000000');

      // 旧版本写的清单（没有 digest 键）必须能读，且读出 null。
      final legacy = SyncManifest.fromJson({
        'entries': {
          'x': {'id': 'x', 'updatedAt': 20, 'size': 7},
        },
        'deletedIds': <String>[],
      });
      expect(legacy.entries['x']!.digest, isNull);

      // 没摘要时不该把键写成 null（与 v4 样式字段同一条「只写偏离」纪律）。
      final noDigest = SyncManifest(
        entries: {
          'x': const SyncSnapshot(id: 'x', updatedAt: 20, size: 7),
        },
      );
      expect(
        ((noDigest.toJson()['entries'] as Map)['x'] as Map).containsKey('digest'),
        isFalse,
      );
    });

    test('畸形摘要（非字符串 / 超长）⇒ 整轮中止，不猜意图', () {
      expect(
        () => SyncManifest.fromJson({
          'entries': {
            'x': {'id': 'x', 'updatedAt': 20, 'size': 7, 'digest': 123},
          },
          'deletedIds': <String>[],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SyncManifest.fromJson({
          'entries': {
            'x': {
              'id': 'x',
              'updatedAt': 20,
              'size': 7,
              'digest': 'a' * 5000,
            },
          },
          'deletedIds': <String>[],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DN-206 平局冲突', () {
    const snap = SyncSnapshot(
      id: 'x',
      updatedAt: 20,
      size: 7,
      digest: 'aaaa',
    );
    const remoteSameFingerprint = SyncSnapshot(
      id: 'x',
      updatedAt: 20,
      size: 7,
      digest: 'bbbb',
    );

    test('同 ts 同 size 仅摘要不同 ⇒ 报冲突，且默认裁决 keepBoth', () {
      final conflicts = detectSyncConflicts(
        {'x': snap},
        SyncManifest(entries: {'x': remoteSameFingerprint}),
        // 基线取两端之一：相对基线「谁改过」在平局里没有可靠答案，
        // 判据靠 fingerprintTie 而不是基线比较。
        SyncManifest(entries: {'x': snap}),
      );

      expect(conflicts, hasLength(1), reason: '旧实现在这里 continue，永久静默分叉');
      expect(conflicts.single.fingerprintTie, isTrue);
      expect(conflicts.single.lwwTimestampSuspect, isTrue);
      expect(conflicts.single.suggestedResolution, ConflictResolution.keepBoth);
      expect(conflicts.single.localDigest, 'aaaa');
      expect(conflicts.single.remoteDigest, 'bbbb');
    });

    test('反向锁：两端都没有摘要（旧客户端）⇒ 不报冲突（不得制造升级风暴）', () {
      final conflicts = detectSyncConflicts(
        {'x': const SyncSnapshot(id: 'x', updatedAt: 20, size: 7)},
        SyncManifest(
          entries: {
            'x': const SyncSnapshot(id: 'x', updatedAt: 20, size: 7),
          },
        ),
        SyncManifest(
          entries: {
            'x': const SyncSnapshot(id: 'x', updatedAt: 10, size: 7),
          },
        ),
      );
      expect(conflicts, isEmpty);
    });

    test('反向锁：只有一端有摘要 ⇒ 不可比，不报冲突', () {
      final conflicts = detectSyncConflicts(
        {'x': snap},
        SyncManifest(
          entries: {
            'x': const SyncSnapshot(id: 'x', updatedAt: 20, size: 7),
          },
        ),
        SyncManifest(entries: {'x': snap}),
      );
      expect(conflicts, isEmpty);
    });

    test('平局冲突 planner 给不出方向 ⇒ 有效裁决补出操作，且带 keepBoth', () {
      const local = SyncManifest(entries: {'x': snap});
      const remote = SyncManifest(entries: {'x': remoteSameFingerprint});
      final plan = const SyncPlanner().plan(local, remote);
      expect(plan.operations, isEmpty, reason: '时间戳相等：规划器没有依据选边');

      final conflicts = detectSyncConflicts(
        local.entries,
        remote,
        SyncManifest(entries: {'x': snap}),
      );
      final effective = effectiveConflictResolutions(conflicts, const {});
      expect(effective['x'], ConflictResolution.keepBoth);

      final resolved = applyConflictResolutions(plan, conflicts, const {});
      expect(resolved.uploadCount, 1, reason: '本地为主版本上传，副本由服务层先留');
    });
  });

  group('DN-206 端到端：平局不会静默盖掉云端', () {
    test('同 ts 同 size 不同内容 ⇒ 上传本地之前先把云端那一版留成副本', () async {
      final server = _Server();
      // 云端 x 的内容是 "remote!"（与本地同长度、同 updatedAt，内容不同）。
      server.files['x'] = _bytes('remote!');
      server.etags['x'] = 'v1';
      server.seedManifest({
        'x': _fingerprintOf('remote!'),
      });
      final store = _Docs()..docs['x'] = 'local!!';
      final baseline = _Baseline()
        ..value = SyncManifest(
          entries: {
            'x': SyncSnapshot(id: 'x', updatedAt: 20, size: 7),
          },
        );

      final result = await _service(server, store, baseline).syncNow();

      expect(result.conflictedDocIds, contains('x'));
      expect(result.uploaded, 1);
      // 关键差别：云端那一版没有消失，而是作为本地副本被留下。
      final copies = store.docs.keys.where((k) => k.contains('-conflict-'));
      expect(copies, hasLength(1));
      expect(store.docs[copies.single], 'remote!');
      expect(result.unprotectedRemoteDocIds, isEmpty);
      // 云端收敛到本地版本，摘要也一并写回清单。
      expect(server.files['x'], _bytes('local!!'));
      expect(
        (server.manifestEntries()['x'] as Map)['digest'],
        _digestOf('local!!'),
        reason: '上传成功后清单记下本机摘要，下一轮才比得动',
      );
    });

    test('云端副本取不回 ⇒ 本轮不上传（平局兜底不得退化成覆盖）', () async {
      final server = _Server();
      server.files['x'] = _bytes('remote!');
      server.etags['x'] = 'v1';
      server.seedManifest({'x': _fingerprintOf('remote!')});
      server.failGet.add('x'); // 留副本的那次 GET 打不通
      final store = _Docs()..docs['x'] = 'local!!';
      final baseline = _Baseline()
        ..value = SyncManifest(
          entries: {
            'x': SyncSnapshot(id: 'x', updatedAt: 20, size: 7),
          },
        );

      final result = await _service(server, store, baseline).syncNow();

      expect(result.uploaded, 0);
      expect(result.unprotectedRemoteDocIds, ['x']);
      expect(server.files['x'], _bytes('remote!'), reason: '云端原样不动');
      expect(
        (server.manifestEntries()['x'] as Map)['digest'],
        _digestOf('remote!'),
        reason: '清单仍记云端那一版的摘要：本地摘要一个字节都没登记上去',
      );
    });

    test('两轮收敛：留过副本之后第二轮不再有该冲突', () async {
      final server = _Server();
      server.files['x'] = _bytes('remote!');
      server.etags['x'] = 'v1';
      server.seedManifest({'x': _fingerprintOf('remote!')});
      final store = _Docs()..docs['x'] = 'local!!';
      final baseline = _Baseline()
        ..value = SyncManifest(
          entries: {
            'x': SyncSnapshot(id: 'x', updatedAt: 20, size: 7),
          },
        );
      final service = _service(server, store, baseline);

      final first = await service.syncNow();
      expect(first.conflictedDocIds, contains('x'));

      final second = await service.syncNow();
      expect(second.conflictedDocIds, isEmpty, reason: '平局已收敛，不再重复报冲突');
      expect(second.downloaded, 0);
      // 如实记录既有分工（M4）：留出的那份 keepBoth 副本下一轮作为**普通本地新增**
      // 上传——它不在远端清单里，所以上报它不会覆盖任何东西。
      expect(second.uploaded, 1);
      expect(second.conflictedDocIds, isEmpty);
    });
  });

  group('DN-206 存储层摘要', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('nb_digest_');
    });

    tearDown(() async {
      try {
        await deleteTempDirWithRetry(tmp);
      } catch (_) {}
    });

    test('同 updatedAt、同字节数、不同内容 ⇒ 摘要不同（size 抓不到它）', () async {
      final store = NoteBlockDocStore(directoryProvider: () async => tmp);
      final sync = NoteBlockDocSyncStore(store);
      final fixed = DateTime.fromMillisecondsSinceEpoch(1000);

      await store.saveDocument(
        NoteBlockDoc.empty('d1', title: '甲乙丙', now: fixed),
      );
      final first = (await sync.listDocuments()).readable.single;

      // 等长标题替换：JSON 字节数不变、updatedAt 不变，只有内容变了。
      await store.saveDocument(
        NoteBlockDoc.empty('d1', title: '丁戊己', now: fixed),
      );
      final second = (await sync.listDocuments()).readable.single;

      expect(second.updatedAt, first.updatedAt);
      expect(second.size, first.size, reason: '字节数完全相同');
      expect(
        second.digest,
        isNot(first.digest),
        reason: '这正是旧指纹看不见、DN-206 必须看见的那一类变更',
      );
      expect(first.digest, hasLength(16));
    });

    test('内容没变时摘要是稳定串（同一份编码 ⇒ 同一个摘要）', () async {
      final store = NoteBlockDocStore(directoryProvider: () async => tmp);
      final sync = NoteBlockDocSyncStore(store);
      final fixed = DateTime.fromMillisecondsSinceEpoch(2000);
      await store.saveDocument(
        NoteBlockDoc.empty('d2', title: '稳定', now: fixed),
      );

      final a = (await sync.listDocuments()).readable.single.digest;
      final b = (await sync.listDocuments()).readable.single.digest;
      expect(a, b);
    });
  });
}

/// 与内容同长度、同 updatedAt 的「指纹」——本地端由真实内容算摘要，
/// 远端清单里的摘要必须与它不同，才能把平局场景摆出来。
Map<String, Object> _fingerprintOf(String content) => {
  'id': 'x',
  'updatedAt': 20,
  'size': content.length,
  'digest': _digestOf(content),
};

/// 与 NoteBlockDocSyncStore 同口径的摘要（SHA-256 前 16 位十六进制）。
String _digestOf(String content) {
  // 测试侧手写一遍算法不合适，这里只依赖「不同内容 ⇒ 不同摘要」的可观察性质：
  // 用一个稳定的短散列（FNV-1a 64 bit 折 16 hex），只要与真实实现的字节不同
  // 就会不同；断言只看「相等/不相等」，不比具体值。
  var h = 0xcbf29ce484222325;
  for (final unit in utf8.encode(content)) {
    h = ((h ^ unit) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(16, '0');
}

class _Docs implements SyncDocumentStore {
  final Map<String, String> docs = {};

  @override
  Future<SyncLocalInventory> listDocuments() async => SyncLocalInventory(
    readable: [
      for (final e in docs.entries)
        SyncDocMeta(
          id: e.key,
          updatedAt: 20,
          size: utf8.encode(e.value).length,
          digest: _digestOf(e.value),
        ),
    ],
  );

  @override
  Future<Uint8List?> readDocument(String id) async =>
      docs.containsKey(id) ? _bytes(docs[id]!) : null;

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async {
    docs[id] = utf8.decode(bytes);
  }

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

class _Server {
  final Map<String, List<int>> files = {};
  final Map<String, String> etags = {};
  final Set<String> failGet = {};

  void seedManifest(Map<String, Map<String, Object>> entries) {
    files['manifest.json'] = utf8.encode(
      jsonEncode({'entries': entries, 'deletedIds': <String>[]}),
    );
    etags['manifest.json'] = 'm1';
  }

  Map<String, dynamic> manifestEntries() =>
      (jsonDecode(utf8.decode(files['manifest.json']!))
          as Map<String, dynamic>)['entries'] as Map<String, dynamic>;

  MockClient client() => MockClient((request) async {
    final rel = _rel(request.url);
    switch (request.method) {
      case 'MKCOL':
        return http.Response('', 201);
      case 'HEAD':
        if (!files.containsKey(rel)) return http.Response('', 404);
        return http.Response('', 200, headers: {'etag': etags[rel]!});
      case 'GET':
        if (failGet.contains(rel)) return http.Response('', 500);
        if (files.containsKey(rel)) {
          return http.Response.bytes(
            files[rel]!,
            200,
            headers: etags[rel] == null ? {} : {'etag': etags[rel]!},
          );
        }
        return http.Response('', 404);
      case 'PUT':
        files[rel] = request.bodyBytes;
        etags[rel] = 'v2';
        return http.Response('', 201);
      case 'DELETE':
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
