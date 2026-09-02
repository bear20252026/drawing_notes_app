/// N4 批 2：v3 双保护器信封（StorageService 层）回归测试。
///
/// 覆盖：v3 设密/验密/改密/绑定重置盘/重置盘重置、DEK 会话续用
/// （续写不失效 USB 槽位——LUKS 槽位语义）、v2 → v3 改密自动升级、
/// 冷实例（重启语义）锁定占位与跨实例续写。
///
/// 注：setFilePassword/changeFilePassword 等走生产默认 600k PBKDF2
/// （无迭代注入点），全量套件高并发下会超出默认 30s 单测超时——
/// 放宽到 3 分钟（全量跑实测单条 5–15s）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_password_v3_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
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

  /// 构造文档的明文落盘字节（与 StorageService.save 的编码一致）：
  /// 经无密钥临时实例落明文再读回，避免依赖 codec 细节。
  Future<Uint8List> documentBytes(DrawingDocument d) async {
    final temp = await Directory.systemTemp.createTemp('v3_doc_bytes_');
    try {
      final s = StorageService(
        directoryProvider: () async => temp,
        keyProvider: null,
      );
      await s.save(d);
      return await File(
        '${temp.path}${Platform.pathSeparator}documents'
        '${Platform.pathSeparator}${d.id}.json',
      ).readAsBytes();
  } finally {
    // Windows 下句柄释放可能有延迟——删除失败忽略（系统临时目录自行回收）。
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  }
  }

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

  test('设密绑盘：USB 槽位嵌入；会话续写（save）不失效槽位（DEK 稳定）',
      () async {
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

  test('重置盘重置：免旧密码换新密码；旧密码失效；错钥 fail-closed',
      () async {
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
    expect(metas.first.title, '加密画布');
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

  test('修改密码（v2 旧文件）：自动升级为 v3（暂无槽位，可事后绑定）', () async {
    final storage = storageWith(VaultKeyService.randomBytes(32));
    // 手工落一个 v2 信封（模拟 v1.5.x 旧数据——用真实文档明文字节）。
    final plain = await documentBytes(doc('v3_doc6', '机密画作F'));
    final realV2 = await VaultFileCodec.encryptWithPassword(
      plain,
      '777888',
      aadContext: 'doc:v3_doc6',
      iterations: 1000,
    );
    await Directory(
      '${tempDir.path}${Platform.pathSeparator}documents',
    ).create(recursive: true);
    await File(docPath('v3_doc6')).writeAsBytes(realV2, flush: true);

    // 修改密码 → 自动升级 v3。
    storage.cacheFilePassword('v3_doc6', '777888');
    await storage.changeFilePassword('v3_doc6', '777888', '123321');
    final bytes = await File(docPath('v3_doc6')).readAsBytes();
    expect(VaultFileCodec.isV3Envelope(bytes), isTrue);
    expect(await storage.hasFileUsbSlot('v3_doc6'), isFalse);
    expect(await storage.verifyFilePassword('v3_doc6', '777888'), isFalse);
    expect(await storage.verifyFilePassword('v3_doc6', '123321'), isTrue);

    // 升级后可事后绑定重置盘。
    final key = diskKey();
    await storage.bindFileUsbSlot('v3_doc6', '123321', key);
    expect(await storage.hasFileUsbSlot('v3_doc6'), isTrue);
    expect(
      await storage.resetFilePasswordWithUsb('v3_doc6', key, '321123'),
      isTrue,
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

  test('v3 会话密钥材料随 forgetFilePassword 清除（removeFilePassword 路径）',
      () async {
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
