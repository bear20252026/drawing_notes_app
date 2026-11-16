// K_note 生产接线（2026-11-16）：每笔记本媒体独立密钥——v5 信封 slots.media
// 封存（DEK 包裹，AAD 绑定笔记本 ID）；媒体服务 LRU 映射（上限 32）。
// 真 Argon2id 派生用例打 kdf 标签参与 CI 分流。
@Tags(['kdf'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  const enc = EncryptionService();
  const pw = 'knote-test-pw';

  group('v5 信封 media 槽（信封层）', () {
    test('encryptWithPasswordV5 自动生成 media 槽；解包往返一致', () async {
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-k1',
        plaintext: '{"pages":[]}',
        password: pw,
      );
      expect(EncryptionService.hasMediaSlotV5(envelope), isTrue);
      final k1 = await enc.unwrapNotebookMediaKey(
        notebookId: 'nb-k1',
        encryptedJson: envelope,
        password: pw,
      );
      expect(k1, isNotNull);
      expect(k1!.length, 32);
      // 再解包一次结果一致（确定性）。
      final k2 = await enc.unwrapNotebookMediaKey(
        notebookId: 'nb-k1',
        encryptedJson: envelope,
        password: pw,
      );
      expect(k2, k1);
    });

    test('错误密码 → null；跨笔记本解包 → null（AAD 绑定）', () async {
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-k1',
        plaintext: 'x',
        password: pw,
      );
      expect(
        await enc.unwrapNotebookMediaKey(
          notebookId: 'nb-k1',
          encryptedJson: envelope,
          password: 'wrong-pw',
        ),
        isNull,
      );
      expect(
        await enc.unwrapNotebookMediaKey(
          notebookId: 'nb-other',
          encryptedJson: envelope,
          password: pw,
        ),
        isNull,
        reason: '槽位 AAD 绑定笔记本 ID——不可跨笔记本解包',
      );
    });

    test('改密保留 media 槽：K_note 不变（LUKS 语义）', () async {
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-k1',
        plaintext: 'x',
        password: pw,
      );
      final before = await enc.unwrapNotebookMediaKey(
        notebookId: 'nb-k1',
        encryptedJson: envelope,
        password: pw,
      );
      final changed = await enc.changeNotebookPasswordV5(
        notebookId: 'nb-k1',
        encryptedJson: envelope,
        oldPassword: pw,
        newPassword: 'new-pw-2',
      );
      expect(EncryptionService.hasMediaSlotV5(changed), isTrue);
      final after = await enc.unwrapNotebookMediaKey(
        notebookId: 'nb-k1',
        encryptedJson: changed,
        password: 'new-pw-2',
      );
      expect(after, before, reason: '改密只重绕 pw 槽——K_note 不动');
    });

    test('attachNotebookMediaKey：补装后可解包；幂等不覆盖', () async {
      // 手工构造无 media 槽的 v5 信封（模拟懒补场景）。
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-k1',
        plaintext: 'x',
        password: pw,
      );
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      (map['slots'] as Map<String, dynamic>).remove('media');
      final bare = jsonEncode(map);
      expect(EncryptionService.hasMediaSlotV5(bare), isFalse);
      expect(
        await enc.unwrapNotebookMediaKey(
          notebookId: 'nb-k1',
          encryptedJson: bare,
          password: pw,
        ),
        isNull,
      );

      final key = MediaCryptoService.generateNotebookKey();
      final attached = await enc.attachNotebookMediaKey(
        notebookId: 'nb-k1',
        encryptedJson: bare,
        password: pw,
        mediaKey: key,
      );
      expect(EncryptionService.hasMediaSlotV5(attached), isTrue);
      expect(
        await enc.unwrapNotebookMediaKey(
          notebookId: 'nb-k1',
          encryptedJson: attached,
          password: pw,
        ),
        key,
      );
      // 幂等：已有槽再 attach 不覆盖。
      final again = await enc.attachNotebookMediaKey(
        notebookId: 'nb-k1',
        encryptedJson: attached,
        password: pw,
        mediaKey: MediaCryptoService.generateNotebookKey(),
      );
      expect(again, attached);
    });
  });

  group('NotebookStorage.ensureNotebookMediaKey（存储层）', () {
    late Directory tempDir;
    late NotebookStorage storage;
    late MediaCryptoService media;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nb_knote_');
      media = MediaCryptoService.instance;
      media.clearSessionKey();
      storage = NotebookStorage(
        directoryProvider: () async => tempDir,
        mediaCrypto: media,
      );
    });

    tearDown(() async {
      media.clearSessionKey();
      await deleteTempDirWithRetry(tempDir);
    });

    Notebook nb(String id) => Notebook(id: id, title: 'K_note 测试本');

    test('设密后 ensure：media 槽已在信封，密钥注入并可加解密', () async {
      final notebook = nb('nb-s1');
      await storage.encryptAndSave(notebook, pw);
      await storage.ensureNotebookMediaKey('nb-s1');
      expect(media.hasKeyFor('nb-s1'), isTrue);
      final plain = Uint8List.fromList(utf8.encode('媒体字节'));
      final sealed = await media.encryptFile('nb-s1', plain);
      expect(await media.readMediaFile('nb-s1', sealed), plain);
    });

    test('懒补槽：无 media 槽的旧 v5 信封 → 补装并持久化', () async {
      // 手工落一个无 media 槽的 v5 加密笔记本。
      final notebook = nb('nb-s2');
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-s2',
        plaintext: '{"pages":[]}',
        password: pw,
      );
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      (map['slots'] as Map<String, dynamic>).remove('media');
      notebook.encryptedPayload = jsonEncode(map);
      notebook.encrypted = true;
      await storage.save(notebook);

      // 会话密码缓存（模拟解锁）后 ensure → 懒补槽。
      expect(await storage.verifyNotebookPassword('nb-s2', pw), isTrue);
      await storage.ensureNotebookMediaKey('nb-s2');
      expect(media.hasKeyFor('nb-s2'), isTrue);

      // 持久化验证：重新 load 的信封已含 media 槽，且解包出的密钥与驻留一致。
      final reloaded = await storage.load('nb-s2');
      expect(
        EncryptionService.hasMediaSlotV5(reloaded!.encryptedPayload!),
        isTrue,
        reason: '懒补槽必须落盘——跨会话仍可解包',
      );
      final unwrapped = await enc.unwrapNotebookMediaKey(
        notebookId: 'nb-s2',
        encryptedJson: reloaded.encryptedPayload!,
        password: pw,
      );
      expect(unwrapped, isNotNull);
      // 用解包密钥可解驻留密钥加密的媒体（同一把 K_note）。
      final plain = Uint8List.fromList(utf8.encode('懒补媒体'));
      final sealed = await media.encryptFile('nb-s2', plain);
      media.clearNotebookKey('nb-s2');
      media.setNotebookKey('nb-s2', unwrapped!);
      expect(await media.readMediaFile('nb-s2', sealed), plain);
    });

    test('无会话密码且信封无槽 → VaultFileLockException（fail-closed）', () async {
      final notebook = nb('nb-s3');
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-s3',
        plaintext: '{"pages":[]}',
        password: pw,
      );
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      (map['slots'] as Map<String, dynamic>).remove('media');
      notebook.encryptedPayload = jsonEncode(map);
      notebook.encrypted = true;
      await storage.save(notebook);
      // 不缓存密码 → ensure 必须拒绝（不得明文降级）。
      await expectLater(
        storage.ensureNotebookMediaKey('nb-s3'),
        throwsA(isA<VaultFileLockException>()),
      );
    });

    test('明文笔记本 ensure → 无操作（不注入密钥）', () async {
      final notebook = nb('nb-s4');
      await storage.save(notebook);
      await storage.ensureNotebookMediaKey('nb-s4');
      expect(media.hasKeyFor('nb-s4'), isFalse);
    });

    test('跨笔记本隔离：两本各自 K_note，密文互不可解', () async {
      await storage.encryptAndSave(nb('nb-a'), pw);
      await storage.encryptAndSave(nb('nb-b'), pw);
      await storage.ensureNotebookMediaKey('nb-a');
      await storage.ensureNotebookMediaKey('nb-b');
      final plain = Uint8List.fromList(utf8.encode('笔记本A的媒体'));
      final sealedA = await media.encryptFile('nb-a', plain);
      await expectLater(
        media.readMediaFile('nb-b', sealedA),
        throwsA(anything),
        reason: 'AAD 绑定笔记本——跨本解密必须失败',
      );
      expect(await media.readMediaFile('nb-a', sealedA), plain);
    });
  });
}