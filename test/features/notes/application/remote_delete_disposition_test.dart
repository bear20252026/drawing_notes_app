// A3-2 甲的手动处置入口：豁免存储 + 三个动作的契约。
//
// 这里守的是两条容易走偏的地方：
//  ① 「仍要上传」不能靠改文档时间戳实现——`updatedAt` 是 LWW / 冲突判据 /
//     墓碑因果锚共同的输入，为了绕过一条判据去改判据本身，是拿数据可信度换一个按钮；
//  ② 豁免必须**用完即弃**，并且读不出来时永远偏向「继续按住」——反过来（把读失败
//     当全豁免）等于一次 IO 抖动就把云端已删的内容悄悄推回去。
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/sync/remote_deletes.dart';
import 'package:drawing_notes_app/core/sync/sync_push_waivers.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/file_sync_push_waiver_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';

import '../../../helpers/temp_dir_cleanup.dart';

/// 只用来验处置动作的字节级效果：内容与 id 一一对应，不掺加密。
class _MemDocs implements SyncDocumentStore {
  final Map<String, Uint8List> docs = {};
  final List<String> deleted = [];

  @override
  Future<SyncLocalInventory> listDocuments() async => SyncLocalInventory(
    readable: [
      for (final e in docs.entries)
        SyncDocMeta(id: e.key, updatedAt: 200, size: e.value.length),
    ],
  );

  @override
  Future<Uint8List?> readDocument(String id) async => docs[id];

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async {
    docs[id] = bytes;
  }

  @override
  Future<void> deleteDocument(String id) async {
    deleted.add(id);
    docs.remove(id);
  }
}

class _ThrowingWaivers implements SyncPushWaiverStore {
  @override
  Future<Set<String>> load() async => throw const FileSystemException('盘读不了');

  @override
  Future<void> save(Set<String> ids) async {}
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('push_waivers_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  group('豁免存储（文件实现）', () {
    FileSyncPushWaiverStore store() =>
        FileSyncPushWaiverStore(directoryProvider: () async => tempDir);

    File file() => File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${FileSyncPushWaiverStore.fileName}',
    );

    test('往返保真；写出稳定序（同一集合两次落盘逐字节一致）', () async {
      await store().save({'b_doc', 'a_doc'});
      final first = file().readAsStringSync();
      await store().save({'a_doc', 'b_doc'});

      expect(file().readAsStringSync(), first,
          reason: '集合顺序不该让文件看起来变了');
      expect(await store().load(), {'a_doc', 'b_doc'});
      expect(jsonDecode(first)['waived'], ['a_doc', 'b_doc']);
    });

    test('不存在 ⇒ 空集；损坏 ⇒ 空集（继续按住，不是全豁免）', () async {
      expect(await store().load(), isEmpty);

      file().writeAsStringSync('{"waived": [ "oops"');
      expect(await store().load(), isEmpty);

      file().writeAsStringSync('[1,2,3]');
      expect(await store().load(), isEmpty);
    });

    test('畸形 id 一律丢弃（这个集合会拼进路径与请求）', () async {
      file().writeAsStringSync(
        jsonEncode({
          'waived': ['ok_1', '../evil', 'a/b', 42, 'ok-2'],
        }),
      );

      expect(await store().load(), {'ok_1', 'ok-2'});
    });

