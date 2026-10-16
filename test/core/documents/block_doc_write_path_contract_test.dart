// DN-205（第三轮专家审计 2026-10-13）：懒加密迁移必须走**同一条**写路径契约。
//
// 上一轮 DN-108 把「正常保存」改成了 `.bak` 备份失败即中止（fail-closed），
// 但同一个类里的懒迁移落盘仍自己手写 tmp + rename + 删旧目标——于是后台迁移这条
// 用户完全无感知的腿，保障比正常保存更弱：第二次 rename 失败时正式文件已删、
// `.bak` 又没写成，三个副本一起消失。
//
// 本文件用同一个注入手法（把 `$path.bak` 做成**目录**，`File.copy` 必失败）
// 钉三条腿遵守同一份契约，并锁住两个附带后果：
//   ① 失败不得吃掉用户唯一的副本（原文件字节原样在盘上）；
//   ② 失败不得静默——审计链里必须留下一条 `note_block_doc.lazy_migration_failed`
//      （原来是一个 `catch (_) {}`，「这篇笔记为什么三个月还是明文」无从查起）。
//
// 真 KDF（写密封走生产默认 600k 派生）⇒ 与同类加密文件一致：kdf 标签 + 放宽超时，
// 且轮询预算严格小于库级 @Timeout（`waitEncryptedBudget` 的 P2-4 不变式）。
@Tags(["kdf"])
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

