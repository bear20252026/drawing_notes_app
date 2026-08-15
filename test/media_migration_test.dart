import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';

/// H-03 旧明文媒体迁移（专家审计 2026-08-15）：解锁后批量重加密——
/// payload-plugins 批量加密器模式（幂等——已 DAN 密文跳过）。
void main() {
  late Directory tempDir;
  late NotebookStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_migration');
    storage = NotebookStorage(directoryProvider: () async => tempDir);
    MediaCryptoService.instance.clearSessionKey();
  });

  tearDown(() async {
    MediaCryptoService.instance.clearSessionKey();
    await tempDir.delete(recursive: true);
  });

  test('迁移：明文媒体解锁后自动重加密（DAN 密文化 + 幂等）', () async {
    // 未解锁——明文副本（旧数据/未加密笔记本）。
    final path = await storage.storeImage(_writeTempImage().path, 'page1');
    // 注入会话密钥（模拟解锁）→ 批量迁移。
    MediaCryptoService.instance.setSessionKey(
      List<int>.generate(32, (i) => i),
    );
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
}

File _writeTempImage() {
  final f = File(
    '${Directory.systemTemp.path}/tmp_img_'
    '${DateTime.now().microsecondsSinceEpoch}.png',
  );
  f.writeAsBytesSync(
    Uint8List.fromList(List<int>.generate(64, (i) => i)),
  );
  return f;
}
