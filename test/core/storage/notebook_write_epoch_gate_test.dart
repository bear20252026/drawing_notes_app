// P3 写腿世代闸回归（三轮审计 M-1/M-2，2026-11-18）：
// 解锁时发起的加密写，若密封/编码期间回锁（SessionEpoch.bump），提交前
// 世代比对作废——密文不得写进锁定态磁盘。覆盖 save 与 storeImage 两腿；
// 未建库/未装配 keyProvider 的明文路径不受世代闸影响（无密钥可作废）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('p3_epoch_gate_');
    addTearDown(() => deleteTempDirWithRetry(tempDir));
  });

  String nbPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}notebooks'
      '${Platform.pathSeparator}$id.json';

  Notebook nb(String id, String title) => Notebook(id: id, title: title);

  // 可控密钥提供者：key 为当前密钥；slow=true 时取钥挂起 150ms，
  // 制造「发起时解锁、提交前回锁」的在途窗口。
  Uint8List? currentKey = VaultKeyService.randomBytes(32);
  var slowKey = false;
  Future<Uint8List?> provider() async {
    if (slowKey) await Future<void>.delayed(const Duration(milliseconds: 150));
    return currentKey;
  }

  setUp(() {
    currentKey = VaultKeyService.randomBytes(32);
    slowKey = false;
  });

  test('save：密封期间回锁 → 在途写腿作废，磁盘不落密文', () async {
    final storage = NotebookStorage(
      directoryProvider: () async => tempDir,
      keyProvider: provider,
    );
    slowKey = true;
    final pending = storage.save(nb('p3_gate', '在途笔记本'));
    // 取钥挂起期间回锁：世代翻篇 + 密钥失效。
    await Future<void>.delayed(const Duration(milliseconds: 30));
    currentKey = null;
    SessionEpoch.bump();
    // 在途腿作废：key 已 null + 已建库（vaultConfigured 未注入保守视为
    // 已建库）→ fail-closed 抛锁异常，磁盘不落任何字节。
    await expectLater(pending, throwsA(isA<VaultFileLockException>()));
    slowKey = false;
    expect(
      File(nbPath('p3_gate')).existsSync(),
      isFalse,
      reason: '回锁翻篇后在途加密写不得落盘',
    );
  });

  test('save：世代未变 → 正常 DNV 密文落盘且可解回', () async {
    final storage = NotebookStorage(
      directoryProvider: () async => tempDir,
      keyProvider: provider,
    );
    await storage.save(nb('p3_ok', '正常笔记本'));
    final bytes = await File(nbPath('p3_ok')).readAsBytes();
    expect(VaultFileCodec.isEncrypted(bytes), isTrue);
    final loaded = await storage.load('p3_ok');
    expect(loaded?.title, '正常笔记本');
  });

  test('未装配 keyProvider（无保险库）：明文保存不受世代闸影响', () async {
    final storage = NotebookStorage(directoryProvider: () async => tempDir);
    final before = SessionEpoch.current;
    await storage.save(nb('p3_plain', '明文笔记本'));
    expect(SessionEpoch.current, before, reason: '保存不得翻篇世代');
    final bytes = await File(nbPath('p3_plain')).readAsBytes();
    expect(VaultFileCodec.isEncrypted(bytes), isFalse);
    expect(utf8.decode(bytes).contains('明文笔记本'), isTrue);
  });

  test('storeImage：密封期间回锁 → fail-closed 抛锁异常且无半成品', () async {
    final storage = NotebookStorage(
      directoryProvider: () async => tempDir,
      keyProvider: provider,
      vaultConfigured: () async => true,
    );
    // 最小合法 PNG 源。
    final src = File('${tempDir.path}/src.png');
    await src.writeAsBytes(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4'
      'nGNgYGBgAAAABQABh6FO1AAAAABJRU5ErkJggg==',
    ));
    slowKey = true;
    final pending = storage.storeImage('p3_img', src.path, 'pg1');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    currentKey = null;
    SessionEpoch.bump();
    await expectLater(pending, throwsA(isA<VaultFileLockException>()));
    slowKey = false;
    final imagesDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}notebook_images',
    );
    final leftovers = imagesDir.existsSync()
        ? imagesDir.listSync().where((e) => e.path.endsWith('.tmp'))
        : const <FileSystemEntity>[];
    expect(leftovers, isEmpty, reason: '作废的写腿不得留下半成品临时文件');
  });

  test('回锁后新发起的 save：已建库锁定 → fail-closed 拒绝，密文不被明文覆盖', () async {
    final storage = NotebookStorage(
      directoryProvider: () async => tempDir,
      keyProvider: provider,
      vaultConfigured: () async => true,
    );
    await storage.save(nb('p3_lock', '先解锁保存'));
    expect(
      VaultFileCodec.isEncrypted(await File(nbPath('p3_lock')).readAsBytes()),
      isTrue,
    );
    currentKey = null;
    SessionEpoch.bump();
    // P3 收口：锁定态 save 与媒体写同口径 fail-closed——不得把密文
    // 笔记本降级明文覆盖（锁屏期间自动保存定时器照常开火的场景）。
    await expectLater(
      storage.save(nb('p3_lock', '锁定后保存')),
      throwsA(isA<VaultFileLockException>()),
    );
    final bytes = await File(nbPath('p3_lock')).readAsBytes();
    expect(VaultFileCodec.isEncrypted(bytes), isTrue, reason: '既有密文必须保持密文');
    expect(utf8.decode(bytes, allowMalformed: true).contains('锁定后保存'), isFalse);
  });

  test('未建库（vaultConfigured=false）锁定态 save：明文兼容不拒绝', () async {
    final storage = NotebookStorage(
      directoryProvider: () async => tempDir,
      keyProvider: provider,
      vaultConfigured: () async => false,
    );
    currentKey = null; // 未建库 → 无密钥
    await storage.save(nb('p3_novault', '无保险库笔记本'));
    final bytes = await File(nbPath('p3_novault')).readAsBytes();
    expect(VaultFileCodec.isEncrypted(bytes), isFalse);
    expect(utf8.decode(bytes).contains('无保险库笔记本'), isTrue);
  });
}
