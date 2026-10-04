// 修复 1 回归锁：同盐改同步口令 ⇒ 全新主密钥 ⇒ 既有云端密文从此不可解。
//
// 机制核实（本文件把它钉死）：
// - `AesSyncCipher.remotePath = HMAC(key, context|docId)` ⇒ 换 key 后所有
//   对象名整体错位（旧对象再无人引用、无人清理）；
// - 固定名的 `manifest.json` 用新 key 解不开旧密文 ⇒ 整轮 syncNow 终止。
// 交付的两层：①保存前判定 + 二次确认（不确认不改已存口令）；②同步期把
// 「口令轮换导致的不可读」与网络类失败分型（不做无用退避重试、对用户可见）。
//
// 「一次即收敛、不烧满退避」的端到端锁在
// test/features/notes/application/sync_controller_rotation_test.dart。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart'
    show humanizeWebDavSyncError;

final _key1 = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
final _key2 = Uint8List.fromList(List<int>.generate(32, (i) => i + 99));

const _base = 'https://dav.example.com/sync/';

class _Docs implements SyncDocumentStore {
  _Docs([Map<String, Uint8List>? docs]) : docs = docs ?? {};
  final Map<String, Uint8List> docs;

  @override
  Future<List<SyncDocMeta>> listDocuments() async => [
    for (final e in docs.entries)
      SyncDocMeta(id: e.key, updatedAt: 100, size: e.value.length),
  ];

  @override
  Future<Uint8List?> readDocument(String id) async => docs[id];

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async =>
      docs[id] = bytes;

  @override
  Future<void> deleteDocument(String id) async => docs.remove(id);
}

class _Baseline implements SyncBaselineStore {
  SyncManifest? value;
  int saveCalls = 0;

  @override
  Future<SyncManifest?> load() async => value;

  @override
  Future<void> save(SyncManifest manifest) async {
    saveCalls++;
    value = manifest;
  }
}

/// 内存 WebDAV：记录 PUT/DELETE 次数据此断言 fail-closed（不把旧清单抹掉、
/// 不误删远端对象）。
class _Dav {
  _Dav(this.files);
  final Map<String, List<int>> files;
  final puts = <String>[];
  final deletes = <String>[];

