import 'dart:convert';
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
    tempDir = await Directory.systemTemp.createTemp('storage_encrypt_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String docPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}$id.json';

  DrawingDocument doc(String id, String title) =>
      DrawingDocument(id: id, title: title);

  Future<Uint8List> waitEncrypted(String id) async {
    // 懒迁移走异步写尾队列：轮询等待落盘（上限 ~2s，防死等）。
    final file = File(docPath(id));
    for (var i = 0; i < 200; i++) {
      final bytes = await file.readAsBytes();
      if (VaultFileCodec.isEncrypted(bytes)) return bytes;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('2 秒内明文未被迁移为密文');
  }

  test('有主密钥时保存 → 磁盘为 DNV 密文，无明文标题泄露；读取/列表正常', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = StorageService(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );

    await storage.save(doc('enc_doc1', '机密画作标题'));

    final bytes = await File(docPath('enc_doc1')).readAsBytes();
    expect(VaultFileCodec.isEncrypted(bytes), isTrue);
    expect(
      utf8.decode(bytes, allowMalformed: true).contains('机密画作标题'),
      isFalse,
      reason: '磁盘上不得出现明文标题',
    );

    final loaded = await storage.load('enc_doc1');
    expect(loaded?.id, 'enc_doc1');
    expect(loaded?.title, '机密画作标题');

    final metas = await storage.listDocuments();
    expect(metas, hasLength(1));
    expect(metas.first.title, '机密画作标题');
  });

  test('懒迁移：旧明文文档在读取时自动重写为密文（Joplin 模式）', () async {
    // 先用无密钥存储写出明文（模拟升级前旧数据）。
    final legacy = StorageService(directoryProvider: () async => tempDir);
    await legacy.save(doc('legacy_doc', '升级前旧文档'));
    expect(
      VaultFileCodec.isEncrypted(
        await File(docPath('legacy_doc')).readAsBytes(),
      ),
      isFalse,
    );

    // 换成有密钥的存储读取 → 明文应被自动重写为密文。
    final key = VaultKeyService.randomBytes(32);
    final upgraded = StorageService(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    final loaded = await upgraded.load('legacy_doc');
    expect(loaded?.title, '升级前旧文档');

    final bytes = await waitEncrypted('legacy_doc');
    expect(
      utf8.decode(bytes, allowMalformed: true).contains('升级前旧文档'),
      isFalse,
    );

    // 迁移后仍可正常读取（无数据损失）。
    final reloaded = await upgraded.load('legacy_doc');
    expect(reloaded?.title, '升级前旧文档');
  });

  test('锁定状态读加密文档 → VaultFileLockException（fail-closed 不回退）', () async {
    final key = VaultKeyService.randomBytes(32);
    final writer = StorageService(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    await writer.save(doc('locked_doc', '锁定内容'));

    final lockedReader = StorageService(
      directoryProvider: () async => tempDir,
      keyProvider: () async => null, // 保险库锁定
    );
    await expectLater(
      lockedReader.load('locked_doc'),
      throwsA(isA<VaultFileLockException>()),
    );
    // 列表同样 fail-closed：加密文档被跳过，不暴露任何元信息。
    expect(await lockedReader.listDocuments(), isEmpty);
  });

  test('密文被篡改 → 读取抛 VaultFileException（拒载，不静默降级）', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = StorageService(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    await storage.save(doc('tampered_doc', '将被篡改'));

    final file = File(docPath('tampered_doc'));
    final bytes = await file.readAsBytes();
    bytes[bytes.length - 3] ^= 0x5A; // 翻转密文尾部比特
    await file.writeAsBytes(bytes, flush: true);

    await expectLater(
      storage.load('tampered_doc'),
      throwsA(isA<VaultFileException>()),
    );
  });

  test('加密文档可正常删除（含资产引用扫描路径）', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = StorageService(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    await storage.save(doc('deletable', '待删除'));
    expect(await storage.delete('deletable'), isTrue);
    expect(await File(docPath('deletable')).exists(), isFalse);
  });

  test('列表页懒迁移：明文旧文档在首页刷新时被批量重写为密文', () async {
    final legacy = StorageService(directoryProvider: () async => tempDir);
    await legacy.save(doc('bulk_a', '批量迁移A'));
    await legacy.save(doc('bulk_b', '批量迁移B'));

    final key = VaultKeyService.randomBytes(32);
    final upgraded = StorageService(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    final metas = await upgraded.listDocuments();
    expect(metas, hasLength(2));

    await waitEncrypted('bulk_a');
    await waitEncrypted('bulk_b');
    // 迁移后再刷新列表仍完整（迁移不丢数据）。
    expect(await upgraded.listDocuments(), hasLength(2));
  });
}
