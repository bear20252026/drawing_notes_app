/// N4 批 2：v3 双保护器信封（StorageService 层）回归测试。
///
/// 覆盖：v3 设密/验密/改密/绑定重置盘/重置盘重置、DEK 会话续用
/// （续写不失效 USB 槽位——LUKS 槽位语义）、v2 → v3 改密自动升级、
/// 冷实例（重启语义）锁定占位与跨实例续写。
///
/// 注：批B 起新槽位默认 Argon2id（64MiB t2 p2）——测试注入轻量参数
/// （KdfParams.testLight），槽位格式与生产一致；放宽超时到 5 分钟
/// （原 3 分钟，AGENTS 约定值）——满负载全量套件下多套件真 KDF 并行
/// 排队曾把 3 分钟击穿（2026-09-24 懒迁移降噪专项，本机实测偶发）。
@Tags(["kdf"])
@Timeout(Duration(minutes: 5))
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
  // 批B：注入测试轻量 KDF（新槽位派生几十 ms；生产默认 Argon2id 64MiB）。
  KdfParams.newSlotDefault = KdfParams.testLight;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_password_v3_');
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

  Uint8List diskKey() => VaultKeyService.randomBytes(32);

  test('设密（不绑盘）：v3 信封、验密/读取/列表正常、无 USB 槽', () async {
    final storage = storageWith(VaultKeyService.randomBytes(32));
    await storage.save(doc('v3_doc1', '机密画作A'));

    await storage.setFilePassword('v3_doc1', '864213');

    final bytes = await File(docPath('v3_doc1')).readAsBytes();
    expect(VaultFileCodec.isV3Envelope(bytes), isTrue);
    expect(VaultFileCodec.hasUsbSlotV3(bytes), isFalse);
    expect(await storage.hasFileUsbSlot('v3_doc1'), isFalse);

    expect(await storage.verifyFilePassword('v3_doc1', '000000'), isFalse);
    expect(await storage.verifyFilePassword('v3_doc1', '864213'), isTrue);
    expect(storage.filePasswordFor('v3_doc1'), '864213');

    final loaded = await storage.load('v3_doc1');
    expect(loaded?.title, '机密画作A');
    final metas = await storage.listDocuments();
    expect(metas.first.locked, isFalse);
    expect(metas.first.title, '机密画作A');
  });

  test('设密绑盘：USB 槽位嵌入；会话续写（save）不失效槽位（DEK 稳定）', () async {
    final storage = storageWith(VaultKeyService.randomBytes(32));
    await storage.save(doc('v3_doc2', '机密画作B'));

    final key = diskKey();
    await storage.setFilePassword('v3_doc2', '159357', resetDiskKey: key);
    expect(await storage.hasFileUsbSlot('v3_doc2'), isTrue);

    // 关键语义：会话内继续编辑保存（走 _sealDocBytes）→ DEK 复用 →
    // USB 槽位跨保存持续有效（否则每次保存都会作废重置盘）。
    final loaded = await storage.load('v3_doc2');
    loaded!.title = '机密画作B·改';
    await storage.save(loaded);
    expect(await storage.hasFileUsbSlot('v3_doc2'), isTrue);
    final bytes = await File(docPath('v3_doc2')).readAsBytes();
    expect(VaultFileCodec.isV3Envelope(bytes), isTrue);
  });

  test('重置盘重置：免旧密码换新密码；旧密码失效；错钥 fail-closed', () async {
    final storage = storageWith(VaultKeyService.randomBytes(32));
    await storage.save(doc('v3_doc3', '机密画作C'));
    final key = diskKey();
    await storage.setFilePassword('v3_doc3', '111222', resetDiskKey: key);

    // 错误钥匙 → false，文件与会话均未被改动。
    expect(
      await storage.resetFilePasswordWithUsb('v3_doc3', diskKey(), '333444'),
      isFalse,
    );
    expect(await storage.verifyFilePassword('v3_doc3', '111222'), isTrue);

    // 正确钥匙 → 重置成功，新密码入会话可直接读。
    expect(
      await storage.resetFilePasswordWithUsb('v3_doc3', key, '333444'),
      isTrue,
    );
    expect(storage.filePasswordFor('v3_doc3'), '333444');
    final loaded = await storage.load('v3_doc3');
    expect(loaded?.title, '机密画作C');
    expect(await storage.verifyFilePassword('v3_doc3', '111222'), isFalse);
    // 重置后槽位仍在（U 盘继续有效）。
    expect(await storage.hasFileUsbSlot('v3_doc3'), isTrue);
  });

  test('冷实例（重启语义）：锁定占位 → 验密解锁 → 续写保槽位', () async {
    final key = VaultKeyService.randomBytes(32);
    final writer = storageWith(key);
    await writer.save(doc('v3_doc4', '机密画作D'));
    final disk = diskKey();
    await writer.setFilePassword('v3_doc4', '456789', resetDiskKey: disk);

    // 冷实例：无会话密码 → 锁定占位 + load 拒绝。
    final cold = storageWith(key);
    final metas = await cold.listDocuments();
    expect(metas.first.locked, isTrue);
    expect(metas.first.title, ''); // L-04：锁定占位不产出标题（展示层统一渲染）
    await expectLater(
      cold.load('v3_doc4'),
      throwsA(isA<VaultFilePasswordLockException>()),
    );

    // 冷实例验密成功 → DEK/槽位入会话 → 读取与续写正常且槽位保留。
    expect(await cold.verifyFilePassword('v3_doc4', '456789'), isTrue);
    final loaded = await cold.load('v3_doc4');
    expect(loaded?.title, '机密画作D');
    loaded!.title = '机密画作D·冷改';
    await cold.save(loaded);
    expect(await cold.hasFileUsbSlot('v3_doc4'), isTrue);
  });

  test('修改密码（v3）：DEK 与 USB 槽位保留，新密码生效', () async {
    final storage = storageWith(VaultKeyService.randomBytes(32));
    await storage.save(doc('v3_doc5', '机密画作E'));
    final key = diskKey();
    await storage.setFilePassword('v3_doc5', '111222', resetDiskKey: key);

    await expectLater(
      storage.changeFilePassword('v3_doc5', 'wrong-old', '333444'),
      throwsA(isA<VaultFileException>()),
    );
    await storage.changeFilePassword('v3_doc5', '111222', '333444');
    expect(await storage.verifyFilePassword('v3_doc5', '111222'), isFalse);
    expect(await storage.verifyFilePassword('v3_doc5', '333444'), isTrue);
    expect(await storage.hasFileUsbSlot('v3_doc5'), isTrue);
    // 改密后重置盘仍可重置。
    expect(
      await storage.resetFilePasswordWithUsb('v3_doc5', key, '555666'),
      isTrue,
    );
  });

  // M-06 收口（2026-11-14，删除旧版加密支持）：v2 旧文件不再可解/改密——
  // fail-closed 拒绝（删除旧版读支持后不再自动升级）。
  test('v2 旧文件：改密拒绝、验证返回 false（删除旧版支持，fail-closed）', () async {
    final storage = storageWith(VaultKeyService.randomBytes(32));
    // 手工落一个 v2 信封字节（DNV + 0x02 + salt(16) + iter(4) + 载荷占位）。
    final salt = List<int>.generate(16, (i) => i);
    final iter = ByteData(4)..setUint32(0, 600000);
    final realV2 = Uint8List.fromList([
      0x44, 0x4E, 0x56, 0x02,
      ...salt,
      ...iter.buffer.asUint8List(),
      ...List<int>.generate(48, (i) => i),
    ]);
    await Directory(
      '${tempDir.path}${Platform.pathSeparator}documents',
    ).create(recursive: true);
    await File(docPath('v3_doc6')).writeAsBytes(realV2, flush: true);

    // v2 旧文件：验证返回 false（不可读），改密 fail-closed 拒绝。
    storage.cacheFilePassword('v3_doc6', '777888');
    expect(await storage.verifyFilePassword('v3_doc6', '777888'), isFalse);
    await expectLater(
      storage.changeFilePassword('v3_doc6', '777888', '123321'),
      throwsA(isA<VaultFileException>()),
      reason: '旧版 v2 不再支持，fail-closed 拒绝',
    );
  });

  test('事后绑定：须验证文件密码；错密码拒绝；重复绑定拒绝', () async {
    final storage = storageWith(VaultKeyService.randomBytes(32));
    await storage.save(doc('v3_doc7', '机密画作G'));
    await storage.setFilePassword('v3_doc7', '741258');

    // 错密码 → VaultFileException（verify 语义）。
    await expectLater(
      storage.bindFileUsbSlot('v3_doc7', '000000', diskKey()),
      throwsA(isA<VaultFileException>()),
    );

    final key = diskKey();
    await storage.bindFileUsbSlot('v3_doc7', '741258', key);
    expect(await storage.hasFileUsbSlot('v3_doc7'), isTrue);

    await expectLater(
      storage.bindFileUsbSlot('v3_doc7', '741258', diskKey()),
      throwsA(isA<StateError>()),
    );
    // 绑定后重置通道可用。
    expect(
      await storage.resetFilePasswordWithUsb('v3_doc7', key, '852963'),
      isTrue,
    );
  });

  test('重置后冷实例续写：DEK 跨实例恢复（verify 时从信封解出）', () async {
    final storage = storageWith(VaultKeyService.randomBytes(32));
    await storage.save(doc('v3_doc8', '机密画作H'));
    final key = diskKey();
    await storage.setFilePassword('v3_doc8', '123456', resetDiskKey: key);
    await storage.resetFilePasswordWithUsb('v3_doc8', key, '654321');

    // 冷实例验密（从密码槽解 DEK）→ 续写保槽位。
    final cold = storageWith(VaultKeyService.randomBytes(32));
    expect(await cold.verifyFilePassword('v3_doc8', '654321'), isTrue);
    final loaded = await cold.load('v3_doc8');
    expect(loaded?.title, '机密画作H');
    loaded!.title = '机密画作H·冷续写';
    await cold.save(loaded);
    expect(await cold.hasFileUsbSlot('v3_doc8'), isTrue);
  });

  test('v3 会话密钥材料随 forgetFilePassword 清除（removeFilePassword 路径）', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = storageWith(key);
    await storage.save(doc('v3_doc9', '机密画作I'));
    await storage.setFilePassword('v3_doc9', '135791', resetDiskKey: diskKey());
    expect(await storage.verifyFilePassword('v3_doc9', '135791'), isTrue);
    expect(storage.filePasswordFor('v3_doc9'), isNotNull);

    await storage.removeFilePassword('v3_doc9', '135791');
    expect(storage.filePasswordFor('v3_doc9'), isNull);
    final bytes = await File(docPath('v3_doc9')).readAsBytes();
    expect(VaultFileCodec.isPasswordEnvelope(bytes), isFalse); // 回封 v1
    expect(VaultFileCodec.isEncrypted(bytes), isTrue);
    final loaded = await storage.load('v3_doc9');
    expect(loaded?.title, '机密画作I');
  });
}
