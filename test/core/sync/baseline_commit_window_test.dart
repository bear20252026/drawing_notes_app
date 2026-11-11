// H2（第三轮专家审计）：两阶段提交窗口的收敛性必须被钉住。
//
// 窗口形状：`syncNow()` 先回写远端 manifest（条件写，DN-104），**再**回写本地
// 基线。两次写之间崩溃 ⇒ 两端 manifest 已经领先本地基线。这个窗口是**有意
// 保留**的（注释在 sync_service.dart 的 `baselineStore.save` 上方：不引入
// WAL/journal，因为收敛代价只是一次幂等重传），但「收敛」这个结论此前没有任何
// 用例钉死——它只存在于一段注释里。
//
// 本文件用 `SyncService.baselineCommitBarrierForTest` 把窗口放大成确定性用例：
// 在远端 manifest 已 PUT、基线尚未 save 的那一刻抛异常，然后**换一个新服务
// 实例**（模拟重启：内存 store 是同一份，进程是新进程）跑第二轮，断言：
//  ① 文档没有丢（本地字节仍在，云端条目仍在）；
//  ② 删除方向没被误判（墓碑不因为基线落后而被抹掉，也不凭空产生）；
//  ③ 收敛后基线追上 manifest（第二轮的远端清单不再有新的删除/新增动作）。
//
// 这是「崩溃恢复」的测试，不是「写入顺序」的测试：顺序本身（远端先、本地后）
// 是既有设计，本文件只证明它的后果可控。
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

SyncSnapshot _snap(String id, int updatedAt) => SyncSnapshot(
      id: id,
      updatedAt: updatedAt,
      size: _docBytes(updatedAt).length,
    );

/// 只支持 GET / PUT(If-Match) / DELETE / HEAD=405 的最小清单桩。
class _Dav {
  final Map<String, List<int>> files = {};
  final Map<String, String> etags = {};
  final List<(String, String, String?)> requests = [];

  void seedManifest(SyncManifest manifest, {String etag = 'm1'}) {
    files['manifest.json'] = utf8.encode(jsonEncode(manifest.toJson()));
    etags['manifest.json'] = etag;
  }

