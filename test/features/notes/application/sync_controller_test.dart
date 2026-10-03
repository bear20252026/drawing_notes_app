// C-05（审计 2026-09-27）行为锁：SyncController 装配收口。
//
// 覆盖三件事：
// 1. 默认装配可构造（生产实现，构造无 IO 副作用）；
// 2. 方法转发到注入桩（loadConfig / readSecrets / save / requireHttpsBaseUrl /
//    syncNow），并锁死 S-03「空值沿用」与盐复用、https fail-closed 语义；
// 3. dispose 语义：无——纯类门面（无通知器/流），store 与 App 同生命周期，
//    每次同步的 transport 在 syncNow 内用毕即 close，无可释放状态。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';

/// 内存文档存储桩：记录 readDocument 调用，验证 syncNow 转发到注入桩。
class _MemDocStore implements SyncDocumentStore {
  final Map<String, Uint8List> docs;
  final readCalls = <String>[];

  _MemDocStore(this.docs);

  @override
  Future<List<SyncDocMeta>> listDocuments() async => [
    for (final e in docs.entries)
      SyncDocMeta(id: e.key, updatedAt: 12345, size: e.value.length),
  ];

  @override
  Future<Uint8List?> readDocument(String id) async {
    readCalls.add(id);
    return docs[id];
  }

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async {
    docs[id] = bytes;
  }

  @override
  Future<void> deleteDocument(String id) async {
    docs.remove(id);
  }
}

/// 内存基线存储桩：捕获 save 的 manifest，验证同步闭环写回。
class _MemBaselineStore implements SyncBaselineStore {
  SyncManifest? saved;

  @override
  Future<SyncManifest?> load() async => null;

  @override
  Future<void> save(SyncManifest manifest) async {
    saved = manifest;
  }
}

/// 本地回环假 WebDAV 服务器：MKCOL→201、GET→404、PUT→201；
/// [alwaysFail] 时一律 500（验证有界重试收敛）。
class _FakeDav {
  final uploaded = <String, List<int>>{};
  String? manifestBody;
  late final HttpServer _server;

  Future<void> start({bool alwaysFail = false}) async {
    _server = await HttpServer.bind('127.0.0.1', 0);
    _server.listen((request) async {
      final builder = BytesBuilder();
      await for (final chunk in request) {
        builder.add(chunk);
      }
      final bodyBytes = builder.takeBytes();
      if (alwaysFail) {
        request.response.statusCode = 500;
        await request.response.close();
        return;
      }
      switch (request.method) {
        case 'MKCOL':
          request.response.statusCode = 201;
        case 'GET':
          // 远端 manifest 不存在 → 404（客户端视为空清单）。
          request.response.statusCode = 404;
        case 'PUT':
          if (request.uri.path.endsWith('manifest.json')) {
            manifestBody = utf8.decode(bodyBytes);
          } else {
            uploaded[request.uri.path] = bodyBytes;
          }
          request.response.statusCode = 201;
        default:
          request.response.statusCode = 405;
      }
      await request.response.close();
    });
  }

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}/sync/');

  Future<void> close() => _server.close(force: true);
}

