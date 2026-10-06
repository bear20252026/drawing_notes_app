// 懒迁移真 KDF 重写，CI 高负载可超 30s 默认超时。
@Tags(["kdf"])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/temp_dir_cleanup.dart';
import '../../helpers/wait_encrypted.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_encrypt_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  String docPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}$id.json';

  DrawingDocument doc(String id, String title) =>
      DrawingDocument(id: id, title: title);

  /// 懒迁移等待统一走 [waitEncryptedFile]（2s→15s，防 CI 慢机器击穿）。
  Future<Uint8List> waitEncrypted(String id) async =>
      waitEncryptedFile(File(docPath(id)), label: '明文');

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

  // P0 定性（2026-10-06，由 integration_test/cuj_01_test.dart 真机取证）：
  // `app.dart` **无条件**注入 keyProvider，而写路径把「provider 非空 +
  // key 为 null」一律当锁定 → 从未设置 PIN 的用户（保险库尚未建立，是合法
  // 稳态：`VaultKeyService.initialize` 只在设置页/门禁/快速解锁三处被调用）
  // 每次保存画布都抛 VaultFileLockException，被 SaveScheduler 的退避吞掉，
  // 用户侧表现就是「画完的东西关掉就没了」。同文件的笔记块写路径
  // （NoteBlockDocStore）在无密钥时是**明文落盘**的，那才是产品设计的口径
  // （S-10 记录过「未设 PIN 明文落盘」）。
  test('未建立保险库（用户从未设 PIN）时保存画布必须明文落盘', () async {
    final storage = StorageService(
      directoryProvider: () async => tempDir,
      // 生产装配形状：keyProvider 恒被注入，未建库时取不到密钥。
      keyProvider: () async => null,
      vaultConfigured: () async => false, // 保险库文件不存在
    );

    final path = await storage.save(doc('no_vault_doc', '无 PIN 用户的画作'));

    final bytes = await File(path).readAsBytes();
    expect(
      VaultFileCodec.isEncrypted(bytes),
      isFalse,
      reason: '未建库时明文落盘是产品设计（与 NoteBlockDocStore 写路径同口径）',
    );
    expect(utf8.decode(bytes).contains('无 PIN 用户的画作'), isTrue);
    expect((await storage.load('no_vault_doc'))?.title, '无 PIN 用户的画作');
  });

  test('已建立保险库但锁定时保存仍 fail-closed（P2-3 语义不得回退）', () async {
    final storage = StorageService(
      directoryProvider: () async => tempDir,
      keyProvider: () async => null, // 建过库，但本会话未解锁
    );
    await expectLater(
      storage.save(doc('locked_write_doc', '锁定态写入')),
      throwsA(isA<VaultFileLockException>()),
    );
    // 未注入 vaultConfigured 时保守按「已建库」处理——新增的可选参数
    // 不能变成新的 fail-open 后门（上面这条就是这个默认值的证据）。
  });

  test('未建库时缩略图同样必须明文落盘（同一 P0 的媒体覆盖面）', () async {
    final storage = StorageService(
      directoryProvider: () async => tempDir,
      keyProvider: () async => null,
      vaultConfigured: () async => false,
    );
    final png = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

    final path = await storage.saveThumbnail('no_vault_doc', png);

    expect(File(path).existsSync(), isTrue, reason: '缩略图写不进去=首页永远没预览');
    expect(await storage.thumbnailBytes('no_vault_doc'), png);
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
    expect(File(docPath('deletable')).existsSync(), isFalse);
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
    // 迁移写尾队列在 Windows CI 可能仍短暂持有句柄；再刷一次列表并
    // 留一个事件循环拍，避免 tearDown 与在途 rename/delete 竞态（errno 32）。
    expect(await upgraded.listDocuments(), hasLength(2));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  test('Windows 共享冲突：目标句柄被短暂占用时保存经退避重试自愈', () async {
    // 根因回归（2026-09-24）：_replaceWithTemp 的 delete/rename 曾在
    // errno 32 上裸失败，杀毒/索引器短暂持句柄即中断整次保存（本机
    // 全量套件懒迁移偶发失败的单链根因）。40ms 的占用覆盖前两次退避
    // （25/50ms），第 3 次（~75ms）应自愈；即使调度抖动，后续 150/250ms
    // 两档仍有宽裕余量。
    final key = VaultKeyService.randomBytes(32);
    final storage = StorageService(
      directoryProvider: () async => tempDir,
      keyProvider: () async => key,
    );
    await storage.save(doc('lock_doc', '占用回归'));
    final f = File(docPath('lock_doc'));

    final RandomAccessFile handle = await f.open(mode: FileMode.append);
    var closed = false;
    Future<void> closeOnce() async {
      if (closed) return;
      closed = true;
      await handle.close();
    }

    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 40), closeOnce),
    );
    try {
      await storage.save(doc('lock_doc', '占用回归v2'));
    } finally {
      await closeOnce();
    }
    final loaded = await storage.load('lock_doc');
    expect(loaded?.title, '占用回归v2');
  }, skip: Platform.isWindows ? false : 'errno 32 共享冲突仅 Windows 有语义');
}
