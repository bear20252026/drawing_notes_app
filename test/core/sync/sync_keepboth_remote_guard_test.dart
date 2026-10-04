// keepBoth「保住云端副本」回归锁（本批诚实化修复）。
//
// 缺陷形状：SyncService 在上传**之前**取回 keepBoth 的远端副本，旧实现在取回
// 抛错 / 解密失败时静默 `continue`，随后本地版本照常 PUT 到同一个远端路径
// （AesSyncCipher.remotePath 由当前密钥确定性导出 ⇒ 覆盖云端唯一副本），
// 等于以「两者皆保留」的名义静默覆盖远端——违反本子系统硬约束。
//
// 现锁死三条：
// ①副本没能保住 ⇒ 该文档本轮零 PUT，并进 SyncResult.unprotectedRemoteDocIds；
// ②其余文档（健康的 keepBoth、普通新增）不受牵连，照常完成同步；
// ③整轮不抛异常、每轮对同一文档只尝试一次 GET（不做无谓的反复重试）。
// 404（云端根本没有该对象）不会被误判为「没能保住」——上传不会覆盖任何东西。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';

const _base = 'https://dav.example.com/sync/';

/// 云端副本的加密密钥（模拟「清单可读、这条密文用当前密钥解不开」的混合态）。
final _oldKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

/// 本轮同步使用的密钥（manifest 用它密封，远端对象名也由它导出）。
final _curKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 2));

Uint8List _docBytes(int updatedAt) =>
    Uint8List.fromList(utf8.encode(jsonEncode({'updatedAt': updatedAt})));

class _Docs implements SyncDocumentStore {
  final Map<String, _Doc> docs = {};

  void seed(String id, int updatedAt) {
    final bytes = _docBytes(updatedAt);
    docs[id] = _Doc(id, bytes, updatedAt);
  }

  @override
  Future<List<SyncDocMeta>> listDocuments() async => [
    for (final e in docs.entries)
      SyncDocMeta(
        id: e.key,
        updatedAt: e.value.updatedAt,
        size: e.value.bytes.length,
      ),
  ];

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

class _Baseline implements SyncBaselineStore {
  SyncManifest? value;
  @override
  Future<SyncManifest?> load() async => value;
  @override
  Future<void> save(SyncManifest manifest) async => value = manifest;
}

/// 内存 WebDAV：记录 GET/PUT/DELETE 的相对路径，据以断言「没有任何 PUT」。
class _Dav {
  _Dav(this.files);
  final Map<String, List<int>> files;
  final gets = <String>[];
  final puts = <String>[];
  final deletes = <String>[];

  /// 故障注入：GET 这些路径返回 500（模拟取回失败，不是 404）。
  final Set<String> failGet = {};

  static String _rel(Uri url) {
    const prefix = '/sync/';
    final path = url.path;
    return path.startsWith(prefix) ? path.substring(prefix.length) : '';
  }