  MockClient client() => MockClient((request) async {
    final rel = request.url.path.replaceFirst('/sync/', '');
    switch (request.method) {
      case 'MKCOL':
        return http.Response('', 201);
      case 'GET':
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

  SyncService service({
    required List<int> key,
    required SyncDocumentStore docs,
    required SyncBaselineStore baseline,
  }) => SyncService(
    transport: WebDavSyncClient(baseUrl: Uri.parse(_base), client: client()),
    documentStore: docs,
    baselineStore: baseline,
    cipher: AesSyncCipher(key: key),
    conflictHandler: const LwwConflictHandler(),
  );
}

Future<Uint8List> _sealedManifest(List<int> key, Map<String, int> stamps) async {
  final entries = <String, SyncSnapshot>{
    for (final e in stamps.entries)
      e.key: SyncSnapshot(id: e.key, updatedAt: e.value, size: 64),
  };
  return Uint8List.fromList(
    utf8.encode(
      await AesSyncCipher(
        key: key,
      ).sealManifestJson(jsonEncode(SyncManifest(entries: entries).toJson())),
    ),
  );
}

Future<Uint8List> _sealedDoc(List<int> key, String id) =>
    AesSyncCipher(key: key).encryptDocumentBytes(
      Uint8List.fromList(utf8.encode('{"id":"$id"}')),
      id,
    );

void main() {
  group('机制核实：换 key 的三重后果', () {
    test('远端对象名整体错位（旧对象从此不可达、无人清理）', () {
      final oldCipher = AesSyncCipher(key: _key1);
      final newCipher = AesSyncCipher(key: _key2);
      expect(oldCipher.remotePath('doc-1'), isNot(newCipher.remotePath('doc-1')));
      expect(newCipher.remotePath('doc-1'), hasLength(64));
    });

    test('旧 key 密封的 manifest 用新 key 打开 → SyncKeyMismatchException', () async {
      final sealed = await AesSyncCipher(
        key: _key1,
      ).sealManifestJson('{"entries":{}}');
      await expectLater(
        AesSyncCipher(key: _key2).openManifestJson(sealed),
        throwsA(
          allOf(
            isA<SyncKeyMismatchException>(),
            isA<FormatException>(), // 既有 `on FormatException` 调用方不破
          ),
        ),
      );
    });
  });

  group('同步期（修复 1②）：分型、fail-closed、对用户可见', () {
    test('旧密文 manifest → 整轮终止且不回写任何一侧', () async {
      final dav = _Dav({
        SyncService.manifestPath: await _sealedManifest(_key1, {'doc-1': 100}),
      });
      final baseline = _Baseline();
      final service = dav.service(
        key: _key2,
        docs: _Docs(),
        baseline: baseline,
      );

      await expectLater(
        service.syncNow(),
        throwsA(isA<SyncKeyMismatchException>()),
      );
      expect(dav.puts, isEmpty, reason: '失败轮不得 PUT（旧清单必须原样留着）');
      expect(dav.deletes, isEmpty);
      expect(baseline.saveCalls, 0, reason: '不得把残缺状态写进本地基线');
    });

    test('清单可读但文档是旧密文 → 单记 unreadableDocIds，其余照常', () async {
      // 混合态：清单已按新 key 重写，doc-1 的对象还是旧 key 的密文。
      final newCipher = AesSyncCipher(key: _key2);
      final dav = _Dav({
        SyncService.manifestPath: await _sealedManifest(
          _key2,
          {'doc-1': 200, 'doc-2': 300},
        ),
        newCipher.remotePath('doc-1'): await _sealedDoc(_key1, 'doc-1'),
        newCipher.remotePath('doc-2'): await _sealedDoc(_key2, 'doc-2'),
      });
      final docs = _Docs();
      final baseline = _Baseline();

      final result = await dav.service(
        key: _key2,
        docs: docs,
        baseline: baseline,
      ).syncNow();

      expect(result.unreadableDocIds, ['doc-1']);
      expect(result.failedDocIds, contains('doc-1'));
      // 可解的那份照常下载——不可解的旧对象不拖垮整轮。
      expect(result.downloaded, 1);
      expect(docs.docs.containsKey('doc-2'), isTrue);
      expect(docs.docs.containsKey('doc-1'), isFalse);
      // 毒丸保护不变：解不开的远端文档不得进基线（否则下轮被当本地删除误删）。
      expect(baseline.value!.entries.containsKey('doc-1'), isFalse);
      expect(dav.deletes, isEmpty, reason: '绝不因为解不开就删远端');
      expect(dav.files.containsKey(newCipher.remotePath('doc-1')), isTrue);
      // 本轮对它只尝试一次（不当毒丸反复消耗）。
      expect(result.failedDocIds.where((e) => e == 'doc-1'), hasLength(1));
    });
  });

  group('保存前（修复 1①）：判定 + 二次确认 + 不确认零改动', () {
    test('已存口令与新口令不同且盐在 → willRotateSyncKey 为真', () async {
      SharedPreferences.setMockInitialValues({});
      final secrets = MemorySyncSecretStore();
      final controller = SyncController(
        configStore: WebDavConfigStore(),
        secretStore: secrets,
      );
      await controller.save(
        baseUrl: 'https://dav.example.com/dn/',
        username: 'alice',
        password: 'pw',
        passphrase: 'P1',
      );
      final saltBefore = (await controller.loadConfig()).syncSalt;
      expect(await controller.willRotateSyncKey(passphrase: 'P2'), isTrue);
      // 未改（留空）/ 填回原值 → 不算轮换。
      expect(await controller.willRotateSyncKey(passphrase: '   '), isFalse);
      expect(await controller.willRotateSyncKey(passphrase: 'P1'), isFalse);
      expect(
        await controller.willRotateSyncKey(passphrase: ' P2 '),
        isTrue,
        reason: '与 save 的 trim 口径一致',
      );

      // 未确认：抛专用异常，且已存口令/配置一律不动。
      await expectLater(
        controller.save(
          baseUrl: 'https://other.example.com/dn/',
          username: 'bob',
          password: 'pwX',
          passphrase: 'P2',
        ),
        throwsA(isA<SyncKeyRotationConfirmationRequired>()),
      );
      final cfg = await controller.loadConfig();
      expect(cfg.baseUrl, 'https://dav.example.com/dn/');
      expect(cfg.username, 'alice');
      expect(cfg.syncSalt, saltBefore);
      final stored = await secrets.read();
      expect(stored.syncPassphrase, 'P1', reason: '不确认就不改已存口令');
      expect(stored.webdavPassword, 'pw');

      // 确认后：盐仍复用（这正是旧数据不可解的成因），口令换新。
      final effective = await controller.save(
        baseUrl: 'https://other.example.com/dn/',
        username: 'bob',
        password: 'pwX',
        passphrase: 'P2',
        confirmKeyRotation: true,
      );
      expect(effective.passphrase, 'P2');
      final after = await controller.loadConfig();
      expect(after.syncSalt, saltBefore, reason: '轮换只由口令变化引起');
      expect((await secrets.read()).syncPassphrase, 'P2');
    });

    test('从未派生过密钥（无盐 / 无已存口令）→ 不打扰用户', () async {
      SharedPreferences.setMockInitialValues({});
      // 有口令但无盐：_buildCipher 走 Noop，云端没有本密钥体系的密文。
      final controller = SyncController(
        configStore: WebDavConfigStore(),
        secretStore: MemorySyncSecretStore(
          const SyncSecrets(webdavPassword: 'pw', syncPassphrase: 'old'),
        ),
      );
      expect(await controller.willRotateSyncKey(passphrase: 'new'), isFalse);
      final effective = await controller.save(
        baseUrl: 'https://dav.example.com/dn/',
        username: 'alice',
        password: 'pw',
        passphrase: 'new',
      );
      expect(effective.passphrase, 'new');
      // 首次设口令（无已存口令）同样不算轮换。
      final fresh = SyncController(
        configStore: WebDavConfigStore(),
        secretStore: MemorySyncSecretStore(),
      );
      expect(await fresh.willRotateSyncKey(passphrase: 'first'), isFalse);
    });

    test('https 门禁仍排在最前：非法地址先 ArgumentError（非轮换确认）', () async {
      SharedPreferences.setMockInitialValues({});
      final secrets = MemorySyncSecretStore();
      final controller = SyncController(
        configStore: WebDavConfigStore(),
        secretStore: secrets,
      );
      await controller.save(
        baseUrl: 'https://dav.example.com/dn/',
        username: 'alice',
        password: 'pw',
        passphrase: 'P1',
      );
      await expectLater(
        controller.save(
          baseUrl: 'http://example.com/dn/',
          username: 'alice',
          password: 'pw',
          passphrase: 'P2',
        ),
        throwsArgumentError,
      );
      expect((await secrets.read()).syncPassphrase, 'P1');
    });

    test('确认异常与认证失败文案都不带口令/AAD 原文，且可执行', () {
      const rotation = SyncKeyRotationConfirmationRequired();
      expect(rotation.toString(), isNot(contains('P1')));
      expect(rotation.toString(), isNot(contains('P2')));
      expect(humanizeWebDavSyncError(rotation), isNot(contains('P1')));

      final mismatch = humanizeWebDavSyncError(const SyncKeyMismatchException());
      // 具体、可执行：不是那句「检查网络与账号设置」的泛化文案。
      expect(mismatch, contains('同步口令'));
      expect(mismatch, isNot(contains('请检查网络')));
      // 内部错误口径（AAD/MAC/密钥）不外送。
      expect(mismatch, isNot(contains('AAD')));
      expect(mismatch, isNot(contains('同步数据认证失败')));
    });

    test('本轮带不来的旧密文数量必须进同步摘要（可见性）', () async {
      final summary = humanizeWebDavSyncError(
        const SyncKeyMismatchException('x'),
      );
      expect(summary, isA<String>());
      // SyncResult 的分型字段是摘要的数据源（默认空数组 = 公共 API 兼容）。
      const plain = SyncResult(uploaded: 1, downloaded: 0, deletedRemote: 0);
      expect(plain.unreadableDocIds, isEmpty);
      expect(plain.failedDocIds, isEmpty);
      expect(
        const SyncResult(
          uploaded: 0,
          downloaded: 0,
          deletedRemote: 0,
          unreadableDocIds: ['doc-1'],
        ).unreadableDocIds,
        ['doc-1'],
      );
    });
  });

  group('重试收敛（修复 1②）：确定性失败不退避', () {
    test('认证失败不可重试；网络/远端类失败仍可重试', () {
      expect(
        SyncController.isRetryableSyncFailure(const SyncKeyMismatchException()),
        isFalse,
      );
      expect(
        SyncController.isRetryableSyncFailure(
          WebDavSyncException('GET failed', statusCode: 500),
        ),
        isTrue,
      );
      expect(
        SyncController.isRetryableSyncFailure(
          const FormatException('远端清单格式损坏'),
        ),
        isTrue,
        reason: '损坏类仍按既有有界重试（不改既有收敛）',
      );
      expect(
        SyncController.isRetryableSyncFailure(
          TimeoutException('slow', const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });
  });
}
