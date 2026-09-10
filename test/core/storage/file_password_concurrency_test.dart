/// E-17 并发回归测试：单文件密码读-改-写 API 与 save 共享同一
/// per-document 独占队列（[_runDocExclusive]）。
///
/// 验证：
/// - save 与 set/change/remove 交错时按请求顺序串行，落盘为最新内容
///   （密码重封不会以陈旧明文覆盖新保存）；
/// - 改密/移密失败后旧文件仍可读、会话缓存与磁盘一致。
///
/// 批B 起新槽位默认 Argon2id——测试注入轻量参数（KdfParams.testLight），
/// 槽位格式与生产一致；放宽超时到 3 分钟。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/temp_dir_cleanup.dart';

void main() {
  // 测试轻量 KDF（新槽位 Argon2id 8MiB≈几十 ms；格式与生产一致）。
  KdfParams.newSlotDefault = KdfParams.testLight;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fp_concurrency_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  String docPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}$id.json';

  StorageService storageWith(Uint8List? key) => StorageService(
    directoryProvider: () async => tempDir,
    keyProvider: key == null ? null : () async => key,
  );

  DrawingDocument doc(String id, String title) =>
      DrawingDocument(id: id, title: title);

  Uint8List shellBytes(StorageService s, String id) =>
      File(docPath(id)).readAsBytesSync();

  test('并发交错：save 与 setFilePassword 同时请求 → 串行，最终为最新内容', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('cc_doc1', 'v0'));

    // 同一步骤内按请求顺序入队：save 先、set 后，队列强迫二者串行。
    final saveF = storage.save(doc('cc_doc1', 'v1'));
    final setF = storage.setFilePassword('cc_doc1', 'pw1');
    await Future.wait([saveF, setF]);

    // 落盘为密码信封，且是新保存的 v1 内容（set 不是覆盖陈旧明文）。
    final bytes = shellBytes(storage, 'cc_doc1');
    expect(VaultFileCodec.isPasswordEnvelope(bytes), isTrue);
    expect(await storage.verifyFilePassword('cc_doc1', 'pw1'), isTrue);
    expect((await storage.load('cc_doc1'))?.title, 'v1');
  });

  test('并发交错：save 与 changeFilePassword 同时请求 → 最新内容 + 新密生效', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('cc_doc2', 'v0'));
    await storage.setFilePassword('cc_doc2', 'pw-a');

    // change 与 save 交错：change 在队列内读取最新已落盘 v1 再重封。
    final saveF = storage.save(doc('cc_doc2', 'v1'));
    final changeF = storage.changeFilePassword('cc_doc2', 'pw-a', 'pw-b');
    await Future.wait([saveF, changeF]);

    expect(await storage.verifyFilePassword('cc_doc2', 'pw-a'), isFalse);
    expect(await storage.verifyFilePassword('cc_doc2', 'pw-b'), isTrue);
    expect((await storage.load('cc_doc2'))?.title, 'v1');
  });

  test('并发交错：save 与 removeFilePassword 同时请求 → 最终回封 v1 主密钥信封', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('cc_doc3', 'v0'));
    await storage.setFilePassword('cc_doc3', 'pw');

    // remove 在队列内读取最新已落盘 v1 后回封主密钥信封。
    final saveF = storage.save(doc('cc_doc3', 'v1'));
    final removeF = storage.removeFilePassword('cc_doc3', 'pw');
    await Future.wait([saveF, removeF]);

    // 密码已移除：非密码信封，仅主密钥解出；会话缓存已清除。
    final bytes = shellBytes(storage, 'cc_doc3');
    expect(VaultFileCodec.isPasswordEnvelope(bytes), isFalse);
    expect(VaultFileCodec.isEncrypted(bytes), isTrue);
    expect(storage.filePasswordFor('cc_doc3'), isNull);
    expect((await storage.load('cc_doc3'))?.title, 'v1');
  });

  test('失败语义：changeFilePassword 密码错误 → 旧文件仍可读、缓存保持旧密一致', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('cc_doc4', '机密'));
    await storage.setFilePassword('cc_doc4', 'old-pw');

    await expectLater(
      storage.changeFilePassword('cc_doc4', 'wrong', 'new-pw'),
      throwsA(isA<VaultFileException>()),
    );

    // 失败未破坏旧缓存；旧文件仍可凭正确旧密码读取。
    expect(storage.filePasswordFor('cc_doc4'), 'old-pw');
    expect(await storage.verifyFilePassword('cc_doc4', 'old-pw'), isTrue);
    expect((await storage.load('cc_doc4'))?.title, '机密');
  });

  test('失败语义：removeFilePassword 密码错误 → 仍为密码信封、旧文件可读、缓存一致', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('cc_doc5', '机密'));
    await storage.setFilePassword('cc_doc5', 'pw');

    await expectLater(
      storage.removeFilePassword('cc_doc5', 'wrong'),
      throwsA(isA<VaultFileException>()),
    );

    // 失败后仍是密码信封（未回明文），缓存仍为旧密码。
    expect(
      VaultFileCodec.isPasswordEnvelope(
        await File(docPath('cc_doc5')).readAsBytes(),
      ),
      isTrue,
    );
    expect(storage.filePasswordFor('cc_doc5'), 'pw');
    expect(await storage.verifyFilePassword('cc_doc5', 'pw'), isTrue);
    expect((await storage.load('cc_doc5'))?.title, '机密');
  });
}