  MockClient client() => MockClient((request) async {
    final rel = _rel(request.url);
    switch (request.method) {
      case 'MKCOL':
        return http.Response('', 201);
      case 'GET':
        gets.add(rel);
        if (failGet.contains(rel)) return http.Response('', 500);
        final body = files[rel];
        return body == null
            ? http.Response('', 404)
            : http.Response.bytes(body, 200);
      case 'PUT':
        puts.add(rel);
        files[rel] = request.bodyBytes;
        return http.Response('', 201);
      case 'DELETE':
        deletes.add(rel);
        files.remove(rel);
        return http.Response('', 204);
      default:
        return http.Response('', 405);
    }
  });
}

SyncSnapshot _snap(String id, int updatedAt) => SyncSnapshot(
  id: id,
  updatedAt: updatedAt,
  size: _docBytes(updatedAt).length,
);

/// 用 [key] 密封「entries」清单（远端 manifest 必须能被当前密钥打开，
/// 否则整轮在 openManifestJson 就终止了，走不到 keepBoth 分支）。
Future<List<int>> _sealedManifest(
  List<int> key,
  Map<String, int> idToUpdatedAt,
) async {
  final entries = <String, SyncSnapshot>{
    for (final e in idToUpdatedAt.entries) e.key: _snap(e.key, e.value),
  };
  return Uint8List.fromList(
    utf8.encode(
      await AesSyncCipher(
        key: key,
      ).sealManifestJson(jsonEncode(SyncManifest(entries: entries).toJson())),
    ),
  );
}

Future<List<int>> _sealedDoc(List<int> key, String id, int updatedAt) =>
    AesSyncCipher(key: key).encryptDocumentBytes(_docBytes(updatedAt), id);

SyncService _service(
  _Dav dav,
  _Docs docs,
  _Baseline baseline, {
  required SyncCipher cipher,
  required Map<String, ConflictResolution> verdicts,
}) => SyncService(
  transport: WebDavSyncClient(baseUrl: Uri.parse(_base), client: dav.client()),
  documentStore: docs,
  baselineStore: baseline,
  cipher: cipher,
  conflictHandler: _ScriptedHandler(verdicts),
);

class _ScriptedHandler implements ConflictHandler {
  _ScriptedHandler(this.map);
  final Map<String, ConflictResolution> map;
  @override
  Future<Map<String, ConflictResolution>> resolve(
    List<SyncConflict> conflicts,
  ) async => map;
}

/// 场景装配：c（远端副本解不开）+ h（远端副本可读）两个 keepBoth 冲突，
/// 外加一个普通本地新增 n。基线把两端都记成 10 ⇒ 真·双边改动冲突。
Future<({AesSyncCipher cipher, _Dav dav, _Docs docs, _Baseline baseline})>
_fixture({bool remoteCopyPresent = true, bool copyReadable = false}) async {
  final cipher = AesSyncCipher(key: _curKey);
  final cPath = cipher.remotePath('c');
  final files = <String, List<int>>{
    SyncService.manifestPath: await _sealedManifest(_curKey, {
      'c': 40,
      'h': 40,
    }),
    cipher.remotePath('h'): await _sealedDoc(_curKey, 'h', 40),
  };
  if (remoteCopyPresent) {
    files[cPath] = copyReadable
        ? await _sealedDoc(_curKey, 'c', 40)
        : await _sealedDoc(_oldKey, 'c', 40);
  }
  final docs = _Docs()
    ..seed('c', 25)
    ..seed('h', 25)
    ..seed('n', 15);
  final baseline = _Baseline()
    ..value = SyncManifest(entries: {'c': _snap('c', 10), 'h': _snap('h', 10)});
  return (cipher: cipher, dav: _Dav(files), docs: docs, baseline: baseline);
}

void main() {
  group('keepBoth：云端副本没能保住 ⇒ 跳过上传且不覆盖', () {
    test('解密失败：该文档零 PUT、进 unprotectedRemoteDocIds、云端密文原样', () async {
      final fx = await _fixture();
      final cPath = fx.cipher.remotePath('c');
      final before = List<int>.from(fx.dav.files[cPath]!);

      final r = await _service(
        fx.dav,
        fx.docs,
        fx.baseline,
        cipher: fx.cipher,
        verdicts: const {
          'c': ConflictResolution.keepBoth,
          'h': ConflictResolution.keepBoth,
        },
      ).syncNow();

      // ① 没能保住的云端副本单列上报（与 unreadableDocIds 语义不同：那是执行
      // 期失败，这是为保护远端主动跳过）。
      expect(r.unprotectedRemoteDocIds, ['c']);
      expect(r.unreadableDocIds, isEmpty);
      expect(r.conflictedDocIds, containsAll(<String>['c', 'h']));
      // 关键：本轮没有任何 PUT 落在 c 的远端路径上（旧实现会盖掉它）。
      expect(
        fx.dav.puts.where((p) => p == cPath),
        isEmpty,
        reason: '解不开云端副本时绝不 PUT 覆盖',
      );
      expect(fx.dav.files[cPath], before, reason: '云端唯一副本字节不变');
      expect(fx.dav.deletes, isEmpty, reason: '也不许删远端');
      // 没有本地副本被写出来（keepBoth 未兑现）。
      expect(
        fx.docs.docs.keys.where((k) => k.startsWith('c-conflict-')),
        isEmpty,
      );
      expect(r.uploaded, 2, reason: 'h（keepBoth）+ n（新增）照常上传');
    });

    test('基线不把「没同步的 c」谎记成已同步：退回本轮开始时的值', () async {
      final fx = await _fixture();
      await _service(
        fx.dav,
        fx.docs,
        fx.baseline,
        cipher: fx.cipher,
        verdicts: const {'c': ConflictResolution.keepBoth},
      ).syncNow();

      // 远端清单保留 c@40（文件真实存在），基线必须是本轮开始前的 10——
      // 否则下轮冲突判据退化成「远端没改过却比本地新」，兜底方向又变回上传。
      expect(fx.baseline.value!.entries['c']!.updatedAt, 10);
      final opened = jsonDecode(
        await fx.cipher.openManifestJson(
          utf8.decode(fx.dav.files[SyncService.manifestPath]!),
        ),
      ) as Map<String, dynamic>;
      expect(((opened['entries'] as Map)['c'] as Map)['updatedAt'], 40);
    });

    test('取回失败（GET 500）同样跳过上传并上报', () async {
      final fx = await _fixture(copyReadable: true);
      final cPath = fx.cipher.remotePath('c');
      fx.dav.failGet.add(cPath);

      final r = await _service(
        fx.dav,
        fx.docs,
        fx.baseline,
        cipher: fx.cipher,
        verdicts: const {'c': ConflictResolution.keepBoth},
      ).syncNow();

      expect(r.unprotectedRemoteDocIds, ['c']);
      expect(fx.dav.puts.where((p) => p == cPath), isEmpty);
      expect(fx.dav.files.containsKey(cPath), isTrue);
    });

    test('云端 404（对象根本不存在）⇒ 不跳过：上传不会覆盖任何内容', () async {
      final fx = await _fixture(remoteCopyPresent: false);
      final cPath = fx.cipher.remotePath('c');

      final r = await _service(
        fx.dav,
        fx.docs,
        fx.baseline,
        cipher: fx.cipher,
        verdicts: const {'c': ConflictResolution.keepBoth},
      ).syncNow();

      expect(r.unprotectedRemoteDocIds, isEmpty);
      expect(fx.dav.puts, contains(cPath));
      expect(r.uploaded, 2);
    });
  });

  group('keepBoth：正常文档不受牵连 + 收敛有界', () {
    test('健康 keepBoth 照常出副本；坏文档不引发整轮异常', () async {
      final fx = await _fixture();
      final r = await _service(
        fx.dav,
        fx.docs,
        fx.baseline,
        cipher: fx.cipher,
        verdicts: const {
          'c': ConflictResolution.keepBoth,
          'h': ConflictResolution.keepBoth,
        },
      ).syncNow();

      expect(r.failedDocIds, isEmpty, reason: '跳过不等于执行失败');
      // h 的远端副本按 keepBoth 落到本地（id 含 -conflict-，内容时间戳 40）。
      final hCopy = fx.docs.docs.keys.firstWhere(
        (k) => k.startsWith('h-conflict-'),
      );
      expect(fx.docs.docs[hCopy]!.updatedAt, 40);
      // 远端 h 收敛到本地主版本 25。
      final plainH = await fx.cipher.decryptDocumentBytes(
        Uint8List.fromList(fx.dav.files[fx.cipher.remotePath('h')]!),
        'h',
      );
      expect(
        (jsonDecode(utf8.decode(plainH)) as Map<String, dynamic>)['updatedAt'],
        25,
      );
      // 普通新增照常上云。
      expect(fx.dav.puts, contains(fx.cipher.remotePath('n')));
    });

    test('连续三轮：每轮只尝试一次 GET、始终没有 PUT 落在坏文档上、其余收敛', () async {
      final fx = await _fixture();
      final cPath = fx.cipher.remotePath('c');
      final service = _service(
        fx.dav,
        fx.docs,
        fx.baseline,
        cipher: fx.cipher,
        verdicts: const {
          'c': ConflictResolution.keepBoth,
          'h': ConflictResolution.keepBoth,
        },
      );

      final rounds = <SyncResult>[
        await service.syncNow(),
        await service.syncNow(),
        await service.syncNow(),
      ];

      for (final r in rounds) {
        expect(r.unprotectedRemoteDocIds, ['c']);
      }
      // 每轮一次尝试（三轮共 3 次 GET），无退避风暴、无重复内尝试。
      expect(fx.dav.gets.where((p) => p == cPath), hasLength(3));
      expect(fx.dav.puts.where((p) => p == cPath), isEmpty);
      // 其余文档第 1 轮上传主版本 + 副本，第 2 轮补传副本，第 3 轮完全收敛。
      expect(rounds[1].uploaded, 1);
      expect(rounds[2].changed, isFalse);
      expect(rounds[2].uploaded, 0);
    });
  });

  group('SyncResult 公共 API 兼容', () {
    test('新字段默认空、可选命名参数（既有构造点不破）', () {
      const plain = SyncResult(uploaded: 0, downloaded: 0, deletedRemote: 0);
      expect(plain.unprotectedRemoteDocIds, isEmpty);
      expect(
        const SyncResult(
          uploaded: 0,
          downloaded: 0,
          deletedRemote: 0,
          unprotectedRemoteDocIds: ['c'],
        ).toString(),
        contains('unprotectedRemote=1'),
      );
    });
  });
}
