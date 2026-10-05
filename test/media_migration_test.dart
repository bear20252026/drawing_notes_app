import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'helpers/temp_dir_cleanup.dart';

/// H-03 旧明文媒体迁移（专家审计 2026-08-15）：解锁后批量重加密——
/// payload-plugins 批量加密器模式（幂等——已 DAN 密文跳过）。
void main() {
  late Directory tempDir;
  late NotebookStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_migration');
    // C-06（审计 2026-09-27）：媒体服务构造注入——迁移判定从全局单例直取
    // 改为注入字段；测试注入同一单例，语义与此前一致。
    storage = NotebookStorage(
      directoryProvider: () async => tempDir,
      mediaCrypto: MediaCryptoService.instance,
    );
    MediaCryptoService.instance.clearSessionKey();
  });

  tearDown(() async {
    MediaCryptoService.instance.clearSessionKey();
    await deleteTempDirWithRetry(tempDir);
  });

  test('迁移：显式调用重加密明文媒体（DAN 密文化 + 幂等——I-003 后不再自动）', () async {
    // 未解锁——明文副本（旧数据/未加密笔记本）。
    final path = await storage.storeImage(_writeTempImage().path, 'page1');
    // 注入会话密钥（模拟解锁）→ 批量迁移。
    MediaCryptoService.instance.setSessionKey(List<int>.generate(32, (i) => i));
    final migrated = await storage.migrateLegacyMedia();
    expect(migrated, 1);
    // 幂等：已 DAN 密文——再次迁移 0。
    expect(await storage.migrateLegacyMedia(), 0);
    // 已是 DAN 密文，且读取可解密还原。
    final bytes = File(path).readAsBytesSync();
    expect(MediaCryptoService.isEncryptedFile(bytes), isTrue);
    final clear = await MediaCryptoService.instance.readMediaFile(bytes);
    expect(clear.length, greaterThan(0));
  });

  test('迁移：未解锁（会话密钥未注入）时不迁移', () async {
    await storage.storeImage(_writeTempImage().path, 'page1');
    expect(await storage.migrateLegacyMedia(), 0);
  });
  test('I-003：关闭自动迁移——多笔记媒体字节稳定（不自动变化）', () async {
    final p1 = await storage.storeImage(_writeTempImage().path, 'page-1');
    final p2 = await storage.storeImage(_writeTempImage().path, 'page-2');
    final bytes1 = await File(p1).readAsBytes();
    final bytes2 = await File(p2).readAsBytes();
    // 不触发迁移——媒体字节不变（I-003 验收：关闭全局自动迁移后——
    // 无全局自动扫描污染其他笔记媒体——字节/哈希回归稳定）。
    expect(await File(p1).readAsBytes(), bytes1);
    expect(await File(p2).readAsBytes(), bytes2);
  });

  // S-05（审计 2026-09-27 → AR 批 2026-10-05）：迁移器原先只认 DAN 魔数，
  // DNV 保险库信封会被当成「明文」再包一层 DAN ⇒ 双重加密、永久解不开。
  // 现按明文签名白名单 fail-closed：DNV 与认不出的头部一律不动。
  test('S-05：DNV 信封媒体不被二次加密（跳过，字节原样）', () async {
    final dir = await storage.ensureImagesDir();
    final envelope = File(
      '${dir.path}${Platform.pathSeparator}page1_1700000000000.png',
    );
    // vault_file_codec 格式：'DNV' + 版本 0x01 + 载荷。
    envelope.writeAsBytesSync(
      Uint8List.fromList(<int>[0x44, 0x4E, 0x56, 0x01, ...List<int>.filled(48, 7)]),
    );
    MediaCryptoService.instance.setSessionKey(List<int>.generate(32, (i) => i));

    expect(await storage.migrateLegacyMedia(), 0);
    expect(envelope.readAsBytesSync()[0], 0x44); // 仍是 DNV，没被套 DAN
    expect(MediaCryptoService.isEncryptedFile(envelope.readAsBytesSync()), isFalse);
  });

  test('S-05：认不出头部的文件跳过（fail-closed，宁可少迁不可坏迁）', () async {
    final dir = await storage.ensureImagesDir();
    final mystery = File(
      '${dir.path}${Platform.pathSeparator}page1_1700000000001.png',
    );
    mystery.writeAsBytesSync(Uint8List.fromList(List<int>.generate(64, (i) => i)));
    MediaCryptoService.instance.setSessionKey(List<int>.generate(32, (i) => i));

    expect(await storage.migrateLegacyMedia(), 0);
    expect(mystery.readAsBytesSync(), List<int>.generate(64, (i) => i));
  });

  test('S-05 正向对照：真 PNG 签名仍会迁移（白名单没把正常路径一起关掉）', () async {
    final path = await storage.storeImage(_writeTempImage().path, 'page1');
    MediaCryptoService.instance.setSessionKey(List<int>.generate(32, (i) => i));

    expect(await storage.migrateLegacyMedia(), 1);
    expect(MediaCryptoService.isEncryptedFile(File(path).readAsBytesSync()), isTrue);
  });
}

/// 带真实 PNG 签名头的伪图（S-05 起迁移器按签名白名单判定，
/// 任意字节序列会被当成「认不出的头部」跳过）。
File _writeTempImage() {
  final f = File(
    '${Directory.systemTemp.path}/tmp_img_'
    '${DateTime.now().microsecondsSinceEpoch}.png',
  );
  f.writeAsBytesSync(
    Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, ...List<int>.generate(60, (i) => i)]),
  );
  return f;
}