import '../../helpers/temp_dir_cleanup.dart';
import '../../helpers/wait_encrypted.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dn205_contract_');
    AuditLogger.clear();
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  String docPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}blockdocs'
      '${Platform.pathSeparator}$id.json';

  NoteBlockDoc doc(String id, String title) {
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    return NoteBlockDoc(
      id: id,
      title: title,
      body: [NoteBlock.textBlock('${id}_b1', text: '只有这一份副本')],
      createdAt: now,
      updatedAt: now,
    );
  }


  /// 等懒迁移这条**fire-and-forget** 的腿走完：轮询到「审计留下放弃/失败痕迹」
  /// 或文件已变成密文为止（两条都是终点，谁先到算谁）。预算 < 库级 @Timeout。
  Future<void> drainRewrite(File file) async {
    final steps = waitEncryptedBudget.inMilliseconds ~/ 10;
    for (var i = 0; i < steps; i++) {
      if (file.existsSync() && VaultFileCodec.isEncrypted(await file.readAsBytes())) {
        return;
      }
      if (AuditLogger.snapshot().any(
        (l) => l.contains('lazy_migration_aborted') || l.contains('lazy_migration_failed'),
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('迁移这条腿在 ${waitEncryptedBudget.inSeconds}s 内既没完成也没留下放弃痕迹');
  }

  /// 注入「`.bak` 写不下去」：同名目录会让 `File.copy('$path.bak')` 抛错。
  Future<void> breakBackup(File file) async {
    await Directory('${file.path}.bak').create(recursive: true);
  }

  /// 轮询等某个条件成立；预算沿用 `waitEncryptedBudget`（必须 < 库级 @Timeout，
  /// 否则失败呈现为裸超时、诊断话轮不到说——helper 里记着同一条教训）。
  Future<void> waitFor(
    bool Function() condition, {
    required String label,
  }) async {
    final steps = waitEncryptedBudget.inMilliseconds ~/ 10;
    for (var i = 0; i < steps; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('$label：${waitEncryptedBudget.inSeconds}s 内没等到（预算已按 CI 慢机器留余量）');
  }

  List<String> residue(String dirPath) => Directory(dirPath)
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.tmp'))
      .toList();

  group('DN-205 三条写腿共用同一份数据安全契约', () {
    test('懒加密迁移：备份失败 ⇒ 明文原件字节原样不动，且不静默', () async {
      // 1) 先以「未建库」形态落一篇明文（这就是用户唯一的副本）。
      final plainStore = NoteBlockDocStore(
        directoryProvider: () async => tempDir,
      );
      await plainStore.saveDocument(doc('mig_fail', '迁移前明文'));
      final file = File(docPath('mig_fail'));
      final before = await file.readAsBytes();
      expect(VaultFileCodec.isEncrypted(before), isFalse);

      // 2) 注入故障 + 换成「有主密钥」的存储实例去读它 ⇒ 排队懒迁移。
      await breakBackup(file);
      final key = VaultKeyService.randomBytes(32);
      final store = NoteBlockDocStore(
        directoryProvider: () async => tempDir,
        keyProvider: () async => key,
      );
      final loaded = await store.loadDocument('mig_fail');
      expect(loaded?.title, '迁移前明文', reason: '迁移失败不影响本次读取');

      // 3) 排队的迁移任务确实跑过，并留下了可诊断的一条审计。
      await waitFor(
        () => AuditLogger.snapshot().any((l) => l.contains('lazy_migration_failed')),
        label: '懒迁移失败没有留下审计记录（要么没跑、要么又被吞掉了）',
      );

      // 4) 核心断言：原文件一个字节都没动，也没有半写 tmp 残留。
      expect(await file.readAsBytes(), before);
      expect(residue(file.parent.path), isEmpty);
    });

    test('正常保存：同一注入手法 ⇒ 旧内容仍在盘上、异常如实抛出', () async {
      final store = NoteBlockDocStore(directoryProvider: () async => tempDir);
      await store.saveDocument(doc('save_fail', '第一版'));
      final file = File(docPath('save_fail'));
      final before = await file.readAsBytes();
      await breakBackup(file);

      await expectLater(
        store.saveDocument(doc('save_fail', '第二版')),
        throwsA(isA<FileSystemException>()),
        reason: 'fail-closed：没有备份就不许进入「删目标再换入」分支',
      );
      expect(await file.readAsBytes(), before, reason: '旧内容不得被吃掉');
      expect(residue(file.parent.path), isEmpty);
    });

    // DN-207：两条**确定性**竞态用例。以前这类窗口只能靠调度碰运气
    // （满并发全量下真 KDF 用例红过、同 SHA 重跑绿），现在用
    // `rewriteBarrierForTest` 把「校验通过 → 外部动作 → 迁移落盘」钉死。
    test('时序屏障内删除文件 ⇒ 迁移放弃，不复活已删笔记', () async {
      final plainStore = NoteBlockDocStore(directoryProvider: () async => tempDir);
      await plainStore.saveDocument(doc('gone_in_window', '会被删除'));
      final file = File(docPath('gone_in_window'));
      final key = VaultKeyService.randomBytes(32);
      final store = NoteBlockDocStore(
        directoryProvider: () async => tempDir,
        keyProvider: () async => key,
      );
      store.rewriteBarrierForTest = (id) async {
        await File(docPath(id)).delete();
      };

      await store.loadDocument('gone_in_window');
      await drainRewrite(file);

      expect(
        file.existsSync(),
        isFalse,
        reason: '校验通过后文件被删 ⇒ 迁移不得把它写成密文复活（旧写法会）',
      );
      store.rewriteBarrierForTest = null;
    });

    test('时序屏障内改写盘上内容 ⇒ 迁移放弃，不反超那次改写', () async {
      final plainStore = NoteBlockDocStore(directoryProvider: () async => tempDir);
      await plainStore.saveDocument(doc('raced_in_window', '入队时的快照'));
      final file = File(docPath('raced_in_window'));
      final key = VaultKeyService.randomBytes(32);
      final store = NoteBlockDocStore(
        directoryProvider: () async => tempDir,
        keyProvider: () async => key,
      );
      final raced = doc('raced_in_window', '窗口内的较新内容');
      store.rewriteBarrierForTest = (id) async {
        await File(docPath(id)).writeAsBytes(
          utf8.encode(jsonEncode(raced.toJson())),
        );
      };

      await store.loadDocument('raced_in_window');
      await drainRewrite(file);

      expect(
        jsonDecode(utf8.decode(await file.readAsBytes()))['title'],
        '窗口内的较新内容',
        reason: '落盘前的最后一刻复查必须读到新内容并放弃',
      );
      store.rewriteBarrierForTest = null;
    });

    test('反向锁：障碍移除后迁移照常完成（没把迁移写成永不生效）', () async {
      final plainStore = NoteBlockDocStore(
        directoryProvider: () async => tempDir,
      );
      await plainStore.saveDocument(doc('mig_ok', '待迁移明文'));
      final key = VaultKeyService.randomBytes(32);
      final store = NoteBlockDocStore(
        directoryProvider: () async => tempDir,
        keyProvider: () async => key,
      );

      await store.loadDocument('mig_ok');
      final file = File(docPath('mig_ok'));
      // 迁移这条腿是 fire-and-forget 的排队写，所以给它**确定信号**，不要纯掐表。
      // CI 上这条用例曾以「未提供确定信号（纯轮询）」烧满 120s 预算后失败
      // （run 38849399643，2026-10-16），事后连「队列卡住」「迁移放弃」还是
      // 「runner 太慢」都分不出来——而同文件另外两条用例早就在排空队列了。
      final sealed = await waitEncryptedFile(
        file,
        label: '明文块文档（反向锁）',
        pendingWrite: store.drainWritesForTest('mig_ok'),
      );
      expect(VaultFileCodec.isEncrypted(sealed), isTrue);

      // 迁移后仍读得回来，且内容一字未丢。
      final after = await store.loadDocument('mig_ok');
      expect(after?.title, '待迁移明文');
      expect(after?.body.first.text, '只有这一份副本');
      expect(
        AuditLogger.snapshot().any((l) => l.contains('lazy_migration_failed')),
        isFalse,
        reason:
            '成功路径不该留下失败记录。审计尾部的最后三条：'
            '${AuditLogger.snapshot().reversed.take(3).toList()}',
      );
    });
  });
}
