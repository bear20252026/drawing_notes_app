// A3（第三轮协同方案 §9）：删除墓碑带因果，且 manifest.json 前后向兼容。
//
// 修的是「远端清单里某条目消失了」这一件事**不可区分**的问题：有人删了它，
// 还是清单被并发覆盖写丢了这一条（DN-104 的孤儿文件场景）？旧形状下答案只有
// 后者能被发现——手持该文档的设备一律按「本地独有 ⇒ 上传」处理，于是删除被
// 另一端复活，删除方下一轮再删 ⇒ 乒乓。本批只让**信息存在**（写出墓碑 + 读回
// 墓碑 + 保留对方的墓碑），不改任何同步方向：读 baseRev 的那条腿＝「按删除把
// 本地那份也去掉」，那会移除用户内容，须单独确认后再做。
//
// 兼容性是这里的主约束，所以两组断言分开门钉：
//  ① 新清单在旧客户端眼里形状不变（`entries` + `deletedIds` 原样，未知键忽略）；
//  ② 旧清单在新客户端眼里按「无因果」处理，绝不因为缺键就把删除当成异常。
@Timeout(Duration(minutes: 3))
library;

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

Uint8List _docBytes(int updatedAt) =>
    Uint8List.fromList(utf8.encode(jsonEncode({'updatedAt': updatedAt})));

SyncSnapshot _snap(String id, int updatedAt) =>
    SyncSnapshot(id: id, updatedAt: updatedAt, size: _docBytes(updatedAt).length);

/// 只支持 GET / PUT(If-Match) / DELETE / HEAD=405 的最小清单桩。
///
/// 文档正文一律走「服务器不响应 HEAD」那条退路（无条件写），把本文件的断言
/// 面收窄到墓碑上——条件写入本身已由 doc_conditional_write_test 钉住。
class _Dav {
  final Map<String, List<int>> files = {};
  final Map<String, String> etags = {};
  final List<(String, String, String?)> requests = [];

  /// 下一次 PUT manifest.json 之前，别的设备抢先改写清单（触发 412 重试）。
  List<int>? hijackManifestWith;

  void seedManifest(SyncManifest manifest, {String etag = 'm1'}) {
    files['manifest.json'] = utf8.encode(jsonEncode(manifest.toJson()));
    etags['manifest.json'] = etag;
  }

  SyncManifest remoteManifest() =>
      SyncManifest.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(utf8.decode(files['manifest.json']!)) as Map,
        ),
      );

  Map<String, dynamic> rawRemoteManifest() =>
      Map<String, dynamic>.from(
        jsonDecode(utf8.decode(files['manifest.json']!)) as Map,
      );

  MockClient client() => MockClient((request) async {
    final rel = _rel(request.url);
    final ifMatch = request.headers['if-match'];
    requests.add((request.method, rel, ifMatch));
    switch (request.method) {
      case 'MKCOL':
        return http.Response('', 201);
      case 'HEAD':
        return http.Response('', 405); // 文档写走无条件退路
      case 'GET':
        if (!files.containsKey(rel)) return http.Response('', 404);
        return http.Response.bytes(
          files[rel]!,
          200,
          headers: {'etag': etags[rel] ?? 'g-$rel'},
        );
      case 'PUT':
        if (rel == 'manifest.json' && hijackManifestWith != null) {
          final hijacked = hijackManifestWith!;
          hijackManifestWith = null;
          files[rel] = hijacked;
          etags[rel] = 'm-other';
        }
        if (ifMatch != null && etags[rel] != ifMatch) {
          return http.Response('', 412);
        }
        files[rel] = request.bodyBytes;
        etags[rel] = 'm${etags[rel] == null ? 1 : 9}';
        return http.Response('', 201);
      case 'DELETE':
        files.remove(rel);
        etags.remove(rel);
        return http.Response('', 204);
      default:
        return http.Response('', 405);
    }
  });

  static String _rel(Uri url) {
    const prefix = '/sync/';
    return url.path.startsWith(prefix) ? url.path.substring(prefix.length) : '';
  }
}

