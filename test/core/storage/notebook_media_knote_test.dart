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
import 'package:drawing_notes_app/core/security/notebook_media_keys.dart';
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

    test('错误密码/跨笔记本解包 → FormatException（三态契约，H-2）', () async {
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-k1',
        plaintext: 'x',
        password: pw,
      );
      // 三态契约（框架级收口 2026-11-15）：错密码/槽损坏抛 FormatException，
      // 绝不返回 null 与「无槽」混淆（防懒补生成未持久化临时密钥）。
      await expectLater(
        enc.unwrapNotebookMediaKey(
          notebookId: 'nb-k1',
          encryptedJson: envelope,
          password: 'wrong-pw',
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        enc.unwrapNotebookMediaKey(
          notebookId: 'nb-other',
          encryptedJson: envelope,
          password: pw,
        ),
        throwsA(isA<FormatException>()),
        reason: '槽位 AAD 绑定笔记本 ID——不可跨笔记本解包',
      );
    });

    test('media 槽损坏（篡改密文）→ FormatException，不得当无槽（H-2）', () async {
      final envelope = await enc.encryptWithPasswordV5(
        notebookId: 'nb-k1',
        plaintext: 'x',
        password: pw,
      );
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      final media = (map['slots'] as Map<String, dynamic>)['media']
          as Map<String, dynamic>;
      // 翻转包裹密文首字节——AEAD 认证必失败（槽存在但损坏）。
      final wrapped = base64Decode(media['w'] as String);
      wrapped[0] ^= 0xFF;
      media['w'] = base64Encode(wrapped);
      await expectLater(
        enc.unwrapNotebookMediaKey(
          notebookId: 'nb-k1',
          encryptedJson: jsonEncode(map),
          password: pw,
        ),
        throwsA(isA<FormatException>()),
        reason: '槽损坏必须 fail-closed——返回 null 会触发懒补临时密钥（数据丢失）',
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

  group('NotebookStorage.ensureNotebookMediaKey（存储层——经编排器）', () {
    late Directory tempDir;
    late NotebookStorage storage;
    late MediaCryptoService media;
    late NotebookMediaKeys keys;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nb_knote_');
      media = MediaCryptoService.instance;
      media.clearSessionKey();
      // 框架级收口（2026-11-15）：以真实存储为信封端口装配编排器并注入
      // （与生产 app.dart 同一装配形状）——ensure 委托编排器。late 闭包
      // 端口引用最终 storage（单实例，避免双构造的会话口令表分裂）。
      keys = NotebookMediaKeys(
        media: media,
        envelopes: _LateEnvelopePort(() => storage),
      );
      storage = NotebookStorage(
        directoryProvider: () async => tempDir,
        mediaCrypto: media,
        mediaKeys: keys,
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

/// 延迟绑定信封端口（测试装配用）：编排器先于存储构造时，经闭包引用
/// 最终存储实例——与生产 app.dart 的 late final 初始化器同一语义。
class _LateEnvelopePort implements NotebookMediaEnvelopePort {
  _LateEnvelopePort(this._resolve);
  final NotebookStorage Function() _resolve;

  @override
  Future<bool> isEncryptedNotebook(String notebookId) =>
      _resolve().isEncryptedNotebook(notebookId);

  @override
  Future<String?> sessionPassword(String notebookId) =>
      _resolve().sessionPassword(notebookId);

  @override
  Future<List<int>?> unwrapMediaKey(String notebookId, String password) =>
      _resolve().unwrapMediaKey(notebookId, password);

  @override
  Future<void> attachMediaSlot(
    String notebookId,
    String password,
    List<int> mediaKey,
  ) => _resolve().attachMediaSlot(notebookId, password, mediaKey);
}