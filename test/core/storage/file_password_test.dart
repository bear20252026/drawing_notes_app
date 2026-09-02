/// 批次②：单文件密码（StorageService 层）回归测试。
///
/// 覆盖：设密/改密/验密/移除、会话缓存语义、锁定列表占位、
/// 缩略图抑制（隐藏缩略图——用户拍板）、删除清理。
///
/// 注：批B 起新槽位默认 Argon2id（64MiB t2 p2）——测试注入轻量参数
/// （KdfParams.testLight），槽位格式与生产一致；仍放宽超时到 3 分钟。
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

void main() {
  // 批B：注入测试轻量 KDF（新槽位 Argon2id 8MiB≈几十 ms；生产默认
  // 64MiB t2 p2）。槽位 JSON 格式与生产完全一致，仅参数不同。
  KdfParams.newSlotDefault = KdfParams.testLight;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_password_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String docPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}$id.json';

  String thumbPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}thumbnails'
      '${Platform.pathSeparator}$id.png';

  StorageService storageWith(Uint8List? key) => StorageService(
    directoryProvider: () async => tempDir,
    keyProvider: key == null ? null : () async => key,
  );

  DrawingDocument doc(String id, String title) =>
      DrawingDocument(id: id, title: title);

  test('设密流程：v1 → v2 信封；错误密码拒绝；正确密码缓存后可读可列表', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('fp_doc1', '机密画作A'));

    await storage.setFilePassword('fp_doc1', '864213');

    final bytes = await File(docPath('fp_doc1')).readAsBytes();
    expect(VaultFileCodec.isPasswordEnvelope(bytes), isTrue);

    // 错误密码拒绝；正确密码入会话缓存。
    expect(await storage.verifyFilePassword('fp_doc1', '000000'), isFalse);
    expect(await storage.verifyFilePassword('fp_doc1', '864213'), isTrue);
    expect(storage.filePasswordFor('fp_doc1'), '864213');

    // 会话缓存生效：读取与列表均正常（会话内记住——用户拍板）。
    final loaded = await storage.load('fp_doc1');
    expect(loaded?.title, '机密画作A');
    final metas = await storage.listDocuments();
    expect(metas, hasLength(1));
    expect(metas.first.locked, isFalse);
    expect(metas.first.title, '机密画作A');
  });

  test('锁定占位：新实例（无会话密码）列表返回 locked 元信息，load 拒绝，缩略图为 null', () async {
    final key = VaultKeyService.randomBytes(32);
    final writer = storageWith(key);
    await writer.save(doc('fp_doc2', '机密画作B'));
    await writer.setFilePassword('fp_doc2', '159357');

    // 全新实例：会话密码缓存不共享（重启/切后台即失效的语义）。
    final cold = storageWith(key);
    expect(await cold.isFilePasswordProtected('fp_doc2'), isTrue);

    final metas = await cold.listDocuments();
    expect(metas, hasLength(1));
    expect(metas.first.locked, isTrue);
    expect(metas.first.id, 'fp_doc2');
    expect(metas.first.title, '加密画布'); // 不暴露真实标题

    await expectLater(
      cold.load('fp_doc2'),
      throwsA(isA<VaultFilePasswordLockException>()),
    );
    expect(await cold.thumbnailBytes('fp_doc2'), isNull);
  });

  test('缩略图抑制：有会话密码时 saveThumbnail 直接跳过（不落盘）', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('fp_doc3', '机密画作C'));
    await storage.setFilePassword('fp_doc3', '741258');

    final written = await storage.saveThumbnail(
      'fp_doc3',
      Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
    );
    expect(written, '');
  });

  test('修改密码：旧密码错误拒绝；正确后新密码生效旧密码失效', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('fp_doc4', '机密画作D'));
    await storage.setFilePassword('fp_doc4', '111222');

    await expectLater(
      storage.changeFilePassword('fp_doc4', 'wrong-old', '333444'),
      throwsA(isA<VaultFileException>()),
    );

    await storage.changeFilePassword('fp_doc4', '111222', '333444');
    expect(await storage.verifyFilePassword('fp_doc4', '111222'), isFalse);
    expect(await storage.verifyFilePassword('fp_doc4', '333444'), isTrue);
  });

  test('移除密码：保险库锁定时拒绝（fail-closed 绝不回明文）；解锁后回封 v1', () async {
    final key = VaultKeyService.randomBytes(32);
    final writer = storageWith(key);
    await writer.save(doc('fp_doc5', '机密画作E'));
    await writer.setFilePassword('fp_doc5', '456789');

    // 锁定保险库的存储实例：移除必须被拒绝。
    final locked = storageWith(null);
    locked.cacheFilePassword('fp_doc5', '456789');
    await expectLater(
      locked.removeFilePassword('fp_doc5', '456789'),
      throwsA(isA<VaultFileLockException>()),
    );
    // 拒绝后文件仍是 v2（不是明文）。
    expect(
      VaultFileCodec.isPasswordEnvelope(
        await File(docPath('fp_doc5')).readAsBytes(),
      ),
      isTrue,
    );

    // 解锁状态：回封 v1，之后仅凭主密钥可读。
    await writer.verifyFilePassword('fp_doc5', '456789');
    await writer.removeFilePassword('fp_doc5', '456789');
    final bytes = await File(docPath('fp_doc5')).readAsBytes();
    expect(VaultFileCodec.isPasswordEnvelope(bytes), isFalse);
    expect(VaultFileCodec.isEncrypted(bytes), isTrue);
    final loaded = await writer.load('fp_doc5');
    expect(loaded?.title, '机密画作E');
  });

  test('删除文档：会话文件密码同步清除', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('fp_doc6', '机密画作F'));
    await storage.setFilePassword('fp_doc6', '123321');
    expect(storage.filePasswordFor('fp_doc6'), isNotNull);

    await storage.delete('fp_doc6');
    expect(storage.filePasswordFor('fp_doc6'), isNull);
  });

  test('设密后删除缩略图文件（隐藏缩略图——卡片显示锁形占位）', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('fp_doc7', '机密画作G'));
    // 手工放一个缩略图文件（模拟此前保存过的缩略图）。
    final thumb = File(thumbPath('fp_doc7'));
    await thumb.parent.create(recursive: true);
    await thumb.writeAsBytes(<int>[1, 2, 3], flush: true);

    await storage.setFilePassword('fp_doc7', '987654');
    expect(await thumb.exists(), isFalse);
  });
}
