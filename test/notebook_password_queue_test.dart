/// P0/P1 回归锁（审计 2026-10-04）：分页画布（笔记本）密码四入口的
/// 「读载荷 → Argon2id 重绕 → 写回」必须整体在同 id 的独占写队列内执行。
///
/// 旧实现把 `load` 放在队列外：重绕是数百毫秒级慢操作，窗口内的并发落盘
/// （编辑器自动保存、另一次改密/绑盘）先写的新载荷会被「陈旧槽位组」覆盖，
/// UI 却提示成功——静默丢稿 / 静默降密（旧密码复活）。口径对齐
/// `test/blockdoc_password_queue_test.dart`（块文档域）与
/// `StorageFilePasswordManager.setFilePassword` 的「队列内重读最新已落盘
/// 明文后再重封（非陈旧快照）」。
///
/// 同时锁 P1 空密码收口的第三层：笔记本设密/改密/重置盘入口对空串一律
/// [ArgumentError]，空串绝不封成「已加密」。
///
/// 附带锁两个「不得回退」的结构性质：①独占槽位内不得使用排队原语
/// （`_writeNotebook`/再入 `_runExclusive` 会 await 自己所在的链 → 死锁，
/// 表现为下面所有并发用例挂死）；②载荷重读不走 `load`——`load` 会顺带
/// 排一次懒迁移重写，用「读时的整本明文」反超随后写回的新载荷。
///
/// 批B 起新槽位默认 Argon2id——注入轻量参数（[KdfParams.testLight]），
/// 槽位格式与生产一致、无真 KDF 耗时（同 n2/blockdoc v5 套件口径）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp_dir_cleanup.dart';