void main() {
  // 刻意不装 TestWidgetsFlutterBinding：binding 会把所有 HttpClient 请求
  // 劫持为 400，而本测试要用真实本地回环 HTTP 验证 syncNow 的生产装配
  // （transport 由 controller 内建）。SharedPreferences mock 走 platform
  // instance 替换，同样无需 binding。

  test('默认装配可构造：生产实现，构造无 IO 副作用', () {
    // 不调用任何方法——只验证默认装配路径可实例化（真实 store 在首次
    // 用例调用时才触 IO）。
    final controller = SyncController();
    expect(controller, isNotNull);
  });

  test('loadConfig / readSecrets 转发到注入桩', () async {
    SharedPreferences.setMockInitialValues({});
    final secrets = MemorySyncSecretStore(
      const SyncSecrets(webdavPassword: 'p', syncPassphrase: 'q'),
    );
    final controller = SyncController(
      configStore: WebDavConfigStore(),
      secretStore: secrets,
    );

    final stored = await controller.readSecrets();
    expect(stored.webdavPassword, 'p');
    expect(stored.syncPassphrase, 'q');

    final cfg = await controller.loadConfig();
    expect(cfg.baseUrl, '');
    expect(cfg.isConfigured, isFalse);
  });

  group('save：S-03 空值沿用 + 盐复用 + https fail-closed', () {
    test('全新保存：配置与机密双写，盐生成，返回生效值', () async {
      SharedPreferences.setMockInitialValues({});
      final secrets = MemorySyncSecretStore();
      final controller = SyncController(
        configStore: WebDavConfigStore(),
        secretStore: secrets,
      );

      final effective = await controller.save(
        baseUrl: 'https://dav.example.com/dn/',
        username: 'alice',
        password: 'pw1',
        passphrase: 'phrase1',
      );
      expect(effective.password, 'pw1');
      expect(effective.passphrase, 'phrase1');

      final cfg = await controller.loadConfig();
      expect(cfg.baseUrl, 'https://dav.example.com/dn/');
      expect(cfg.username, 'alice');
      expect(cfg.hasSyncSalt, isTrue);

      final stored = await secrets.read();
      expect(stored.webdavPassword, 'pw1');
      expect(stored.syncPassphrase, 'phrase1');
    });

    test('留空保存 = 沿用已存（明文不回填语义），盐保持稳定', () async {
      SharedPreferences.setMockInitialValues({});
      final secrets = MemorySyncSecretStore();
      final controller = SyncController(
        configStore: WebDavConfigStore(),
        secretStore: secrets,
      );
      await controller.save(
        baseUrl: 'https://dav.example.com/dn/',
        username: 'alice',
        password: 'pw1',
        passphrase: 'phrase1',
      );
      final saltBefore = (await controller.loadConfig()).syncSalt;

      final effective = await controller.save(
        baseUrl: 'https://dav.example.com/dn/',
        username: 'alice',
        password: '',
        passphrase: '   ',
      );
      expect(effective.password, 'pw1');
      expect(effective.passphrase, 'phrase1');

      final stored = await secrets.read();
      expect(stored.webdavPassword, 'pw1');
      expect(stored.syncPassphrase, 'phrase1');
      expect((await controller.loadConfig()).syncSalt, saltBefore);
    });

    test('输入新值覆盖旧值，盐仍复用（派生 key 对已上传密文稳定）', () async {
      SharedPreferences.setMockInitialValues({});
      final secrets = MemorySyncSecretStore();
      final controller = SyncController(
        configStore: WebDavConfigStore(),
        secretStore: secrets,
      );
      await controller.save(
        baseUrl: 'https://dav.example.com/dn/',
        username: 'alice',
        password: 'pw1',
        passphrase: 'phrase1',
      );
      final saltBefore = (await controller.loadConfig()).syncSalt;

      final effective = await controller.save(
        baseUrl: 'https://dav.example.com/dn/',
        username: 'bob',
        password: 'pw2',
        passphrase: 'phrase2',
      );
      expect(effective.password, 'pw2');
      expect(effective.passphrase, 'phrase2');

      final stored = await secrets.read();
      expect(stored.webdavPassword, 'pw2');
      expect(stored.syncPassphrase, 'phrase2');
      expect((await controller.loadConfig()).syncSalt, saltBefore);
    });

    test('非 https 非回环：ArgumentError，且配置与机密都不落盘（fail-closed）', () async {
      SharedPreferences.setMockInitialValues({});
      final secrets = MemorySyncSecretStore();
      final controller = SyncController(
        configStore: WebDavConfigStore(),
        secretStore: secrets,
      );
      await controller.save(
        baseUrl: 'https://dav.example.com/dn/',
        username: 'bob',
        password: 'pw2',
        passphrase: 'phrase2',
      );

      await expectLater(
        controller.save(
          baseUrl: 'http://example.com/dn/',
          username: 'hacked',
          password: 'hacked',
          passphrase: 'hacked',
        ),
        throwsArgumentError,
      );

      final stored = await secrets.read();
      expect(stored.webdavPassword, 'pw2');
      expect(stored.syncPassphrase, 'phrase2');
      expect((await controller.loadConfig()).username, 'bob');
    });
  });

  test('requireHttpsBaseUrl 转发：https/回环 http 放行，其余拒绝', () {
    expect(
      () => SyncController.requireHttpsBaseUrl('https://dav.example.com/'),
      returnsNormally,
    );
    expect(
      () => SyncController.requireHttpsBaseUrl('http://127.0.0.1:9000/x/'),
      returnsNormally,
    );
    expect(
      () => SyncController.requireHttpsBaseUrl('http://example.com/'),
      throwsArgumentError,
    );
    expect(
      () => SyncController.requireHttpsBaseUrl('ftp://example.com/'),
      throwsArgumentError,
    );
  });

  group('syncNow：转发注入桩（本地回环 HTTP 端到端一轮）', () {
    test('无口令（Noop cipher）：上传一轮成功，进度与基线经注入桩回写', () async {
      final dav = _FakeDav();
      await dav.start();
      addTearDown(dav.close);
      final docStore = _MemDocStore({
        'doc-1': Uint8List.fromList(utf8.encode('hello')),
      });
      final baselineStore = _MemBaselineStore();
      final controller = SyncController(
        configStore: WebDavConfigStore(),
        secretStore: MemorySyncSecretStore(),
        documentStore: docStore,
        baselineStore: baselineStore,
      );
      final phases = <SyncProgressPhase>[];

      final outcome = await controller.syncNow(
        baseUrl: dav.baseUrl,
        username: 'u',
        password: 'p',
        passphrase: '',
        syncSalt: null,
        conflictHandler: const LwwConflictHandler(),
        onProgress: (p) => phases.add(p.phase),
      );

      final result = outcome.result;
      expect(result, isNotNull);
      expect(result!.uploaded, 1);
      expect(result.downloaded, 0);
      expect(result.deletedRemote, 0);
      expect(result.changed, isTrue);
      // 转发到注入桩：文档从 documentStore 读取，基线回写含 doc-1。
      expect(docStore.readCalls, contains('doc-1'));
      expect(baselineStore.saved, isNotNull);
      expect(baselineStore.saved!.entries.keys, contains('doc-1'));
      // 远端收到文档字节与明文 manifest（Noop：无口令 → 明文透传）。
      expect(dav.uploaded, isNotEmpty);
      expect(dav.manifestBody, isNotNull);
      expect(dav.manifestBody!, contains('doc-1'));
      // 进度回调转发：覆盖连接→规划→上传→写清单→完成。
      expect(
        phases,
        containsAll([
          SyncProgressPhase.connecting,
          SyncProgressPhase.planning,
          SyncProgressPhase.uploading,
          SyncProgressPhase.writingManifest,
          SyncProgressPhase.done,
        ]),
      );
    });

    test('服务器 500：按策略有界重试后以 outcome.error 收敛（不抛）', () async {
      final dav = _FakeDav();
      await dav.start(alwaysFail: true);
      addTearDown(dav.close);
      final controller = SyncController(
        configStore: WebDavConfigStore(),
        secretStore: MemorySyncSecretStore(),
        documentStore: _MemDocStore({}),
        baselineStore: _MemBaselineStore(),
      );

      final outcome = await controller.syncNow(
        baseUrl: dav.baseUrl,
        username: 'u',
        password: 'p',
        passphrase: '',
        syncSalt: null,
        conflictHandler: const LwwConflictHandler(),
      );

      expect(outcome.result, isNull);
      expect(outcome.error, isA<WebDavSyncException>());
      final error = outcome.error! as WebDavSyncException;
      expect(error.statusCode, 500);
    });
  });
}
