/// P0 竞态回归锁（审计 2026-10-03）：块文档改密/绑盘/重置/移密的
/// 「读信封 → Argon2id 重绕 → 写回」三步必须整体在同 id 的独占写队列内执行。
///
/// 旧实现在队列外读信封：重绕是数百毫秒级慢操作，期间编辑器自动保存落盘的
/// 新正文会被「旧正文 + 新槽位」覆盖，UI 却提示成功（静默丢稿）。口径对齐
/// `StorageFilePasswordManager.setFilePassword`（E-17）与其 `_readCurrentRaw`
/// 「队列内重读最新已落盘明文再重封（非陈旧快照）」的既有先例。
///
/// 两种入队顺序都锁：
/// - 保存在前、密码操作在后 ⇒ 密码操作必须在队列内重读到新正文；
/// - 密码操作在前、保存在后 ⇒ 保存 rewrap 落在新槽位信封上，正文仍是最新。
///
/// 另锁 P1 空密码收口的第三层（存储层 fail-closed）：设密/改密/重置入口
/// 对空串一律拒绝，空串绝不封成「已加密」。
///
/// 批B 起新槽位默认 Argon2id——测试注入轻量参数（[KdfParams.testLight]），
/// 槽位格式与生产一致、无真 KDF 耗时（同 n2/blockdoc v5 套件口径）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp_dir_cleanup.dart';

