// DN-002a 同步单飞互斥回归锁（SyncController）。
//
// 缺陷场景（读码核实，非臆测）：远端清单是无条件读-改-写 PUT
// （SyncService.syncNow 先 GET manifest → 合并 → putBytes(manifestPath)，
// 传输层没有 If-Match 能力，本批也不引入）。页面级按钮禁用挡不住
// 「退出设置页 → 重进 → 再点同步」：webdav_sync_mounted_guard_test.dart:127-135
// 钉死了「页面卸载后该轮继续跑」。两轮并发时后完成那轮会拿它**开始时刻**
// 的旧快照覆盖云端清单——同一设备自己覆盖自己的清单。
//
// 处置：**合并**（第二轮并入在飞那轮，等同一份结果），零新增 UI 文案。
// 本文件钉三件事：①第二轮不产生第二次清单 PUT（连远端清单都不重读）；
// ②第一轮结束后仍能起下一轮（互斥不得变成永久卡死）；③轮次以异常收场时
// 标记照样清除。
//
// 风格照抄 test/features/notes/application/sync_controller_test.dart：
// **刻意不装 TestWidgetsFlutterBinding**（binding 会把 HttpClient 请求劫持
// 成 400），用真实回环 HTTP 走 controller 内建 transport；无 mockito，
// 手写假服务器（本仓既有做法）。全程真异步、无 FakeAsync 假时钟，
// Completer 也在真实区构造与完成。

@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_planner.dart' show SyncManifest;
import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';

/// 内存文档存储桩。
class _MemDocStore implements SyncDocumentStore {
  _MemDocStore(this.docs);

  final Map<String, Uint8List> docs;
  final readCalls = <String>[];

  @override
  Future<SyncLocalInventory> listDocuments() async => SyncLocalInventory(
    readable: [
      for (final e in docs.entries)
        SyncDocMeta(id: e.key, updatedAt: 12345, size: e.value.length),
    ],
  );

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

class _MemBaselineStore implements SyncBaselineStore {
  SyncManifest? saved;

  @override
  Future<SyncManifest?> load() async => null;

  @override
  Future<void> save(SyncManifest manifest) async {
    saved = manifest;
  }
}

/// 计数型回环假 WebDAV：清单 GET/PUT 与文档 PUT 各自计数，
/// 可选把「GET manifest.json」吊在闸门上等外部放行（制造在飞窗口）。
class _CountingDav {
  _CountingDav({this.gateManifest = false});

  final bool gateManifest;
  final Completer<void> gate = Completer<void>();

  int manifestGets = 0;
  int manifestPuts = 0;
  int docPuts = 0;
  String? lastManifestBody;

  late final HttpServer _server;

