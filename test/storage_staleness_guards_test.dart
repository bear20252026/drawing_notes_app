/// P1 回归锁：陈旧快照不得反超较新的写入（两条读-改-写路径）。
///
/// ① 画布懒迁移：`StorageService.listDocuments` 在读文件时捕获明文 `raw`，
///   经若干 await 后才 `enqueueRawRewrite` —— 队列把这份**陈旧快照**加密写回，
///   反超并覆盖队列中排在前面的较新保存（编辑内容静默回退）。修法是队列内
///   重读当前字节、与快照不一致就放弃迁移（语义对齐
///   `test/core/storage/file_password_concurrency_test.dart` 断言的
///   「重封写不是覆盖陈旧明文」）。
/// ② 分页画布改密/绑盘/重置盘：整本 `load → save` 在队列外完成，窗口内的
///   并发保存被陈旧整本快照覆盖。修法是把读-改-写收进同一 per-id 独占槽位，
///   且只替换信封字段（局部更新）。
///
/// 批B 起新槽位默认 Argon2id——② 用轻量参数（KdfParams.testLight），
/// 槽位格式与生产一致；放宽超时到 3 分钟。
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/storage_directories.dart';
import 'package:drawing_notes_app/core/storage/storage_secret_session.dart';
import 'package:drawing_notes_app/core/storage/storage_write_pipeline.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'helpers/temp_dir_cleanup.dart';

void main() {
  KdfParams.newSlotDefault = KdfParams.testLight;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('staleness_guard_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  group('画布懒迁移（StorageWritePipeline.enqueueRawRewrite）', () {
    late StorageDirectories dirs;
    late StorageWritePipeline pipeline;
    late Uint8List key;

    setUp(() async {
      key = VaultKeyService.randomBytes(32);
      dirs = StorageDirectories(directoryProvider: () async => tempDir);
      pipeline = StorageWritePipeline(
        directories: dirs,
        secrets: StorageSecretSession(),
        keyProvider: () async => key,
      );
      await dirs.ensureDocuments();
    });

    String docPath(String id) => dirs.documentPathFor(id);

    Uint8List plain(String id, String title) => Uint8List.fromList(
      utf8.encode(jsonEncode({
        'document': {'id': id, 'title': title},
      })),
    );

    Future<String> titleOnDisk(String id) async {
      final bytes = await File(docPath(id)).readAsBytes();
      final clear = await VaultFileCodec.decrypt(
        bytes,
        key,
        aadContext: 'doc:$id',
      );
      final root = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      return (root['document'] as Map<String, dynamic>)['title'] as String;
    }

    /// 排空队列（迁移是 fire-and-forget，断言前必须等队列走完）。
    Future<void> drain(String id) =>
        pipeline.runDocExclusive(id, () async {});

    test('队列内重读：陈旧明文快照不覆盖排在前面的较新保存', () async {
      const id = 'stale_migrate';
      final stale = plain(id, 'v1');
      File(docPath(id)).writeAsBytesSync(stale);

      final gate = Completer<void>();
      // 较新的保存先入队（被 gate 卡在队列里），陈旧快照的迁移后入队——
      // 这正是 listDocuments「先捕获 raw、await 之后才入队」的时序形状。
      final newerSave = pipeline.enqueueSave(id, () async {
        await gate.future;
        await pipeline.saveEncoded(id, plain(id, 'v2'));
      });
      pipeline.enqueueRawRewrite(id, stale);
      gate.complete();

      await newerSave;
      await drain(id);

      expect(
        await titleOnDisk(id),
        'v2',
        reason: '迁移若照抄陈旧快照会把 v2 反超回 v1',
      );
      expect(
        VaultFileCodec.isEncrypted(File(docPath(id)).readAsBytesSync()),
        isTrue,
        reason: '较新的保存本身已是密文，不应被改写',
      );
    });

    test('磁盘仍是入队时的明文快照 → 迁移照常完成', () async {
      const id = 'stale_migrate_ok';
      final plainBytes = plain(id, 'v1');
      File(docPath(id)).writeAsBytesSync(plainBytes);

      pipeline.enqueueRawRewrite(id, plainBytes);
      await drain(id);

      expect(
        VaultFileCodec.isEncrypted(File(docPath(id)).readAsBytesSync()),
        isTrue,
        reason: '磁盘未变时快照迁移仍须正常完成（不能被守卫误伤）',
      );
      expect(await titleOnDisk(id), 'v1');
    });

    test('迁移排队后文档被删除 → 不复活', () async {
      const id = 'stale_migrate_gone';
      final plainBytes = plain(id, 'v1');
      File(docPath(id)).writeAsBytesSync(plainBytes);

      pipeline.enqueueRawRewrite(id, plainBytes);
      await File(docPath(id)).delete();
      await drain(id);

      expect(File(docPath(id)).existsSync(), isFalse);
    });
  });

  group('分页画布读-改-写（NotebookStorage 密码管理面）', () {
    Notebook nbWithPage(String id) => Notebook(id: id, title: '机密分页画布')
      ..pages.add(
        NotebookPage(
          id: 'pg1',
          title: '页一',
          document: DrawingDocument(id: 'd1', title: '页', width: 100, height: 100),
        ),
      );

    test('改密只替换信封字段：窗口内的并发整本保存不被陈旧快照覆盖', () async {
      const id = 'nb_stale_rmw';
      final notebookPath =
          '${tempDir.path}${Platform.pathSeparator}notebooks'
          '${Platform.pathSeparator}$id.json';
      var keyCalls = 0;
      final storage = NotebookStorage(
        directoryProvider: () async => tempDir,
        // 未启用保险库（返回 null）：笔记本 JSON 明文落盘，便于直接改文件
        // 模拟并发保存；密钥调用计数用于注入「load 之后、写回之前」的交错。
        keyProvider: () async {
          if (++keyCalls == 2) {
            final file = File(notebookPath);
            final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
            root['title'] = '并发保存的新标题';
            file.writeAsStringSync(jsonEncode(root), flush: true);
          }
          return null;
        },
      );

      await storage.encryptAndSave(nbWithPage(id), 'old-pass-1');
      keyCalls = 0;
      await storage.changeNotebookPassword(id, 'old-pass-1', 'new-pass-2');

      final reloaded = await storage.load(id);
      expect(
        reloaded?.title,
        '并发保存的新标题',
        reason: '整本 load→save 会用陈旧快照覆盖并发保存（本次修复项）',
      );
      expect(await storage.verifyNotebookPassword(id, 'new-pass-2'), isTrue);
      expect(await storage.verifyNotebookPassword(id, 'old-pass-1'), isFalse);
    });

    test('改密后加密内容仍可解（局部更新不丢载荷）', () async {
      const id = 'nb_stale_rmw_payload';
      final storage = NotebookStorage(directoryProvider: () async => tempDir);
      await storage.encryptAndSave(nbWithPage(id), 'pass-aaa');
      await storage.changeNotebookPassword(id, 'pass-aaa', 'pass-bbb');

      final unlocked = (await storage.load(id))!;
      expect(await storage.decryptNotebook(unlocked, 'pass-bbb'), isTrue);
      expect(unlocked.pages.single.textItems, isEmpty);
      expect(unlocked.pages.single.title, '页一');
    });
  });
}
