// 审查修复回归（2026-11-16 全面升级重构审查）。
//
// 钉住两类修复：
// ① **明文外层取钥守卫**（notebook_storage_password.dart
//    _encryptedPayloadOnDiskInsideExclusive）：保险库有钥但笔记本未设密时
//    外层是明文 JSON——此前有钥即无条件 decrypt 撞 vault_file_codec
//    「不是 DNV 加密信封」抛错，阻断 ensure/改密/绑盘。补 !isEncrypted 放行
//    （对齐 _patchEncryptedPayloadInsideExclusive 既有口径）。
// ② **DEK 用完即焚**（encryption_service 五处内部独占副本：新生/改密/
//    重置盘/绑盘/块文档解密）：补 finally fillRange 后全链路功能不变。
//    DEK 是方法内局部副本，零化不可从外部直接观测——本组以「全链路仍正确」
//    回归保证零化未误伤调用方传入的 rewrap DEK（那几处归属调用方，未擦）。
//
// 轻量 KDF（testLight）注入，格式与生产一致、无真 KDF 耗时。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';

import 'helpers/temp_dir_cleanup.dart';

void main() {
  KdfParams.newSlotDefault = KdfParams.testLight;

  late Directory tempDir;
  const enc = EncryptionService();
  const pw = 'review-fix-pw';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nb_review_fix_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  Notebook nb(String id) => Notebook(id: id, title: '审查修复测试本');

  group('① 明文外层取钥守卫（保险库有钥 + 笔记本未设密）', () {
    test('ensureNotebookMediaKey：明文外层不再撞「不是 DNV 信封」抛错', () async {
      final key = VaultKeyService.randomBytes(32);
      final storage = NotebookStorage(
        directoryProvider: () async => tempDir,
        keyProvider: () async => key, // 保险库恒解锁
      );
      // 直接构造「明文外层 + 无 encryptedPayload」笔记本字节——真实命中
      // _encryptedPayloadOnDiskInsideExclusive 的明文分支（save 会懒迁移成
      // DNV，故不走 save）。这正是「保险库已建、笔记本尚未设密」的磁盘形态。
      final dir = Directory('${tempDir.path}/notebooks')
        ..createSync(recursive: true);
      final plainJson = jsonEncode({
        'id': 'nb_plain',
        'title': '明文外层本',
        'encrypted': false,
        'pages': <Map<String, dynamic>>[],
      });
      File('${dir.path}/nb_plain.json').writeAsStringSync(plainJson);

      // 修复前：有钥即 decrypt 明文 → VaultFileException。修复后：明文放行，
      // 无 encryptedPayload → unwrapMediaKey 返回 null → ensure 无操作（不抛）。
      await storage.ensureNotebookMediaKey('nb_plain');
      expect(await storage.isEncryptedNotebook('nb_plain'), isFalse);
    });

    test('bindNotebookUsbSlot：明文外层本可正常设密绑盘（读载荷不抛）', () async {
      final key = VaultKeyService.randomBytes(32);
      final storage = NotebookStorage(
        directoryProvider: () async => tempDir,
        keyProvider: () async => key,
      );
      // 先设密（encryptAndSave 内部读载荷走同一守卫路径）——明文外层起步。
      await storage.encryptAndSave(nb('nb_bind'), pw);
      expect(await storage.verifyNotebookPassword('nb_bind', pw), isTrue);
      // 绑盘：读载荷（此时已 DNV 外层）+ 重绕 + 写回，全链路不抛。
      final usbKey = VaultKeyService.randomBytes(32);
      await storage.bindNotebookUsbSlot('nb_bind', pw, usbKey);
      expect(await storage.hasNotebookUsbSlot('nb_bind'), isTrue);
    });
  });

  group('② DEK 零化后全链路功能不变', () {
    test('改密：旧密码解出 DEK 重绕后，新密码可解、旧密码失效、media 槽保留', () async {
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb_chg',
        plaintext: '{"pages":[]}',
        password: pw,
      );
      expect(EncryptionService.hasMediaSlotV5(envelope), isTrue);
      final changed = await enc.changeNotebookPasswordV5(
        notebookId: 'nb_chg',
        encryptedJson: envelope,
        oldPassword: pw,
        newPassword: 'new-pw-2',
      );
      // 新密码可解出 K_note（DEK 零化未破坏重绕）。
      final kNote = await enc.unwrapNotebookMediaKey(
        notebookId: 'nb_chg',
        encryptedJson: changed,
        password: 'new-pw-2',
      );
      expect(kNote, isNotNull);
      expect(kNote!.length, 32);
      // media 槽原样保留（LUKS 语义）。
      expect(EncryptionService.hasMediaSlotV5(changed), isTrue);
      // 旧密码失效。
      await expectLater(
        enc.unwrapNotebookMediaKey(
          notebookId: 'nb_chg',
          encryptedJson: changed,
          password: pw,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('重置盘：U 盘钥匙解出 DEK 重绕后新密码可解、media 槽保留', () async {
      final usbKey = VaultKeyService.randomBytes(32);
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb_rst',
        plaintext: '{"pages":[]}',
        password: pw,
        usbKey: usbKey,
      );
      final reset = await enc.resetNotebookPasswordWithUsbV5(
        notebookId: 'nb_rst',
        encryptedJson: envelope,
        usbKey: usbKey,
        newPassword: 'reset-pw-3',
      );
      expect(reset, isNotNull);
      final kNote = await enc.unwrapNotebookMediaKey(
        notebookId: 'nb_rst',
        encryptedJson: reset!,
        password: 'reset-pw-3',
      );
      expect(kNote, isNotNull);
      expect(EncryptionService.hasMediaSlotV5(reset), isTrue);
    });

    test('块文档：加密→解密往返不变（解密路径 DEK 零化未误伤）', () async {
      const plain = '{"blocks":[{"type":"paragraph","text":"审查"}]}';
      final envelope = await enc.encryptBlockDocPasswordV5(
        docId: 'bd_1',
        plaintext: plain,
        password: pw,
      );
      final decrypted = await enc.decryptBlockDocPassword(
        docId: 'bd_1',
        encryptedJson: envelope,
        password: pw,
      );
      expect(decrypted, plain);
    });

    test('续写 rewrap：调用方传入的 DEK 不被擦（rewrap 后仍可二次复用）', () async {
      // unwrapPasswordSlotForRewrap / rewrapPayloadV5 的 DEK 归属调用方，
      // 本轮零化只擦方法内独占副本——此用例钉住「调用方 DEK 仍可复用」。
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb_rw',
        plaintext: '{"pages":[]}',
        password: pw,
      );
      final dek = await enc.unwrapPasswordSlotForRewrap(
        notebookId: 'nb_rw',
        encryptedJson: envelope,
        password: pw,
      );
      expect(dek, isNotNull);
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      final rw1 = await enc.rewrapPayloadV5(
        notebookId: 'nb_rw',
        map: map,
        dek: dek!,
        plaintext: '{"pages":[1]}',
      );
      // 同一 DEK 二次复用（若被误擦则此处 AEAD 认证失败）。
      final rw2 = await enc.rewrapPayloadV5(
        notebookId: 'nb_rw',
        map: map,
        dek: dek,
        plaintext: '{"pages":[2]}',
      );
      expect(rw1, isNot(rw2));
      // 两次续写产物都能用原密码解出。
      expect(
        await enc.decryptWithPasswordAad(
          notebookId: 'nb_rw',
          encryptedJson: rw2,
          password: pw,
        ),
        '{"pages":[2]}',
      );
    });
  });
}