void main() {
  KdfParams.newSlotDefault = KdfParams.testLight;

  late Directory tempDir;
  late NoteBlockDocStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bd_pw_queue_');
    store = NoteBlockDocStore(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    try {
      await deleteTempDirWithRetry(tempDir);
    } on FileSystemException {
      // Windows 句柄延迟释放——尽力清理（同 n2 套件口径）。
    }
  });

  String docPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}blockdocs'
      '${Platform.pathSeparator}$id.json';

  String envelopeOnDisk(String id) => File(docPath(id)).readAsStringSync();

  NoteBlockDoc docWith(String id, String body) => NoteBlockDoc(
    id: id,
    title: '机密笔记',
    body: [NoteBlock.textBlock('${id}_b1', text: body)],
    tags: const ['tag-1'],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  group('块文档密码 × 自动保存并发（写队列内重读信封）', () {
    test('保存在前 + 改密在后：新正文存活、密码槽已更新、无明文泄露', () async {
      const id = 'bd_q_change_a';
      await store.encryptAndSave(docWith(id, '旧正文'), 'old-pass-1');

      // 自动保存先入队，改密随后：改密必须在队列内重读「此刻已落盘」的信封。
      final saveF = store.saveDocument(docWith(id, '自动保存的新正文'));
      final changeF = store.changeBlockDocPassword(
        id,
        'old-pass-1',
        'new-pass-2',
      );
      await Future.wait([saveF, changeF]);

      final envelope = envelopeOnDisk(id);
      expect(EncryptionService.isDualProtectorEnvelope(envelope), isTrue);
      expect(
        envelope,
        isNot(contains('自动保存的新正文')),
        reason: '受密正文不得以明文出现在落盘信封里',
      );
      expect(await store.verifyBlockDocPassword(id, 'new-pass-2'), isTrue);
      expect(await store.verifyBlockDocPassword(id, 'old-pass-1'), isFalse);
      final kept = await store.loadDocument(id);
      expect(kept!.body.single.text, '自动保存的新正文');
    });

    test('改密在前 + 保存在后：最新正文仍存活（rewrap 落在新槽位上）', () async {
      const id = 'bd_q_change_b';
      await store.encryptAndSave(docWith(id, '旧正文'), 'old-pass-1');

      final changeF = store.changeBlockDocPassword(
        id,
        'old-pass-1',
        'new-pass-2',
      );
      final saveF = store.saveDocument(docWith(id, '改密后又编辑的正文'));
      await Future.wait([changeF, saveF]);

      expect(await store.verifyBlockDocPassword(id, 'new-pass-2'), isTrue);
      expect((await store.loadDocument(id))!.body.single.text,
          '改密后又编辑的正文');
    });

    test('保存在前 + 绑盘在后：新正文存活且重置盘槽位即时可用', () async {
      const id = 'bd_q_bind';
      final usbKey = List<int>.generate(32, (i) => i ^ 0x5A);
      await store.encryptAndSave(docWith(id, '旧正文'), 'bind-pass-1');
      expect(await store.hasBlockDocUsbSlot(id), isFalse);

      final saveF = store.saveDocument(docWith(id, '绑盘期间的自动保存'));
      final bindF = store.bindBlockDocUsbSlot(id, 'bind-pass-1', usbKey);
      await Future.wait([saveF, bindF]);

      expect(await store.hasBlockDocUsbSlot(id), isTrue);
      final afterBind = await store.loadDocument(id);
      expect(afterBind!.body.single.text, '绑盘期间的自动保存');
      // 绑上的盘立刻可用（DEK 未变）。
      expect(
        await store.resetBlockDocPasswordWithUsb(id, usbKey, 'reset-pass-9'),
        isTrue,
      );
      final afterReset = await store.loadDocument(id);
      expect(afterReset!.body.single.text, '绑盘期间的自动保存');
    });

    test('保存在前 + 重置盘重置在后：新正文存活、旧密码失效', () async {
      const id = 'bd_q_reset';
      final usbKey = List<int>.generate(32, (i) => i + 9);
      await store.encryptAndSave(
        docWith(id, '旧正文'),
        'old-pass-1',
        usbKey: usbKey,
      );

      final saveF = store.saveDocument(docWith(id, '重置期间的自动保存'));
      final resetF = store.resetBlockDocPasswordWithUsb(
        id,
        usbKey,
        'reset-pass-8',
      );
      await saveF;
      expect(await resetF, isTrue);

      expect(await store.verifyBlockDocPassword(id, 'reset-pass-8'), isTrue);
      expect(await store.verifyBlockDocPassword(id, 'old-pass-1'), isFalse);
      final afterReset = await store.loadDocument(id);
      expect(afterReset!.body.single.text, '重置期间的自动保存');
    });

    test('保存在前 + 移密在后：新正文存活且不再受密', () async {
      const id = 'bd_q_remove';
      await store.encryptAndSave(docWith(id, '旧正文'), 'rm-pass-1');

      final saveF = store.saveDocument(docWith(id, '移密期间的自动保存'));
      final removeF = store.removeBlockDocPassword(id, 'rm-pass-1');
      await Future.wait([saveF, removeF]);

      expect(await store.isBlockDocPasswordProtected(id), isFalse);
      expect(store.isBlockDocUnlocked(id), isFalse); // 移密后清会话 DEK
      final removed = await store.loadDocument(id);
      expect(removed!.body.single.text, '移密期间的自动保存');
    });

    test('空密码 fail-closed（收口第三层）：拒绝空串且不破坏既有密码', () async {
      const id = 'bd_q_empty';
      await store.saveDocument(docWith(id, '普通正文'));

      expect(
        () => store.encryptAndSave(docWith(id, '普通正文'), ''),
        throwsArgumentError,
      );
      await store.encryptAndSave(docWith(id, '普通正文'), 'pw-1111');
      expect(
        () => store.changeBlockDocPassword(id, 'pw-1111', ''),
        throwsArgumentError,
      );
      final usbKey = List<int>.generate(32, (i) => i + 1);
      expect(
        () => store.resetBlockDocPasswordWithUsb(id, usbKey, ''),
        throwsArgumentError,
      );

      // 被拒后原密码仍然有效（既没降级成裸奔，也没写成空密码信封）。
      expect(await store.isBlockDocPasswordProtected(id), isTrue);
      expect(await store.verifyBlockDocPassword(id, 'pw-1111'), isTrue);
      final kept = await store.loadDocument(id);
      expect(kept!.body.single.text, '普通正文');
    });
  });
}