  Future<void> start() async {
    _server = await HttpServer.bind('127.0.0.1', 0);
    _server.listen((request) async {
      final builder = BytesBuilder();
      await for (final chunk in request) {
        builder.add(chunk);
      }
      final bodyBytes = builder.takeBytes();
      final isManifest = request.uri.path.endsWith('manifest.json');
      switch (request.method) {
        case 'MKCOL':
          request.response.statusCode = 201;
        case 'GET':
          if (isManifest) {
            manifestGets++;
            // 闸门：让第一轮停在「已读远端清单」这一步，制造在飞窗口。
            if (gateManifest) await gate.future;
          }
          request.response.statusCode = 404; // 远端尚无清单
        case 'PUT':
          if (isManifest) {
            manifestPuts++;
            lastManifestBody = utf8.decode(bodyBytes);
          } else {
            docPuts++;
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

Future<void> _waitFor(
  bool Function() condition, {
  required String reason,
}) async {
  for (var i = 0; i < 300; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('等待超时：$reason');
}

SyncController _controller(_MemDocStore docs, _MemBaselineStore baseline) =>
    SyncController(
      configStore: WebDavConfigStore(),
      secretStore: MemorySyncSecretStore(),
      documentStore: docs,
      baselineStore: baseline,
    );

Future<SyncRunOutcome> _round(SyncController controller, Uri baseUrl) =>
    controller.syncNow(
      baseUrl: baseUrl,
      username: 'u',
      password: 'p',
      // 空口令 → NoopSyncCipher：零 KDF、纯明文字节，聚焦互斥本身。
      passphrase: '',
      syncSalt: null,
      conflictHandler: const LwwConflictHandler(),
    );

void main() {
  test('第二轮在飞时被并入同一轮：只读一次远端清单、只 PUT 一次清单', () async {
    final dav = _CountingDav(gateManifest: true);
    await dav.start();
    addTearDown(dav.close);
    final controller = _controller(
      _MemDocStore({'doc-1': Uint8List.fromList(utf8.encode('hello'))}),
      _MemBaselineStore(),
    );

    final first = _round(controller, dav.baseUrl);
    await _waitFor(() => dav.manifestGets >= 1, reason: '第一轮应已读到远端清单');
    expect(dav.manifestGets, 1);

    // 第二轮：页面重进后再点「立即同步」。
    final second = _round(controller, dav.baseUrl);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(
      dav.manifestGets,
      1,
      reason: '并轮的第二轮连远端清单都不该重读（否则就是第二轮在跑）',
    );
    expect(dav.manifestPuts, 0);
    expect(dav.docPuts, 0);

    dav.gate.complete();
    final firstOutcome = await first;
    final secondOutcome = await second;

    expect(firstOutcome.result, isNotNull);
    expect(firstOutcome.error, isNull);
    expect(
      identical(firstOutcome, secondOutcome),
      isTrue,
      reason: '合并语义：第二轮拿到的就是同一份结果对象，不新起一轮',
    );
    expect(
      dav.manifestPuts,
      1,
      reason: '并发两轮只写一次云端清单（本条要守住的不变量）',
    );
    expect(dav.docPuts, 1);
    expect(dav.lastManifestBody, contains('doc-1'));
  });

  test('第一轮结束后仍能起下一轮（互斥不得变成永久卡死）', () async {
    final dav = _CountingDav();
    await dav.start();
    addTearDown(dav.close);
    final docs = _MemDocStore({'doc-1': Uint8List.fromList(utf8.encode('a'))});
    final controller = _controller(docs, _MemBaselineStore());

    final r1 = await _round(controller, dav.baseUrl);
    expect(r1.result, isNotNull);
    expect(dav.manifestPuts, 1);

    final r2 = await _round(controller, dav.baseUrl);
    expect(
      r2.result,
      isNotNull,
      reason: '闸门只挡「在飞」，不挡后续轮次',
    );
    expect(dav.manifestGets, 2);
    expect(dav.manifestPuts, 2);
    expect(dav.docPuts, 2, reason: '假服务器无状态：第二轮照常上传');
  });

  test('轮次以装配异常收场时标记照样清除（异常不得锁死后续同步）', () async {
    final dav = _CountingDav();
    await dav.start();
    addTearDown(dav.close);
    final controller = _controller(
      _MemDocStore({'doc-1': Uint8List.fromList(utf8.encode('a'))}),
      _MemBaselineStore(),
    );

    // 非法盐 → _buildCipher 的 base64Decode 抛 FormatException（装配失败
    // 原样抛出，既有口径），这一轮一个字节都没上网。
    await expectLater(
      controller.syncNow(
        baseUrl: dav.baseUrl,
        username: 'u',
        password: 'p',
        passphrase: 'phrase',
        syncSalt: '@@not-base64@@',
        conflictHandler: const LwwConflictHandler(),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(dav.manifestPuts, 0);

    final next = await _round(controller, dav.baseUrl);
    expect(next.result, isNotNull, reason: '异常轮结束后必须可以再起');
    expect(dav.manifestPuts, 1);
  });
}