  SyncManifest remoteManifest() => SyncManifest.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(utf8.decode(files['manifest.json']!)) as Map,
        ),
      );

  /// 远端清单被 PUT 过的次数（本文件的收敛判据之一）。
  int get manifestPuts =>
      requests.where((r) => r.$1 == 'PUT' && r.$2 == 'manifest.json').length;

  /// 远端被 DELETE 过的文档路径（用于「删除方向没被误判」）。
  List<String> get deletedDocPaths =>
      [for (final r in requests) if (r.$1 == 'DELETE') r.$2];

  MockClient client() => MockClient((request) async {
        final rel = _rel(request.url);
        final ifMatch = request.headers['if-match'];
        requests.add((request.method, rel, ifMatch));
        switch (request.method) {
          case 'MKCOL':
            return http.Response('', 201);
          case 'HEAD':
            return http.Response('', 405);
          case 'GET':
            if (!files.containsKey(rel)) return http.Response('', 404);
            return http.Response.bytes(
              files[rel]!,
              200,
              headers: {'etag': etags[rel] ?? 'g-$rel'},
            );
          case 'PUT':
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

/// 同一个实例被两轮共用：模拟「崩溃后重启」——数据在同一份 store 里，
/// 服务实例是新的（真实的进程重启不会复用任何内存对象）。
class _Baseline implements SyncBaselineStore {
  _Baseline([SyncManifest? initial]) : value = initial;

  SyncManifest? value;
  int saveCount = 0;

  @override
  Future<SyncManifest?> load() async => value;

  @override
  Future<void> save(SyncManifest manifest) async {
    saveCount++;
    value = manifest;
  }
}

SyncService _service(
  _Dav dav,
  _Docs docs,
  _Baseline baseline, {
  Future<void> Function()? barrier,
}) =>
    SyncService(
      transport: WebDavSyncClient(baseUrl: Uri.parse(_base), client: dav.client()),
      documentStore: docs,
      baselineStore: baseline,
      cipher: const NoopSyncCipher(),
      conflictHandler: const LwwConflictHandler(),
      baselineGate: const AlwaysTrustedBaselineGate(),
      baselineCommitBarrierForTest: barrier,
    );

void main() {
  group('H2 两阶段提交窗口：远端已回写、基线未回写时崩溃', () {
    test('窗口内崩溃 ⇒ 下一轮收敛：文档不丢、删除方向不误判、基线追上', () async {
      // 场景：a 是既有文档（两端都已知），b 是本地新增待上传。
      final docs = _Docs({'a': 200, 'b': 300});
      final dav = _Dav()..seedManifest(SyncManifest(entries: {'a': _snap('a', 200)}));
      final baseline = _Baseline(SyncManifest(entries: {'a': _snap('a', 200)}));

      // —— 第一轮：在远端 manifest 已 PUT、基线未 save 处崩溃 ——
      var barrierCalls = 0;
      // 崩溃等价类：进程被杀 / 磁盘写失败。远端清单此刻已经落地。
      // 异常必须被这条用例接住——同步器不吞它（有意：失败要如实上报）。
      StateError? crash;
      try {
        await _service(
          dav,
          docs,
          baseline,
          barrier: () async {
            barrierCalls++;
            throw StateError('崩溃在提交窗口');
          },
        ).syncNow();
      } on StateError catch (e) {
        crash = e;
      }

      expect(barrierCalls, 1, reason: '钩子没被调到 = 这条用例什么都没验');
      expect(crash, isNotNull, reason: '同步器必须把崩溃如实抛给调用方，不得静默');

      // 窗口的**因**：远端 manifest 已经领先本地基线。
      final remoteAfterCrash = dav.remoteManifest();
      expect(
        remoteAfterCrash.entries.keys,
        contains('b'),
        reason: '远端清单已回写——这正是窗口存在的前提',
      );
      expect(
        baseline.value!.entries.keys,
        isNot(contains('b')),
        reason: '本地基线未回写——两端 manifest 领先基线，即本用例的输入形态',
      );

      // —— 第二轮：新进程、同一份 store，正常跑完 ——
      final second = await _service(dav, docs, baseline).syncNow();

      // ① 文档不丢。
      expect(docs.updatedAtById.keys, containsAll(['a', 'b']));
      expect(dav.remoteManifest().entries.keys, containsAll(['a', 'b']));
      expect(second.failedDocIds, isEmpty, reason: '没有任何文档进入失败集');
      expect(
        second.deletedRemote,
        0,
        reason: '基线落后绝不等于「用户删除了什么」——不许凭空产生远端删除',
      );
      expect(dav.deletedDocPaths, isEmpty);

      // ② 收敛：基线追上远端，且不再需要任何后续写。
      expect(baseline.value!.entries.keys, containsAll(['a', 'b']));
      expect(baseline.saveCount, 1, reason: '只有第二轮真的写了基线');

      // ③ 幂等性：基线已经追上远端，本地内容也不再变化 ⇒ 第三轮没有任何
      // 上传/下载/删除动作，远端条目也保持原样。
      // 判据刻意按**内容**而不是按「有没有 PUT」——同步器每轮都会把读到的清单
      // 幂等写回一次，那是既有设计；真正衡量收敛的是不再有数据动作。
      final third = await _service(dav, docs, baseline).syncNow();
      expect(third.uploaded, 0);
      expect(third.downloaded, 0);
      expect(third.deletedRemote, 0);
      expect(third.failedDocIds, isEmpty);
      expect(
        dav.remoteManifest().entries.keys,
        remoteAfterCrash.entries.keys,
        reason: '已经收敛的轮次不该再改动远端条目——两端在第二轮就已对齐',
      );
    });

    test('反向锁：钩子为 null 时行为逐字节不变（生产不挂钩子）', () async {
      final docs = _Docs({'a': 200, 'b': 300});
      final dav = _Dav()..seedManifest(SyncManifest(entries: {'a': _snap('a', 200)}));
      final baseline = _Baseline(SyncManifest(entries: {'a': _snap('a', 200)}));

      final result = await _service(dav, docs, baseline).syncNow();

      expect(result.uploaded, 1);
      expect(baseline.value!.entries.keys, containsAll(['a', 'b']));
      expect(dav.remoteManifest().entries.keys, containsAll(['a', 'b']));
    });

    test('窗口内崩溃 + 本地删除：墓碑不因基线落后而被抹掉', () async {
      // 更危险的一支：本机删掉了 b，崩溃发生在「云端已写下带因果的墓碑、
      // 基线未推进」。下一轮基线仍然声称「b 在本机是好的那一版」——这正是
      // 窗口的形状：**本机删除意图已生效，而基线还不知道**。
      //
      // 必须证明的是：下一轮不会把远端已删这件事误读成「本机独有 ⇒ 上传复活」，
      // 墓碑也不会被抹掉。
      final docs = _Docs({'a': 200});
      final dav = _Dav()
        ..seedManifest(
          SyncManifest(
            entries: {'a': _snap('a', 200), 'b': _snap('b', 200)},
          ),
        );
      dav.files['b'] = _docBytes(200);
      final baseline = _Baseline(
        SyncManifest(entries: {'a': _snap('a', 200), 'b': _snap('b', 200)}),
      );

      // 第一轮：本机把 b 删掉（远端同步删掉它），然后在提交窗口崩溃。
      var barrierCalls = 0;
      StateError? crash;
      try {
        await _service(
          dav,
          docs,
          baseline,
          barrier: () async {
            barrierCalls++;
            throw StateError('崩溃在提交窗口');
          },
        ).syncNow();
      } on StateError catch (e) {
        crash = e;
      }
      expect(barrierCalls, 1, reason: '钩子没被调到 = 这条用例什么都没验');
      expect(crash, isNotNull, reason: '同步器必须把崩溃如实抛给调用方，不得静默');

      final remoteAfterCrash = dav.remoteManifest();
      // 窗口的**因**：远端已写下带因果的墓碑（baseRev = 删除作用在哪一版上），
      // 而本地基线还留着 b 的好版本。
      expect(remoteAfterCrash.entries.containsKey('b'), isFalse);
      expect(remoteAfterCrash.deletedIds, contains('b'));
      expect(
        remoteAfterCrash.tombstones['b'],
        isNotNull,
        reason: '墓碑带因果信息（A3），不能退化成裸 id',
      );
      expect(
        baseline.value!.entries.keys,
        contains('b'),
        reason: '基线仍认为 b 在本机——两端 manifest 领先基线，即本用例的输入形态',
      );

      // 第二轮：新进程。判据是「远端清单里 b 已被删除」⇒ 本机的 b 必须消失，
      // 而不是被推回云端。
      final second = await _service(dav, docs, baseline).syncNow();

      expect(
        second.deletedRemote,
        0,
        reason: '删除已经落地，不需要再删一次',
      );
      expect(
        dav.remoteManifest().deletedIds,
        contains('b'),
        reason: 'b 的墓碑必须继续带着走（基线落后不是抹掉它的理由）',
      );
      expect(
        dav.remoteManifest().tombstones['b'],
        isNotNull,
        reason: '墓碑既不能被抹掉，也不能退化成没有因果的裸记录',
      );
      expect(
        dav.remoteManifest().entries.containsKey('b'),
        isFalse,
        reason: '远端删掉的那一篇不该在本机复活（否则就是本用例要抓的误判）',
      );
      expect(
        docs.updatedAtById.containsKey('b'),
        isFalse,
        reason: '本机本就没有 b 的字节，崩溃后更不该凭空长回来',
      );
      expect(
        dav.deletedDocPaths.where((p) => p == 'b').length,
        1,
        reason: '只有一次真删除，来自第一轮（崩溃的那次已真删掉了云端对象）',
      );
      expect(
        baseline.value!.entries.keys,
        isNot(contains('b')),
        reason: '收敛后基线不再声称 b 在本机——删除被记住，而不是被忘掉',
      );
    });
  });
}
