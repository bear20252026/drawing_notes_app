/// N2：笔记（NoteBlockDoc）文件密码——NoteBlockDocStore 存储层回归测试。
///
/// 覆盖：encryptAndSave → 解锁往返、锁定态 loadDocument 抛
/// BlockDocLockedException、锁定态 saveDocument 守卫（StateError，
/// 禁止明文覆盖密文）、解锁后 saveDocument 透明 rewrap（内容不丢 +
/// 重置盘槽位仍有效）、listDocHeaders 锁定占位与解锁后真实标题、
/// verify/change/remove 生命周期、重置盘重置（存储层）、回收站
/// fail-closed 与恢复往返、loadAll 跳过锁定、会话 DEK 生命周期。
///
/// 注：批B 起新槽位默认 Argon2id——测试注入轻量参数（KdfParams.testLight）
/// 避免拖慢套件，槽位格式与生产一致；仍放宽单测超时到 3 分钟。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 批B：注入测试轻量 KDF（新槽位 Argon2id 8MiB≈几十 ms；生产默认
  // 64MiB t2 p2）。槽位 JSON 格式与生产完全一致，仅参数不同。
  KdfParams.newSlotDefault = KdfParams.testLight;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bd_n2_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Windows 句柄延迟释放——尽力清理。
      }
    }
  });

  NoteBlockDocStore storageWith() =>
      NoteBlockDocStore(directoryProvider: () async => tempDir);

  NoteBlockDoc docWith(
    String id, {
    String title = '机密笔记',
    List<String> tags = const ['tag-1'],
  }) => NoteBlockDoc(
    id: id,
    title: title,
    body: [
      NoteBlock.textBlock('${id}_b1', text: '绝密正文第一行'),
      NoteBlock.textBlock('${id}_b2', text: '第二行'),
    ],
    tags: tags,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  group('NoteBlockDocStore 文件密码（N2）', () {
    const id = 'bd_n2_s1';

    test(
      'encryptAndSave → 锁定态抛 BlockDocLockedException → verify 解锁往返',
      () async {
        final store = storageWith();
        final usbKey = List<int>.generate(32, (i) => i ^ 0x5A);
        await store.encryptAndSave(docWith(id), 'pass-1111', usbKey: usbKey);
        expect(await store.isBlockDocPasswordProtected(id), isTrue);
        expect(store.isBlockDocUnlocked(id), isTrue); // 设密即入会话

        // 新实例（模拟重启）：会话丢失 → 锁定。
        final cold = storageWith();
        expect(cold.isBlockDocUnlocked(id), isFalse);
        await expectLater(
          cold.loadDocument(id),
          throwsA(isA<BlockDocLockedException>()),
        );

        // 解锁（verify 成功即入会话）→ 完整往返。
        expect(await cold.verifyBlockDocPassword(id, 'pass-1111'), isTrue);
        final doc = (await cold.loadDocument(id))!;
        expect(doc.title, '机密笔记');
        expect(doc.tags, ['tag-1']);
        expect(doc.body[0].text, '绝密正文第一行');
        expect(doc.body[1].text, '第二行');
        // 错密码拒绝。
        expect(await cold.verifyBlockDocPassword(id, 'wrong'), isFalse);
      },
    );

    test('锁定态 saveDocument 守卫：禁止明文覆盖密文（StateError）', () async {
      final store = storageWith();
      await store.encryptAndSave(docWith(id), 'guard-pass-1');

      // 冷实例（无 DEK）试图保存 → fail-closed。
      final cold = storageWith();
      await expectLater(
        cold.saveDocument(docWith(id).copyWith(title: '明文篡改')),
        throwsStateError,
      );
      // 原密文未被覆盖：解锁后内容仍是原样。
      expect(await cold.verifyBlockDocPassword(id, 'guard-pass-1'), isTrue);
      expect((await cold.loadDocument(id))!.title, '机密笔记');
    });

    test('解锁后 saveDocument 透明 rewrap：内容不丢 + 重置盘仍有效', () async {
      final store = storageWith();
      final usbKey = List<int>.generate(32, (i) => i + 9);
      await store.encryptAndSave(docWith(id), 'edit-pass-1', usbKey: usbKey);

      // 解锁后 DocPage 自动保存（saveDocument）走 rewrap——零改动透明。
      await store.saveDocument(
        docWith(id).copyWith(
          body: [
            NoteBlock.textBlock('${id}_b1', text: '编辑后的正文'),
            NoteBlock.textBlock('${id}_b2', text: '第二行'),
            NoteBlock.textBlock('${id}_b3', text: '新增行'),
          ],
        ),
      );
      final edited = (await store.loadDocument(id))!;
      expect(edited.body.length, 3);
      expect(edited.body[0].text, '编辑后的正文');
      expect(edited.body[2].text, '新增行');
      expect(
        EncryptionService.hasUsbSlotV5(
          await File(
            '${(await tempDir.resolveSymbolicLinks())}'
            '${Platform.pathSeparator}blockdocs'
            '${Platform.pathSeparator}$id.json',
          ).readAsString(),
        ),
        isTrue,
      ); // 续写仅重生成 payload，USB 槽原样保留

      // 重置盘仍可用（DEK 未变）。
      expect(
        await store.resetBlockDocPasswordWithUsb(id, usbKey, 'reset-2222'),
        isTrue,
      );
      final afterReset = (await store.loadDocument(id))!;
      expect(afterReset.body[0].text, '编辑后的正文');
    });

    test('listDocHeaders：锁定占位不泄露标题/标签；解锁后刷新真实头', () async {
      final store = storageWith();
      await store.encryptAndSave(docWith(id), 'list-pass-1');
      // 设密即入会话（同实例）→ 真实标题；冷实例（模拟重启）→ 占位。
      expect((await store.listDocHeaders()).single.locked, isFalse);
      final cold = storageWith();

      // 锁定占位：标题「加密笔记」、标签空、locked:true。
      final headers = await cold.listDocHeaders();
      expect(headers, hasLength(1));
      final h = headers.single;
      expect(h.id, id);
      expect(h.title, '加密笔记');
      expect(h.tags, isEmpty);
      expect(h.locked, isTrue);

      // 解锁后 → 真实标题与标签。
      expect(await cold.verifyBlockDocPassword(id, 'list-pass-1'), isTrue);
      final unlocked = await cold.listDocHeaders();
      expect(unlocked.single.title, '机密笔记');
      expect(unlocked.single.tags, ['tag-1']);
      expect(unlocked.single.locked, isFalse);

      // 忘记会话 → 回到占位（模拟切后台锁屏清 DEK）。
      cold.forgetBlockDocPassword(id);
      expect(cold.isBlockDocUnlocked(id), isFalse);
      expect((await cold.listDocHeaders()).single.locked, isTrue);
    });

    test('改密：仅重绕密码槽；旧密码失效、新密码可解', () async {
      final store = storageWith();
      await store.encryptAndSave(docWith(id), 'old-pass-1');
      await store.changeBlockDocPassword(id, 'old-pass-1', 'new-pass-2');
      expect(await store.verifyBlockDocPassword(id, 'new-pass-2'), isTrue);
      expect(await store.verifyBlockDocPassword(id, 'old-pass-1'), isFalse);
      expect((await store.loadDocument(id))!.title, '机密笔记');
      // 错旧密码 → FormatException。
      final cold = storageWith();
      await cold.verifyBlockDocPassword(id, 'new-pass-2');
      expect(
        () => cold.changeBlockDocPassword(id, 'wrong-old', 'x-pass'),
        throwsFormatException,
      );
    });

    test('重置盘（存储层）：事后绑定须验密；错盘 fail-closed；重置成功', () async {
      final store = storageWith();
      await store.encryptAndSave(docWith(id), 'bind-pass-1');
      expect(await store.hasBlockDocUsbSlot(id), isFalse);
      final usbKey = List<int>.generate(32, (i) => i + 3);
      // 错密码拒绝。
      await expectLater(
        store.bindBlockDocUsbSlot(id, 'wrong-pass', usbKey),
        throwsFormatException,
      );
      await store.bindBlockDocUsbSlot(id, 'bind-pass-1', usbKey);
      expect(await store.hasBlockDocUsbSlot(id), isTrue);
      // 重复绑定拒绝。
      await expectLater(
        store.bindBlockDocUsbSlot(id, 'bind-pass-1', usbKey),
        throwsFormatException,
      );

      // 冷实例错盘 fail-closed → false。
      final cold = storageWith();
      final wrongKey = List<int>.generate(32, (i) => 99 - i);
      expect(
        await cold.resetBlockDocPasswordWithUsb(id, wrongKey, 'nope-pass'),
        isFalse,
      );
      // 正确盘 → 重置成功，内容不丢。
      expect(
        await cold.resetBlockDocPasswordWithUsb(id, usbKey, 'reset-3333'),
        isTrue,
      );
      final doc = (await cold.loadDocument(id))!;
      expect(doc.title, '机密笔记');
      expect(doc.body[0].text, '绝密正文第一行');
    });

    test('移除密码：错密码拒绝；正确 → 回普通存储可自由读写', () async {
      final store = storageWith();
      await store.encryptAndSave(docWith(id), 'remove-pass-1');
      // 错密码。
      await expectLater(
        store.removeBlockDocPassword(id, 'wrong'),
        throwsFormatException,
      );
      // 正确 → 不再受密、会话 DEK 清除、内容完整。
      await store.removeBlockDocPassword(id, 'remove-pass-1');
      expect(await store.isBlockDocPasswordProtected(id), isFalse);
      expect(store.isBlockDocUnlocked(id), isFalse);
      final doc = (await store.loadDocument(id))!;
      expect(doc.title, '机密笔记');
      expect(doc.tags, ['tag-1']);
      expect(doc.body[1].text, '第二行');
      // 移除后可正常明文保存。
      await store.saveDocument(doc.copyWith(title: '自由编辑'));
      expect((await store.loadDocument(id))!.title, '自由编辑');
    });

    test('回收站：锁定条目 fail-closed 不泄露；恢复后仍受密、解锁可读', () async {
      final store = storageWith();
      await store.encryptAndSave(docWith(id), 'trash-pass-1');

      // 冷实例删除：envelope 原样 rename 进回收站（不落明文）。
      final cold = storageWith();
      expect(await cold.deleteDocument(id), isTrue);
      expect(cold.isBlockDocUnlocked(id), isFalse); // 删除后清会话 DEK
      // fail-closed：未解锁的密文条目给「加密笔记」占位（不泄露标题，
      // 与 listDocHeaders 同口径；仍可恢复）。
      final lockedTrash = await cold.listTrash();
      expect(lockedTrash, hasLength(1));
      expect(lockedTrash.single.doc.id, id);
      expect(lockedTrash.single.doc.title, '加密笔记');

      // 恢复（rename 回激活区）→ 仍是 v5 信封，未解锁仍抛锁定。
      expect(await cold.restoreDocument(id), isTrue);
      expect(await cold.isBlockDocPasswordProtected(id), isTrue);
      await expectLater(
        cold.loadDocument(id),
        throwsA(isA<BlockDocLockedException>()),
      );

      // 解锁后可读完整内容。
      expect(await cold.verifyBlockDocPassword(id, 'trash-pass-1'), isTrue);
      final doc = (await cold.loadDocument(id))!;
      expect(doc.title, '机密笔记');
      expect(doc.body[1].text, '第二行');
      // 回收站已空。
      expect(await cold.listTrash(), isEmpty);
    });

    test('loadAll：锁定笔记跳过（fail-closed）；解锁后出现', () async {
      final store = storageWith();
      await store.encryptAndSave(docWith(id), 'all-pass-1');
      final cold = storageWith();
      expect(await cold.loadAll(), isEmpty); // 锁定 → 跳过
      expect(await cold.verifyBlockDocPassword(id, 'all-pass-1'), isTrue);
      final docs = await cold.loadAll();
      expect(docs, hasLength(1));
      expect(docs.single.title, '机密笔记');
    });

    test('明文文档不受影响：isBlockDocPasswordProtected false + 往返', () async {
      final store = storageWith();
      await store.saveDocument(docWith(id, title: '普通笔记'));
      expect(await store.isBlockDocPasswordProtected(id), isFalse);
      final doc = (await store.loadDocument(id))!;
      expect(doc.title, '普通笔记');
      final headers = await store.listDocHeaders();
      expect(headers.single.title, '普通笔记');
      expect(headers.single.locked, isFalse);
    });
  });
}
