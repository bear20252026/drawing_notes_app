// R53 审计回归：加密文档主文件损坏时，`.bak` 备份恢复必须真的生效。
//
// 旧实现只 catch `FormatException`（明文解码失败），而加密文档的损坏
// （载荷截断/被篡改）抛的是 `VaultFileException` ⇒ 注释声称的
// 「正式文件损坏时，尝试读取 .bak 上一版备份」对加密文档根本不会触发。
// 加密的正好是它该保护的那类数据，偏偏用不上。

import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_bak_recovery_');
  });

  tearDown(() async {
    try {
      await deleteTempDirWithRetry(tempDir);
    } catch (_) {}
  });

  String docPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}$id.json';

  DrawingDocument doc(String id, String title) =>
      DrawingDocument(id: id, title: title);

  StorageService serviceWith(Uint8List key) => StorageService(
    directoryProvider: () async => tempDir,
    keyProvider: () async => key,
  );

  test('R53：加密文档主文件被截断 → 从 .bak 恢复出原文', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = serviceWith(key);
    await storage.save(doc('enc_bak_doc', '机密标题'));

    final mainBytes = await File(docPath('enc_bak_doc')).readAsBytes();
    expect(VaultFileCodec.isEncrypted(mainBytes), isTrue);

    // 把完好的那一份放进 .bak（模拟「上一版备份」）。
    await File('${docPath('enc_bak_doc')}.bak').writeAsBytes(mainBytes);

    // 主文件被截断到「4 字节头 + 28 字节载荷」——正是 aeadDecrypt 的
    // 过短阈值，会抛 VaultFileException（旧实现接不住，不会回退 .bak）。
    final truncated = Uint8List.fromList(mainBytes.sublist(0, 4 + 28));
    await File(docPath('enc_bak_doc')).writeAsBytes(truncated);

    final loaded = await storage.load('enc_bak_doc');

    expect(loaded, isNotNull, reason: '主文件损坏时必须从 .bak 恢复');
    expect(loaded!.id, 'enc_bak_doc');
    expect(loaded.title, '机密标题');
  });

  test('R53：加密文档主文件被篡改 → 从 .bak 恢复出原文', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = serviceWith(key);
    await storage.save(doc('enc_bak_tamper', '机密标题2'));

    final mainBytes = await File(docPath('enc_bak_tamper')).readAsBytes();
    await File('${docPath('enc_bak_tamper')}.bak').writeAsBytes(mainBytes);

    // 篡改密文中间一比特（GCM 校验必失败 ⇒ VaultFileException）。
    final tampered = Uint8List.fromList(mainBytes);
    tampered[tampered.length - 5] ^= 0xFF;
    await File(docPath('enc_bak_tamper')).writeAsBytes(tampered);

    final loaded = await storage.load('enc_bak_tamper');

    expect(loaded, isNotNull, reason: '主文件被篡改时必须从 .bak 恢复');
    expect(loaded!.title, '机密标题2');
  });

  test('R53：没有 .bak 时不得静默吞掉（仍抛出，让调用方提示）', () async {
    final key = VaultKeyService.randomBytes(32);
    final storage = serviceWith(key);
    await storage.save(doc('enc_no_bak', '机密标题3'));

    final mainBytes = await File(docPath('enc_no_bak')).readAsBytes();
    final truncated = Uint8List.fromList(mainBytes.sublist(0, 4 + 28));
    await File(docPath('enc_no_bak')).writeAsBytes(truncated);

    expect(
      () => storage.load('enc_no_bak'),
      throwsA(isA<VaultFileException>()),
      reason: '无备份可回退时必须把损坏如实抛给调用方，不得静默返回 null',
    );
  });
}
