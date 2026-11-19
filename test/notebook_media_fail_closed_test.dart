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

import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/security/notebook_media_keys.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
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
  // KDF 卫生门禁（kdf_suite_hygiene_test）：本文件 DAN 分支用例调
  // encryptAndSave（真 Argon2id）——注入轻量参数腿（槽位格式与生产一致，
  // 仅参数不同），避免主套件赌生产 KDF 超时。
  KdfParams.newSlotDefault = KdfParams.testLight;

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
        storage.storeImage('nb_fc', pngSource().path, 'pg_locked'),
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
        storage.sealMediaBytesForPath(
          'nb_fc',
          'whatever.png',
          base64Decode(_pngBase64),
        ),
        throwsA(isA<VaultFileLockException>()),
      );
    });

    test('未启用加密（无 keyProvider）→ 明文兼容路径不变', () async {
      final storage = NotebookStorage(directoryProvider: () async => tempDir);
      final path = await storage.storeImage('nb_fc', pngSource().path, 'pg_plain');
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
        await unlocked.storeImage('nb_fc', pngSource().path, 'pg_dnv'),
      ).readAsBytes();
      expect(VaultFileCodec.isEncrypted(dnv), isTrue);

      // 框架级收口（2026-11-15）：DAN 分支判据是「笔记本声明加密」而非
      // 「密钥恰好在内存」——构造真实加密笔记本 + 编排器装配（与生产同形），
      // 即便保险库锁定（keyProvider null）也走 K_note DAN。单实例 + late
      // 闭包端口（与 app.dart late final 同语义，避免双实例口令表分裂）。
      late final NotebookStorage wired;
      final keys = NotebookMediaKeys(
        media: MediaCryptoService.instance,
        envelopes: _LatePort(() => wired),
      );
      wired = NotebookStorage(
        directoryProvider: () async => tempDir,
        mediaCrypto: MediaCryptoService.instance,
        mediaKeys: keys,
        keyProvider: () async => null,
      );
      const pw = 'fc-test-pw';
      await wired.encryptAndSave(Notebook(id: 'nb_fc', title: '加密本'), pw);
      final dan = await File(
        await wired.storeImage('nb_fc', pngSource().path, 'pg_dan'),
      ).readAsBytes();
      expect(MediaCryptoService.isEncryptedFile(dan), isTrue);
      expect(
        await MediaCryptoService.instance.readMediaFile('nb_fc', dan),
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
        storage.storeImage('nb_fc', src.path, 'pg_svg_bad'),
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
      final path = await storage.storeImage('nb_fc', src.path, 'pg_svg_ok');
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
        storage.storeImage('nb_fc', src.path, 'pg_svg_sneak'),
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
        storage.storeImage('nb_fc', src.path, 'pg_svg_big'),
        throwsA(isA<FormatException>()),
      );
      expect(imagesOnDisk(), isEmpty);
    });
  });

  // M-1（第二轮审计 2026-11-18）：密封判定直读主文件，不回退陈旧明文备份。
  group('M-1：isEncryptedNotebook 单调性（备份回退不降级密封）', () {
    test('主文件缺失但 .bak 为陈旧明文 → 仍判加密（不回退备份）', () async {
      late final NotebookStorage wired;
      final keys = NotebookMediaKeys(
        media: MediaCryptoService.instance,
        envelopes: _LatePort(() => wired),
      );
      wired = NotebookStorage(
        directoryProvider: () async => tempDir,
        mediaCrypto: MediaCryptoService.instance,
        mediaKeys: keys,
        keyProvider: () async => null,
      );
      const pw = 'm1-test-pw';
      await wired.encryptAndSave(Notebook(id: 'nb_m1', title: '加密本'), pw);
      expect(await wired.isEncryptedNotebook('nb_m1'), isTrue);

      // 构造陈旧明文 .bak（模拟「曾明文后加密」的历史备份）。
      final nbDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}notebooks',
      );
      final mainFile = File('${nbDir.path}${Platform.pathSeparator}nb_m1.json');
      final bakFile = File('${mainFile.path}.bak');
      bakFile.writeAsStringSync(
        '{"id":"nb_m1","title":"旧明文","encrypted":false,"pages":[]}',
      );
      // 主文件瞬时缺失（rename 兜底先 delete 的窗口）。
      mainFile.deleteSync();

      // 修复前：load() 回退 .bak → encrypted=false → 密封降级到全局钥。
      // 修复后：直读主文件，不存在 → false（新本），但**不回退备份**。
      // 此处主文件缺失 → false 是正确语义（无主文件=无加密声明），
      // 关键断言：即便 .bak 存在也不读它。
      expect(await wired.isEncryptedNotebook('nb_m1'), isFalse);

      // 恢复主文件（密文）→ 仍判加密，.bak 明文不影响。
      // 重新加密保存恢复主文件。
      await wired.encryptAndSave(Notebook(id: 'nb_m1', title: '加密本'), pw);
      expect(await wired.isEncryptedNotebook('nb_m1'), isTrue);
      expect(bakFile.existsSync(), isTrue, reason: '备份仍在（明文）');
      // 密封路径仍走 K_note DAN（不降级）。
      final dan = await File(
        await wired.storeImage('nb_m1', pngSource().path, 'pg_m1'),
      ).readAsBytes();
      expect(MediaCryptoService.isEncryptedFile(dan), isTrue,
          reason: '主文件密文在 → K_note 密封，陈旧明文备份不降级');
    });

    test('主文件损坏 → 抛 FormatException（fail-closed，不判未加密）', () async {
      late final NotebookStorage wired;
      final keys = NotebookMediaKeys(
        media: MediaCryptoService.instance,
        envelopes: _LatePort(() => wired),
      );
      wired = NotebookStorage(
        directoryProvider: () async => tempDir,
        mediaCrypto: MediaCryptoService.instance,
        mediaKeys: keys,
        keyProvider: () async => null,
      );
      await wired.encryptAndSave(Notebook(id: 'nb_m1b', title: '加密本'), 'pw');
      final nbDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}notebooks',
      );
      final mainFile = File('${nbDir.path}${Platform.pathSeparator}nb_m1b.json');
      // 损坏主文件（非 JSON）。
      mainFile.writeAsBytesSync([0xFF, 0xFE, 0x00, 0x01]);
      await expectLater(
        wired.isEncryptedNotebook('nb_m1b'),
        throwsA(isA<FormatException>()),
        reason: '损坏不能据此判「未加密」——密封路径按损坏处理，不降级',
      );
    });

    test('主文件锁定（DNV 外层 + 无钥）→ 抛 VaultFileLockException', () async {
      final key = VaultKeyService.randomBytes(32);
      final unlocked = NotebookStorage(
        directoryProvider: () async => tempDir,
        keyProvider: () async => key,
      );
      await unlocked.encryptAndSave(Notebook(id: 'nb_m1c', title: '加密本'), 'pw');
      // 锁定态存储（无钥）。
      final locked = NotebookStorage(
        directoryProvider: () async => tempDir,
        keyProvider: () async => null,
      );
      await expectLater(
        locked.isEncryptedNotebook('nb_m1c'),
        throwsA(isA<VaultFileLockException>()),
        reason: 'DNV 外层锁定 fail-closed，与 load 同口径',
      );
    });
  });

  // M-6（三轮审计）：判定缓存只许加速，不许改变安全语义。
  group('M-6：加密判定缓存不得掩盖安全信号', () {
    NotebookStorage wiredStorage() {
      late final NotebookStorage wired;
      final keys = NotebookMediaKeys(
        media: MediaCryptoService.instance,
        envelopes: _LatePort(() => wired),
      );
      return wired = NotebookStorage(
        directoryProvider: () async => tempDir,
        mediaCrypto: MediaCryptoService.instance,
        mediaKeys: keys,
        keyProvider: () async => null,
      );
    }

    File mainFileOf(String id) => File(
          '${tempDir.path}${Platform.pathSeparator}notebooks'
          '${Platform.pathSeparator}$id.json',
        );

    test('缓存命中后主文件被删 → 立即判 false（存在性每次实测）', () async {
      final s = wiredStorage();
      await s.encryptAndSave(Notebook(id: 'nb_c1', title: '本'), 'pw');
      expect(await s.isEncryptedNotebook('nb_c1'), isTrue); // 建缓存
      expect(await s.isEncryptedNotebook('nb_c1'), isTrue); // 命中缓存
      mainFileOf('nb_c1').deleteSync();
      expect(
        await s.isEncryptedNotebook('nb_c1'),
        isFalse,
        reason: '主文件缺失是安全信号，缓存不得掩盖',
      );
    });

    test('外部改写主文件（指纹变）→ 重算判定，不用陈旧结论', () async {
      final s = wiredStorage();
      await s.encryptAndSave(Notebook(id: 'nb_c2', title: '本'), 'pw');
      expect(await s.isEncryptedNotebook('nb_c2'), isTrue);
      // 外部改写成明文 JSON（长度/mtime 均变）。
      mainFileOf('nb_c2').writeAsStringSync(
        '{"id":"nb_c2","title":"改","encrypted":false,"pages":[]}',
      );
      expect(await s.isEncryptedNotebook('nb_c2'), isFalse);
    });

    test('损坏主文件 → 每次都抛 FormatException（异常绝不入缓存）', () async {
      final s = wiredStorage();
      await s.encryptAndSave(Notebook(id: 'nb_c3', title: '本'), 'pw');
      expect(await s.isEncryptedNotebook('nb_c3'), isTrue);
      mainFileOf('nb_c3').writeAsBytesSync([0xFF, 0xFE, 0x00]);
      for (var i = 0; i < 3; i++) {
        await expectLater(
          s.isEncryptedNotebook('nb_c3'),
          throwsA(isA<FormatException>()),
          reason: '第 $i 次仍须 fail-closed——缓存异常等于把损坏固化成明文',
        );
      }
    });

    test('回锁清会话 → 缓存作废，重新按磁盘判定', () async {
      final s = wiredStorage();
      await s.encryptAndSave(Notebook(id: 'nb_c4', title: '本'), 'pw');
      expect(await s.isEncryptedNotebook('nb_c4'), isTrue);
      s.clearAllSessionSecrets();
      mainFileOf('nb_c4').deleteSync();
      expect(await s.isEncryptedNotebook('nb_c4'), isFalse);
    });
  });
}

/// 延迟绑定信封端口（测试装配用）：编排器先于存储构造时，经闭包引用
/// 最终存储实例——与生产 app.dart 的 late final 初始化器同一语义。
class _LatePort implements NotebookMediaEnvelopePort {
  _LatePort(this._resolve);
  final NotebookStorage Function() _resolve;

  @override
  Future<bool> isEncryptedNotebook(String notebookId) =>
      _resolve().isEncryptedNotebook(notebookId);

  @override
  Future<String?> sessionPassword(String notebookId) =>
      _resolve().sessionPassword(notebookId);

  @override
  Future<List<int>?> unwrapMediaKey(String notebookId, String password) =>
      _resolve().unwrapMediaKey(notebookId, password);

  @override
  Future<void> attachMediaSlot(
    String notebookId,
    String password,
    List<int> mediaKey,
  ) => _resolve().attachMediaSlot(notebookId, password, mediaKey);
}
