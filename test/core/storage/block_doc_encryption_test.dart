import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 批次①c：块文档（NoteBlockDoc）存储层 DNV 信封加密。
///
/// 覆盖：写路径密封、读路径解密、懒迁移、锁定 fail-closed（读取抛异常/
/// 列表跳过）、回收站密文内容解密。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('blockdoc_encrypt_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String docPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}blockdocs'
      '${Platform.pathSeparator}$id.json';

  NoteBlockDoc doc(String id, String title) {
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    return NoteBlockDoc(
      id: id,
      title: title,
      body: [NoteBlock.textBlock('${id}_b1', text: '绝密段落内容')],
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Uint8List> waitEncrypted(String id) async {
    final file = File(docPath(id));
    for (var i = 0; i < 200; i++) {
      final Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } on FileSystemException {
        // Windows CI 竞态：懒迁移重写正持有文件句柄（errno 32）——瞬态，
        // 与"明文未迁移"同等对待，等下一轮重试。
        await Future<void>.delayed(const Duration(milliseconds: 10));
        continue;
      }
      if (VaultFileCodec.isEncrypted(bytes)) return bytes;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('2 秒内明文块文档未被迁移为密文');
  }

  test('有主密钥时保存 → 磁盘为 DNV 密文，无明文标题/正文泄露；读取/列表正常', () async {
    final key = VaultKeyService.randomBytes(32);
    final store = NoteBlockDocStore(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );

    await store.saveDocument(doc('enc_b1', '机密块文档'));

    final bytes = await File(docPath('enc_b1')).readAsBytes();
    expect(VaultFileCodec.isEncrypted(bytes), isTrue);
    final diskText = utf8.decode(bytes, allowMalformed: true);
    expect(diskText.contains('机密块文档'), isFalse);
    expect(diskText.contains('绝密段落内容'), isFalse);

    final loaded = await store.loadDocument('enc_b1');
    expect(loaded?.title, '机密块文档');
    expect(loaded?.body.single.text, '绝密段落内容');

    final headers = await store.listDocHeaders();
    expect(headers, hasLength(1));
    expect(headers.first.title, '机密块文档');
  });

  test('懒迁移：旧明文块文档读取时自动重写为密文', () async {
    final legacy = NoteBlockDocStore(directoryProvider: () async => tempDir);
    await legacy.saveDocument(doc('legacy_b', '升级前旧块文档'));
    expect(
      VaultFileCodec.isEncrypted(await File(docPath('legacy_b')).readAsBytes()),
      isFalse,
    );

    final key = VaultKeyService.randomBytes(32);
    final upgraded = NoteBlockDocStore(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    final loaded = await upgraded.loadDocument('legacy_b');
    expect(loaded?.title, '升级前旧块文档');

    final bytes = await waitEncrypted('legacy_b');
    expect(
      utf8.decode(bytes, allowMalformed: true).contains('升级前旧块文档'),
      isFalse,
    );
  });

  test('锁定状态读加密块文档 → VaultFileLockException；列表跳过（fail-closed）', () async {
    final key = VaultKeyService.randomBytes(32);
    final writer = NoteBlockDocStore(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    await writer.saveDocument(doc('locked_b', '锁定内容'));

    final lockedReader = NoteBlockDocStore(
      directoryProvider: () async => tempDir,
      keyProvider: () async => null, // 保险库锁定
    );
    await expectLater(
      lockedReader.loadDocument('locked_b'),
      throwsA(isA<VaultFileLockException>()),
    );
    expect(await lockedReader.listDocHeaders(), isEmpty);
  });

  test('删除加密块文档成功；软删除进回收站后恢复可解密读取', () async {
    final key = VaultKeyService.randomBytes(32);
    final store = NoteBlockDocStore(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    await store.saveDocument(doc('cycle_b', '回收站往返'));

    // 软删除 → 回收站。
    await store.deleteDocument('cycle_b');
    expect(await File(docPath('cycle_b')).exists(), isFalse);

    // 回收站列表可解密读出标题（密文内容经 _readTrashContent 解密）。
    final trash = await store.listTrash();
    expect(trash.map((t) => t.doc.id), contains('cycle_b'));

    // 恢复后原位可读（内容不丢）。
    await store.restoreDocument('cycle_b');
    final restored = await store.loadDocument('cycle_b');
    expect(restored?.title, '回收站往返');
  });
}