class _Docs implements SyncDocumentStore {
  _Docs(Map<String, int> initial) {
    updatedAtById.addAll(initial);
  }

  final Map<String, int> updatedAtById = {};

  @override
  Future<SyncLocalInventory> listDocuments() async => SyncLocalInventory(
    readable: [
      for (final e in updatedAtById.entries)
        SyncDocMeta(id: e.key, updatedAt: e.value, size: _docBytes(e.value).length),
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
  _Baseline(this.value);
  SyncManifest? value;
  @override
  Future<SyncManifest?> load() async => value;
  @override
  Future<void> save(SyncManifest manifest) async => value = manifest;
}

SyncService _service(_Dav dav, _Docs docs, _Baseline baseline) => SyncService(
  transport: WebDavSyncClient(baseUrl: Uri.parse(_base), client: dav.client()),
  documentStore: docs,
  baselineStore: baseline,
  cipher: const NoopSyncCipher(),
  conflictHandler: const LwwConflictHandler(),
  baselineGate: const AlwaysTrustedBaselineGate(),
);

void main() {
  group('A3 值模型：墓碑带因果', () {
    test('往返保真：deletedAt / baseRev 逐字段回来', () {
      final manifest = SyncManifest(
        entries: const {},
        deletedIds: const {'gone'},
        tombstones: const {
          'gone': SyncTombstone(id: 'gone', deletedAt: 1700, baseRev: 900),
        },
      );
      final decoded = SyncManifest.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(manifest.toJson())) as Map),
      );

      expect(decoded.deletedIds, {'gone'});
      expect(decoded.tombstones['gone']!.deletedAt, 1700);
      expect(decoded.tombstones['gone']!.baseRev, 900);
      expect(
        decoded.tombstones['gone'],
        const SyncTombstone(id: 'gone', deletedAt: 1700, baseRev: 900),
      );
    });

    test('旧清单（没有 tombstones 键）⇒ 按无因果处理，不是异常', () {
      final decoded = SyncManifest.fromJson({
        'entries': {
          'a': {'id': 'a', 'updatedAt': 100, 'size': 20},
        },
        'deletedIds': ['b', 'c'],
      });

      expect(decoded.deletedIds, {'b', 'c'});
      expect(decoded.tombstones, isEmpty);
      // 无因果 ⇒ 判据只能用「不可比」的那一支，绝不能拿 0 当时间戳参与比较。
      expect(SyncTombstone(id: 'b').hasCausality, isFalse);
      expect(SyncTombstone(id: 'b').retentionKey, 0);
    });

    test('写出面：只有带因果的墓碑才落进 JSON，不撑大清单', () {
      final json = SyncManifest(
        deletedIds: const {'plain', 'caused'},
        tombstones: const {
          'plain': SyncTombstone(id: 'plain'),
          'caused': SyncTombstone(id: 'caused', deletedAt: 5, baseRev: 4),
        },
      ).toJson();

      expect(json['deletedIds'], hasLength(2), reason: '列表仍是全集');
      final tombstones = json['tombstones'] as Map;
      expect(tombstones.keys, ['caused'], reason: '空信息不重复一遍');
      expect(json.containsKey('entries'), isTrue, reason: 'entries 键不得消失');
    });

    test('单一裁决源：tombstones 里未被 deletedIds 承认的 id 不写出', () {
      final json = SyncManifest(
        deletedIds: const {'real'},
        tombstones: const {
          'real': SyncTombstone(id: 'real', deletedAt: 1),
          'ghost': SyncTombstone(id: 'ghost', deletedAt: 2),
        },
      ).toJson();

      expect((json['tombstones'] as Map).keys, ['real']);
      expect(json['deletedIds'], ['real']);
    });

    test('读入面：只写 tombstones 不写 deletedIds 的畸形清单也算「已删」', () {
      // 少了这一条，planner 看不见删除，对端会按「本地独有 ⇒ 上传」复活它。
      final decoded = SyncManifest.fromJson({
        'entries': <String, dynamic>{},
        'tombstones': {
          'x': {'id': 'x', 'deletedAt': 7},
        },
      });

      expect(decoded.deletedIds, {'x'});
      expect(decoded.tombstones['x']!.deletedAt, 7);
    });

    test('畸形墓碑 ⇒ 整轮中止（残缺的删除记录会被读成「没被删」）', () {
      expect(
        () => SyncManifest.fromJson({
          'entries': <String, dynamic>{},
          'tombstones': {
            'x': {'id': 'x', 'deletedAt': '昨天'},
          },
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SyncManifest.fromJson({
          'entries': <String, dynamic>{},
          'tombstones': 'x',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SyncManifest.fromJson({
          'entries': <String, dynamic>{},
          'tombstones': {'x': <String, dynamic>{'baseRev': 1.5}},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('留存裁剪：超上限保最新，缺时间戳先淘汰，同戳按 id 字典序', () {
      final all = <SyncTombstone>[
        const SyncTombstone(id: 'no_stamp', deletedAt: null, baseRev: 1),
        const SyncTombstone(id: 'old', deletedAt: 10),
        const SyncTombstone(id: 'tie_b', deletedAt: 20),
        const SyncTombstone(id: 'tie_a', deletedAt: 20),
        const SyncTombstone(id: 'new', deletedAt: 30),
      ];

      final kept = SyncManifest.pruneTombstones(all, limit: 3);
      expect(kept.keys, ['tie_a', 'tie_b', 'new']);

      // 裁剪必须幂等：清单要参与 ETag 条件写，同输入两次结果不一致会被误判成
      // 「远端又变了」。
      expect(
        SyncManifest.pruneTombstones(kept.values, limit: 3).keys,
        kept.keys,
      );
      expect(SyncManifest.pruneTombstones(all, limit: 99).length, all.length);
    });
  });

  group('A3 服务面：墓碑跟着清单走', () {
    test('本地删除一篇 ⇒ 云端清单留下带因果的墓碑，删除同时不再被抹掉', () async {
      // 基线：a、b 都在 200 那一版同步过。本地把 b 删了；云端还留着 b。
      final docs = _Docs({'a': 200});
      final dav = _Dav()
        ..seedManifest(
          SyncManifest(entries: {'a': _snap('a', 200), 'b': _snap('b', 200)}),
        );
      dav.files['b'] = _docBytes(200);
      final baseline = _Baseline(
        SyncManifest(entries: {'a': _snap('a', 200), 'b': _snap('b', 200)}),
      );

      final result = await _service(dav, docs, baseline).syncNow();

      expect(result.deletedRemote, 1);
      final written = dav.remoteManifest();
      expect(written.entries.containsKey('b'), isFalse);
      expect(written.deletedIds, {'b'}, reason: '旧客户端只读这一项，也得看见删除');
      // 因果锚 = 删除作用在哪一版之上（基线里那一条的 updatedAt）。
      expect(written.tombstones['b']!.baseRev, 200);
      expect(written.tombstones['b']!.deletedAt, isNotNull);
      expect(
        dav.rawRemoteManifest()['entries'].keys,
        contains('a'),
        reason: '墓碑不能把无关条目一起带下去',
      );
    });

    test('别人写进清单的墓碑必须原样保留，不被本轮全量重写清空', () async {
      // 这正是旧实现的洞：`SyncManifest(entries: newEntries)` 一次写就把对方的
      // 删除历史抹平，下一轮另一端手里的副本又变成「仅本地 ⇒ 上传」。
      final docs = _Docs({'a': 300});
      final dav = _Dav()
        ..seedManifest(
          SyncManifest(
            entries: {'a': _snap('a', 200)},
            deletedIds: const {'other_deleted'},
            tombstones: const {
              'other_deleted': SyncTombstone(id: 'other_deleted', deletedAt: 50, baseRev: 40),
            },
          ),
        );
      final baseline = _Baseline(SyncManifest(entries: {'a': _snap('a', 200)}));

      final result = await _service(dav, docs, baseline).syncNow();

      expect(result.uploaded, 1);
      final written = dav.remoteManifest();
      expect(
        written.tombstones['other_deleted'],
        const SyncTombstone(id: 'other_deleted', deletedAt: 50, baseRev: 40),
        reason: '我们这轮没碰它，就该由清单继续保管',
      );
      expect(written.deletedIds, contains('other_deleted'));
    });

    test('本轮真上传成功 ⇒ 那一条删除记录被一次有据的否决移除', () async {
      // 现状口径（A3-1 不改方向，只让历史可见）：本地还留着文档并上传，就是
      // 明确主张「这一版仍在用」。要变成「不复活」，得有下一条腿（本地删除通道）。
      final docs = _Docs({'res': 300});
      final dav = _Dav()
        ..seedManifest(
          SyncManifest(
            entries: const {},
            deletedIds: const {'res'},
            tombstones: const {
              'res': SyncTombstone(id: 'res', deletedAt: 50, baseRev: 40),
            },
          ),
        );
      final baseline = _Baseline(const SyncManifest());

      final result = await _service(dav, docs, baseline).syncNow();

      expect(result.uploaded, 1);
      final written = dav.remoteManifest();
      expect(written.deletedIds, isEmpty);
      expect(written.tombstones, isEmpty, reason: '被否决的删除不能一直赖在清单里');
      expect(written.entries['res']!.updatedAt, 300);
    });

    test('412 重试合并时，对方这轮新写的墓碑同样不能被丢', () async {
      final docs = _Docs({'a': 300});
      final concurrent = SyncManifest(
        entries: {'b': _snap('b', 250)},
        deletedIds: const {'theirs'},
        tombstones: const {
          'theirs': SyncTombstone(id: 'theirs', deletedAt: 60, baseRev: 55),
        },
      );
      final dav = _Dav()
        ..seedManifest(SyncManifest(entries: {'a': _snap('a', 200)}));
      dav.hijackManifestWith = utf8.encode(jsonEncode(concurrent.toJson()));
      final baseline = _Baseline(SyncManifest(entries: {'a': _snap('a', 200)}));

      final result = await _service(dav, docs, baseline).syncNow();

      expect(result.uploaded, 1);
      final manifestPuts = dav.requests
          .where((r) => r.$1 == 'PUT' && r.$2 == 'manifest.json')
          .toList();
      expect(
        manifestPuts.length,
        greaterThanOrEqualTo(2),
        reason: '桩必须真的制造过一次 412，否则本条什么都没验',
      );

      final written = dav.remoteManifest();
      expect(
        written.tombstones['theirs'],
        const SyncTombstone(id: 'theirs', deletedAt: 60, baseRev: 55),
      );
      expect(
        written.entries['b']!.updatedAt,
        250,
        reason: '对方新增的条目也要留住（DN-104 原口径）',
      );
    });

    test('反向锁：无删除发生 ⇒ 写出的清单里根本不出现 tombstones 键', () async {
      // 兼容性的硬要求：混合版本集群里，没有删除时新客户端写出的 JSON 形状
      // 必须与旧版本逐键一致，别让一次普通同步就把共享清单改成旧版读不懂的样子。
      final docs = _Docs({'a': 300});
      final dav = _Dav()..seedManifest(SyncManifest(entries: {'a': _snap('a', 200)}));
      final baseline = _Baseline(SyncManifest(entries: {'a': _snap('a', 200)}));

      await _service(dav, docs, baseline).syncNow();

      final raw = dav.rawRemoteManifest();
      expect(raw.containsKey('tombstones'), isFalse);
      expect(raw['deletedIds'], isEmpty);
      expect((raw['entries'] as Map).keys, ['a']);
    });
  });
}
