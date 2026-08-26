import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/infrastructure/storage/vfs/vault_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/services/notebook_storage.dart';

/// 媒体 VFS 双轨接入测试（专家目标架构 VFS——2026-08-16）：
/// 新媒体写 VFS 对象（'vfs:' 标记 + 读回）+ 旧媒体兼容（未注入走现有
/// 路径）+ 密钥上下文（未注入密钥走现有路径——s3eg 双读窗口模式）。
void main() {
  late Directory tempDir;
  final key = List<int>.generate(32, (i) => i);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vault_media_test');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on Exception catch (_) {/* 忽略清理失败 */}
  });

  Future<NotebookStorage> buildStorage({VaultService? vfs}) async {
    final imagesDir = Directory('${tempDir.path}/images');
    await imagesDir.create(recursive: true);
    final storage = NotebookStorage(
      directoryProvider: () async => tempDir,
      vaultService: vfs,
    );
    return storage;
  }

  test('新媒体 VFS 写：storeImage 返回 vfs 标记 + 读回明文', () async {
    final vfs = VaultService(directory: Directory('${tempDir.path}/vfs'));
    vfs.setKey(key);
    final storage = await buildStorage(vfs: vfs);

    final src = File('${tempDir.path}/src.png');
    await src.writeAsBytes(utf8.encode('PNG 媒体字节'));
    final stored = await storage.storeImage(src.path, 'page-1');

    // 'vfs:' 前缀标记（新媒体走 VFS 对象——不是文件路径）。
    expect(stored, startsWith('vfs:media/'));
    // VaultService 读回明文（解密）。
    final clear = await vfs.getObject(stored.substring(4));
    expect(utf8.decode(clear), 'PNG 媒体字节');
  });

  test('旧媒体兼容：未注入 VaultService——storeImage 走现有文件路径', () async {
    final storage = await buildStorage(); // 无 vaultService。
    final src = File('${tempDir.path}/legacy.png');
    await src.writeAsBytes([1, 2, 3, 4]);
    final stored = await storage.storeImage(src.path, 'page-2');
    // 非 vfs 标记——现有文件路径（DAN 文件/明文——旧路径保持）。
    expect(stored.startsWith('vfs:'), isFalse);
    expect(File(stored).existsSync(), isTrue);
  });

  test('密钥上下文：VaultService 未 setKey——storeImage 走现有路径', () async {
    final vfs = VaultService(directory: Directory('${tempDir.path}/vfs2'));
    // 未 setKey（hasKey false）——双轨回退现有路径（s3eg 双读窗口）。
    final storage = await buildStorage(vfs: vfs);
    final src = File('${tempDir.path}/no-key.png');
    await src.writeAsBytes([9, 9, 9]);
    final stored = await storage.storeImage(src.path, 'page-3');
    expect(stored.startsWith('vfs:'), isFalse);
  });

  test('密钥上下文：未注入密钥的 VaultService 读写拒绝（受控下发）', () async {
    final vfs = VaultService(directory: Directory('${tempDir.path}/vfs3'));
    expect(
      () => vfs.putObject('media/x', plain: Uint8List(4)),
      throwsStateError,
    );
  });
}