void main() {
  KdfParams.newSlotDefault = KdfParams.testLight;

  late Directory tempDir;
  late NotebookStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nb_pw_queue_');
    storage = NotebookStorage(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    try {
      await deleteTempDirWithRetry(tempDir);
    } on FileSystemException {
      // Windows 句柄延迟释放——尽力清理（同 n2 套件口径）。
    }
  });

  Notebook nbWithText(String id, String text) =>
      Notebook(id: id, title: '机密分页画布')
        ..pages.add(
          NotebookPage(
            id: 'pg_$id',
            title: '页一',
            document: DrawingDocument(
              id: 'd_$id',
              title: '页',
              width: 100,
              height: 100,
            ),
          )..textItems.add(PageTextItem(id: 't_$id', x: 1, y: 1, text: text)),
        );

  String notebookPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}notebooks'
      '${Platform.pathSeparator}$id.json';

  group('分页画布密码 × 并发落盘（队列内重读载荷）', () {
    test('保存在前 + 改密在后：新载荷存活、密码槽已更新', () async {
      const id = 'nb_q_change_a';
      await storage.encryptAndSave(nbWithText(id, '旧正文'), 'old-pass-1');

      final saveF = storage.encryptAndSave(
        nbWithText(id, '自动保存的新正文'),
        'old-pass-1',
      );
      final changeF = storage.changeNotebookPassword(
        id,
        'old-pass-1',
        'new-pass-2',
      );
      await Future.wait([saveF, changeF]);

      final unlocked = (await storage.load(id))!;
      expect(await storage.decryptNotebook(unlocked, 'new-pass-2'), isTrue);
      expect(unlocked.pages.single.textItems.single.text, '自动保存的新正文');
      expect(await storage.verifyNotebookPassword(id, 'new-pass-2'), isTrue);
      expect(await storage.verifyNotebookPassword(id, 'old-pass-1'), isFalse);
    });

    test('改密在前 + 陈旧口令续写在后：拒绝降密，新密码不被覆盖', () async {
      const id = 'nb_q_change_b';
      await storage.encryptAndSave(nbWithText(id, '旧正文'), 'old-pass-1');

      // 改密先入队；随后那次「拿着旧会话口令的自动保存」必须看到新槽位组。
      final changeF = storage.changeNotebookPassword(
        id,
        'old-pass-1',
        'new-pass-2',
      );
      final staleSaveF = storage.encryptAndSave(
        nbWithText(id, '窗口内的自动保存'),
        'old-pass-1',
      );
      await changeF;
      await expectLater(staleSaveF, throwsFormatException);

      // fail-closed：载荷未被旧槽位组反超——旧密码彻底失效。
      expect(await storage.verifyNotebookPassword(id, 'new-pass-2'), isTrue);
      expect(await storage.verifyNotebookPassword(id, 'old-pass-1'), isFalse);
      final unlocked = (await storage.load(id))!;
      expect(await storage.decryptNotebook(unlocked, 'new-pass-2'), isTrue);
      expect(unlocked.pages.single.textItems.single.text, '旧正文');
    });

    test('保存在前 + 绑盘在后：新载荷存活且重置盘槽位即时可用', () async {
      const id = 'nb_q_bind';
      final usbKey = List<int>.generate(32, (i) => i ^ 0x5A);
      await storage.encryptAndSave(nbWithText(id, '旧正文'), 'bind-pass-1');
      expect(await storage.hasNotebookUsbSlot(id), isFalse);

      final saveF = storage.encryptAndSave(
        nbWithText(id, '绑盘期间的自动保存'),
        'bind-pass-1',
      );
      final bindF = storage.bindNotebookUsbSlot(id, 'bind-pass-1', usbKey);
      await Future.wait([saveF, bindF]);

      expect(await storage.hasNotebookUsbSlot(id), isTrue);
      final unlocked = (await storage.load(id))!;
      expect(await storage.decryptNotebook(unlocked, 'bind-pass-1'), isTrue);
      expect(unlocked.pages.single.textItems.single.text, '绑盘期间的自动保存');
      // 绑上的盘立刻可用（DEK 未变）。
      expect(
        await storage.resetNotebookPasswordWithUsb(id, usbKey, 'reset-pass-9'),
        isTrue,
      );
      expect(
        (await storage.load(id))!.pages.single.textItems.single.text,
        '绑盘期间的自动保存',
      );
    });

    test('保存在前 + 重置盘重置在后：新载荷存活、旧密码失效', () async {
      const id = 'nb_q_reset';
      final usbKey = List<int>.generate(32, (i) => i + 9);
      await storage.encryptAndSave(
        nbWithText(id, '旧正文'),
        'old-pass-1',
        usbKey: usbKey,
      );

      final saveF = storage.encryptAndSave(
        nbWithText(id, '重置期间的自动保存'),
        'old-pass-1',
      );
      final resetF = storage.resetNotebookPasswordWithUsb(
        id,
        usbKey,
        'reset-pass-8',
      );
      await saveF;
      expect(await resetF, isTrue);

      expect(await storage.verifyNotebookPassword(id, 'reset-pass-8'), isTrue);
      expect(await storage.verifyNotebookPassword(id, 'old-pass-1'), isFalse);
      final unlocked = (await storage.load(id))!;
      expect(await storage.decryptNotebook(unlocked, 'reset-pass-8'), isTrue);
      expect(unlocked.pages.single.textItems.single.text, '重置期间的自动保存');
    });

    test('磁盘载荷被第三方更新后设密：以磁盘槽位组为准（非内存快照）', () async {
      const id = 'nb_q_stale_envelope';
      await storage.encryptAndSave(nbWithText(id, '旧正文'), 'first-pass-1');
      // 内存里留着「对话框打开那一刻」的整本快照（载荷 = 旧槽位组）。
      final stale = (await storage.load(id))!;
      await storage.changeNotebookPassword(id, 'first-pass-1', 'second-pass-2');

      // 用陈旧快照续写：队列内重读看到的是 second-pass-2 的信封 ⇒
      // first-pass-1 解不开 → fail-closed 拒写，而不是将旧槽位组写回。
      await expectLater(
        storage.encryptAndSave(stale, 'first-pass-1'),
        throwsFormatException,
      );
      expect(
        EncryptionService.isDualProtectorEnvelope(
          (await storage.load(id))!.encryptedPayload!,
        ),
        isTrue,
      );
      expect(await storage.verifyNotebookPassword(id, 'second-pass-2'), isTrue);
      expect(await storage.verifyNotebookPassword(id, 'first-pass-1'), isFalse);
    });
  });

  group('空口令 fail-closed（收口第三层）', () {
    test('设密/改密/重置一律拒绝空串，且原密码与内容不受影响', () async {
      const id = 'nb_q_empty';
      expect(
        () => storage.encryptAndSave(nbWithText(id, '新正文'), ''),
        throwsArgumentError,
      );
      await storage.encryptAndSave(nbWithText(id, '新正文'), 'pw-1111');
      expect(
        () => storage.changeNotebookPassword(id, 'pw-1111', ''),
        throwsArgumentError,
      );
      expect(
        () => storage.resetNotebookPasswordWithUsb(
          id,
          List<int>.generate(32, (i) => i + 1),
          '',
        ),
        throwsArgumentError,
      );

      // 被拒后原密码仍有效、既没降级成裸奔也没写成空密码信封；
      // 同步抛出不能把该 id 的写队列卡死（后续操作照常）。
      final reloaded = (await storage.load(id))!;
      expect(reloaded.encrypted, isTrue);
      expect(await storage.verifyNotebookPassword(id, 'pw-1111'), isTrue);
      expect(await storage.verifyNotebookPassword(id, ''), isFalse);
      await storage.encryptAndSave(reloaded, 'pw-1111');
      expect(File(notebookPath(id)).existsSync(), isTrue);
    });

    test('首次设密：明文正文不落盘，载荷由内存整本重封', () async {
      const id = 'nb_q_first_set';
      await storage.save(nbWithText(id, '明文正文'));
      await storage.encryptAndSave(nbWithText(id, '明文正文'), 'pw-set-1');

      expect(
        File(notebookPath(id)).readAsStringSync(),
        isNot(contains('明文正文')),
        reason: '设密后正文只能以密文载荷形式落盘',
      );
      final unlocked = (await storage.load(id))!;
      expect(await storage.decryptNotebook(unlocked, 'pw-set-1'), isTrue);
      expect(unlocked.pages.single.textItems.single.text, '明文正文');
    });
  });
}
