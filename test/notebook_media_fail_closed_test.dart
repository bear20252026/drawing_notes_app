/// P1/P3 回归锁：加密笔记本媒体不得明文降级 + SVG 落盘前必须预检。
///
/// ① 密封三级分支的「③ 均未解锁→明文」只应覆盖**未启用加密**（无
///   keyProvider）的产品设计场景。保险库已装配却取不到密钥 = 锁定态，
///   此处写明文就是明文降级：`NotebookViewPage._restoreSessionAfterReauth`
///   派生失败/无口令时旧实现照样 unlock 会话并弹「会话已恢复」，却不装媒体
///   密钥 ⇒ 此后插入的图片明文躺在 notebook_images/（读端懒迁移只认 DAN/DNV，
///   明文永不回收）。口径对齐画布域 `StorageMediaStore._sealMediaBytes` 的
///   「锁定即抛 [VaultFileLockException]」。
/// ② README 宣称的「导入隔离：SVG 预检」此前只在 test 里被引用、生产零接线；
///   现在 svg 进入应用目录前走 `SvgPreflight.check`，不合规即拒绝导入
///   （白名单保留 svg——是拒绝恶意样本，不是删功能）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'helpers/temp_dir_cleanup.dart';

/// 1x1 像素 PNG。
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

const _benignSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<rect width="10" height="10" fill="red"/></svg>';

const _maliciousSvg =
    '<svg xmlns="http://www.w3.org/2000/svg">'
    '<script type="text/javascript">alert(1)</script></svg>';

void main() {
  late Directory tempDir;
  late Directory imagesDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nb_media_fc_');
    imagesDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}notebook_images',
    );
    MediaCryptoService.instance.clearSessionKey();
  });

  tearDown(() async {
    MediaCryptoService.instance.clearSessionKey();
    await deleteTempDirWithRetry(tempDir);
  });

  File seedSource(String name, List<int> bytes) => File(
    '${tempDir.path}${Platform.pathSeparator}$name',
  )..writeAsBytesSync(bytes);

  File pngSource() => seedSource(
    'src_${DateTime.now().microsecondsSinceEpoch}.png',
    base64Decode(_pngBase64),
  );

  List<String> imagesOnDisk() {
    if (!imagesDir.existsSync()) return const [];
    return imagesDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
  }

  group('媒体密封 fail-closed（保险库启用但锁定）', () {
    test('storeImage：锁定态拒绝明文落盘，且不留下半成品文件', () async {
      final storage = NotebookStorage(
        directoryProvider: () async => tempDir,
        keyProvider: () async => null, // 已装配但锁定
      );
      await expectLater(
        storage.storeImage(pngSource().path, 'pg_locked'),
        throwsA(isA<VaultFileLockException>()),
      );
      expect(
        imagesOnDisk(),
        isEmpty,
        reason: '加密底座开启时不得把明文图片写进 notebook_images/',
      );
    });

    test('sealMediaBytesForPath（PDF 导入等旁路）同口径拒绝', () async {
      final storage = NotebookStorage(
        directoryProvider: () async => tempDir,
        keyProvider: () async => null,
      );
      await expectLater(
        storage.sealMediaBytesForPath('whatever.png', base64Decode(_pngBase64)),
        throwsA(isA<VaultFileLockException>()),
      );
    });

    test('未启用加密（无 keyProvider）→ 明文兼容路径不变', () async {
      final storage = NotebookStorage(directoryProvider: () async => tempDir);
      final path = await storage.storeImage(pngSource().path, 'pg_plain');
      final stored = await File(path).readAsBytes();
      expect(stored, base64Decode(_pngBase64), reason: '不能破坏未加密笔记本既有明文路径');
      expect(VaultFileCodec.isEncrypted(stored), isFalse);
      expect(
        MediaCryptoService.isEncryptedFile(stored),
        isFalse,
      );
    });

    test('保险库解锁 → DNV 密文；媒体会话密钥注入 → DAN 密文', () async {
      final key = VaultKeyService.randomBytes(32);
      final unlocked = NotebookStorage(
        directoryProvider: () async => tempDir,
        keyProvider: () async => key,
      );
      final dnv = await File(
        await unlocked.storeImage(pngSource().path, 'pg_dnv'),
      ).readAsBytes();
      expect(VaultFileCodec.isEncrypted(dnv), isTrue);

      // 媒体会话密钥已装（加密笔记本解锁场景）——即便保险库锁定也走 DAN。
      MediaCryptoService.instance.setSessionKey(
        List<int>.generate(32, (i) => i + 1),
      );
      final danStorage = NotebookStorage(
        directoryProvider: () async => tempDir,
        mediaCrypto: MediaCryptoService.instance,
        keyProvider: () async => null,
      );
      final dan = await File(
        await danStorage.storeImage(pngSource().path, 'pg_dan'),
      ).readAsBytes();
      expect(MediaCryptoService.isEncryptedFile(dan), isTrue);
      expect(
        await MediaCryptoService.instance.readMediaFile(dan),
        base64Decode(_pngBase64),
      );
    });
  });

  group('SVG 导入预检接线（白名单保留 svg）', () {
    test('含脚本的 svg 被拒绝导入，且不留残留文件', () async {
      final storage = NotebookStorage(directoryProvider: () async => tempDir);
      final src = seedSource(
        'evil_${DateTime.now().microsecondsSinceEpoch}.svg',
        utf8.encode(_maliciousSvg),
      );
      await expectLater(
        storage.storeImage(src.path, 'pg_svg_bad'),
        throwsA(isA<FormatException>()),
      );
      expect(imagesOnDisk(), isEmpty);
    });

    test('合规 svg 仍可入库（未删白名单项）', () async {
      final storage = NotebookStorage(directoryProvider: () async => tempDir);
      final src = seedSource(
        'ok_${DateTime.now().microsecondsSinceEpoch}.svg',
        utf8.encode(_benignSvg),
      );
      final path = await storage.storeImage(src.path, 'pg_svg_ok');
      expect(path.endsWith('.svg'), isTrue);
      expect(await File(path).readAsBytes(), utf8.encode(_benignSvg));
    });

    test('svg 改名成 .png 也按内容预检（防绕过扩展名白名单）', () async {
      final storage = NotebookStorage(directoryProvider: () async => tempDir);
      final src = seedSource(
        'sneaky_${DateTime.now().microsecondsSinceEpoch}.png',
        utf8.encode(_maliciousSvg),
      );
      await expectLater(
        storage.storeImage(src.path, 'pg_svg_sneak'),
        throwsA(isA<FormatException>()),
      );
      expect(imagesOnDisk(), isEmpty);
    });

    test('超大 svg 拒绝（复杂度上限）', () async {
      final storage = NotebookStorage(directoryProvider: () async => tempDir);
      final padded = StringBuffer(_benignSvg.substring(0, _benignSvg.length - 6));
      for (var i = 0; i < 6000; i++) {
        padded.write('<rect width="1" height="1"/>');
      }
      padded.write('</svg>');
      final src = seedSource(
        'big_${DateTime.now().microsecondsSinceEpoch}.svg',
        utf8.encode(padded.toString()),
      );
      await expectLater(
        storage.storeImage(src.path, 'pg_svg_big'),
        throwsA(isA<FormatException>()),
      );
      expect(imagesOnDisk(), isEmpty);
    });
  });
}