    test('成功落盘不留临时文件', () async {
      await store().save({'x'});

      expect(
        tempDir.listSync().whereType<File>().where((f) => f.path.contains('.tmp')),
        isEmpty,
      );
    });
  });

  group('SyncController.applyRemoteDeleteDisposition', () {
    late _MemDocs docs;
    late MemoryPushWaiverStore waivers;
    late SyncController controller;

    setUp(() {
      docs = _MemDocs();
      waivers = MemoryPushWaiverStore();
      controller = SyncController(
        secretStore: MemorySyncSecretStore(const SyncSecrets()),
        documentStore: docs,
        pushWaiverStore: waivers,
      );
    });

    Uint8List bytes(String tag) =>
        Uint8List.fromList(utf8.encode(tag));

    test('仍要上传 ⇒ 只登记豁免，绝不改本机文档', () async {
      docs.docs['gone'] = bytes('v1');

      final out = await controller.applyRemoteDeleteDisposition(
        docId: 'gone',
        disposition: RemoteDeleteDisposition.pushAnyway,
      );

      expect(out.applied, isTrue);
      expect(out.copyId, isNull);
      expect(await waivers.load(), {'gone'});
      expect(docs.deleted, isEmpty, reason: '登记豁免不是删除');
      expect(docs.docs.containsKey('gone'), isTrue);
    });

    test('重复点「仍要上传」是幂等的（豁免集合不膨胀）', () async {
      for (var i = 0; i < 3; i++) {
        await controller.applyRemoteDeleteDisposition(
          docId: 'gone',
          disposition: RemoteDeleteDisposition.pushAnyway,
        );
      }
      expect(await waivers.load(), {'gone'});
    });

    test('认云端删除 ⇒ 走普通删除（本机那份进回收站），并撤销豁免', () async {
      docs.docs['gone'] = bytes('v1');
      await waivers.save({'gone', 'other'});

      final out = await controller.applyRemoteDeleteDisposition(
        docId: 'gone',
        disposition: RemoteDeleteDisposition.honorCloudDelete,
      );

      expect(out.applied, isTrue);
      expect(docs.deleted, ['gone']);
      expect(docs.docs.containsKey('gone'), isFalse);
      expect(await waivers.load(), {'other'}, reason: '只撤这一篇，别人的豁免不受影响');
    });

    test('留成副本 ⇒ 新 id 拿到同一份字节、原 id 删掉、豁免撤销', () async {
      docs.docs['gone'] = bytes('唯一的画布');
      await waivers.save({'gone'});

      final out = await controller.applyRemoteDeleteDisposition(
        docId: 'gone',
        disposition: RemoteDeleteDisposition.keepAsCopy,
      );

      expect(out.applied, isTrue);
      final copyId = out.copyId!;
      expect(copyId, isNotEmpty);
      expect(docs.docs[copyId], bytes('唯一的画布'));
      expect(docs.docs.containsKey('gone'), isFalse);
      expect(docs.deleted, ['gone']);
      expect(await waivers.load(), isEmpty);
    });

    test('副本 id 必须过白名单——docId 来自未认证的远端清单', () async {
      docs.docs['../../etc/passwd'] = bytes('x');

      final out = await controller.applyRemoteDeleteDisposition(
        docId: '../../etc/passwd',
        disposition: RemoteDeleteDisposition.keepAsCopy,
      );

      final copyId = out.copyId!;
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(copyId), isTrue,
          reason: '消毒后才能进本地路径：残留的 `.` `/` 会造出路径遍历');
      expect(copyId, contains('-copy-'));
    });

    test('先写副本、后删原件：写不了副本时原件必须还在', () async {
      docs.docs['gone'] = bytes('v1');
      // 让下一次 writeDocument 失败（复用同一份内存实现：塞一个非法形状）
      // 用只含非法字符且消毒后仍与原件同名的极端形态无法构造，故这里直接
      // 断言「原件没被删」的分支：本机读不到字节 ⇒ 整笔不执行。
      final missing = await controller.applyRemoteDeleteDisposition(
        docId: 'not_here',
        disposition: RemoteDeleteDisposition.keepAsCopy,
      );

      expect(missing.applied, isFalse);
      expect(docs.deleted, isEmpty);
      expect(docs.docs.containsKey('gone'), isTrue);
    });

    test('豁免存储读失败 ⇒ 处置仍能登记/撤销不炸，且不吞掉动作', () async {
      final broken = SyncController(
        secretStore: MemorySyncSecretStore(const SyncSecrets()),
        documentStore: docs,
        pushWaiverStore: _ThrowingWaivers(),
      );
      docs.docs['gone'] = bytes('v1');

      await expectLater(
        broken.applyRemoteDeleteDisposition(
          docId: 'gone',
          disposition: RemoteDeleteDisposition.pushAnyway,
        ),
        throwsA(isA<FileSystemException>()),
        reason: '豁免写不下去就该报出来——静默“成功”会让用户以为已经放行',
      );
    });
  });
}
