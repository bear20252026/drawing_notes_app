/// 批次①c：笔记本存储层 DNV 信封加密（Joplin 懒迁移模式）。
///
/// 覆盖：写路径密封（明文不落盘）、读路径解密、懒迁移、锁定 fail-closed、
/// 页面图片三级加密封支（DAN 优先 / DNV 次之 / 明文兼容）。
///
/// 注：写密封走生产默认 600k PBKDF2，全量套件高并发下懒迁移用例
/// 会超出默认 30s 单测超时——放宽到 3 分钟。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nb_encrypt_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String nbPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}notebooks'
      '${Platform.pathSeparator}$id.json';

  Notebook nb(String id, String title) => Notebook(id: id, title: title);

  Future<Uint8List> waitEncrypted(String id) async {
    // 懒迁移走异步写尾队列：轮询等待落盘（上限 ~2s，防死等）。
    final file = File(nbPath(id));
    for (var i = 0; i < 200; i++) {
      final bytes = await file.readAsBytes();
      if (VaultFileCodec.isEncrypted(bytes)) return bytes;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('2 秒内明文笔记本未被迁移为密文');
  }

  test('有主密钥时保存 → 磁盘为 DNV 密文，无明文标题/正文泄露；读取/列表正常', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = NotebookStorage(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );

    final notebook = nb('enc_nb1', '机密笔记本标题')
      ..pages.add(
        NotebookPage(
          id: 'pg1',
          title: '页一',
          document: DrawingDocument(
            id: 'd1',
            title: '页',
            width: 100,
            height: 100,
          ),
        )..textItems.add(PageTextItem(id: 't1', x: 1, y: 1, text: '绝密正文内容')),
      );
    await storage.save(notebook);

    final bytes = await File(nbPath('enc_nb1')).readAsBytes();
    expect(VaultFileCodec.isEncrypted(bytes), isTrue);
    final diskText = utf8.decode(bytes, allowMalformed: true);
    expect(diskText.contains('机密笔记本标题'), isFalse, reason: '磁盘上不得出现明文标题');
    expect(diskText.contains('绝密正文内容'), isFalse, reason: '磁盘上不得出现明文正文');

    final loaded = await storage.load('enc_nb1');
    expect(loaded?.id, 'enc_nb1');
    expect(loaded?.title, '机密笔记本标题');
    expect(loaded?.pages.first.textItems.first.text, '绝密正文内容');

    final all = await storage.listAll();
    expect(all, hasLength(1));
    expect(all.first.title, '机密笔记本标题');
  });

  test('懒迁移：旧明文笔记本读取时自动重写为密文（Joplin 模式）', () async {
    final legacy = NotebookStorage(directoryProvider: () async => tempDir);
    await legacy.save(nb('legacy_nb', '升级前旧笔记本'));
    expect(
      VaultFileCodec.isEncrypted(await File(nbPath('legacy_nb')).readAsBytes()),
      isFalse,
    );

    final key = VaultKeyService.randomBytes(32);
    final upgraded = NotebookStorage(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    final loaded = await upgraded.load('legacy_nb');
    expect(loaded?.title, '升级前旧笔记本');

    final bytes = await waitEncrypted('legacy_nb');
    expect(
      utf8.decode(bytes, allowMalformed: true).contains('升级前旧笔记本'),
      isFalse,
    );

    // 迁移后仍可正常读取（无数据损失）。
    final reloaded = await upgraded.load('legacy_nb');
    expect(reloaded?.title, '升级前旧笔记本');
  });

  test('锁定状态读加密笔记本 → VaultFileLockException；列表跳过（fail-closed）', () async {
    final key = VaultKeyService.randomBytes(32);
    final writer = NotebookStorage(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    await writer.save(nb('locked_nb', '锁定内容'));

    final lockedReader = NotebookStorage(
      directoryProvider: () async => tempDir,
      keyProvider: () async => null, // 保险库锁定
    );
    await expectLater(
      lockedReader.load('locked_nb'),
      throwsA(isA<VaultFileLockException>()),
    );
    expect(await lockedReader.listAll(), isEmpty);
  });

  test('页面图片：保险库解锁 → DNV 密文落盘；readImageBytes 可解回', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = NotebookStorage(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    // 渲染读取口（readImageBytes）走共享保险库实例——与生产 app.dart
    // initState registerShared() 接线一致，测试注入同一密钥。
    final vault = VaultKeyService(
      vaultFileResolver: () async =>
          File('${tempDir.path}${Platform.pathSeparator}vault.key.json'),
    )..debugInjectMasterKey(key);
    vault.registerShared();

    // 造一张最小 PNG（1x1 像素）作为源图。
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    );
    final src = File('${tempDir.path}${Platform.pathSeparator}src.png')
      ..writeAsBytesSync(png);

    final storedPath = await storage.storeImage(src.path, 'pg1');
    final stored = await File(storedPath).readAsBytes();
    expect(
      VaultFileCodec.isEncrypted(stored),
      isTrue,
      reason: '保险库解锁时页面图片应为 DNV 密文',
    );
    expect(utf8.decode(stored, allowMalformed: true).length, greaterThan(0));

    // 经共享渲染读取口解回（AAD 绑定 file:<basename>）。
    final clear = await VaultFileCodec.readImageBytes(File(storedPath));
    expect(clear, png);
  });

  test('页面图片：未解锁 → 明文兼容写入（旧数据行为不变）', () async {
    final storage = NotebookStorage(directoryProvider: () async => tempDir);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    );
    final src = File('${tempDir.path}${Platform.pathSeparator}src.png')
      ..writeAsBytesSync(png);

    final storedPath = await storage.storeImage(src.path, 'pg1');
    final stored = await File(storedPath).readAsBytes();
    expect(VaultFileCodec.isEncrypted(stored), isFalse);
    expect(stored, png);
  });
}
