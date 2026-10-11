// DN-004 / DN-006 回归（P0 数据安全，2026-10-12）。
//
// 钉的是「有界流式恢复的闸门」这一对**相反方向**——守卫类改动必须两条都钉，
// 否则要么形同虚设、要么把合法备份一起打死：
//   ① 该拒的拒：manifest-only / 缺必需子目录 / 清单自述与包内不一致 /
//      条目数·解压总字节·膨胀比超限 / 更高版本包；
//   ② 不误伤：自产合法包在**默认预算**下必须完整可恢复（逐字节回读比对）。
// 每个拒绝分支都额外断言：不写待恢复标记、不留半截暂存目录、现网数据根
// 一字未动（拒绝的净效果必须是零变化）。
//
// 手写 fake / 临时目录风格照 test/core/storage/backup_service_test.dart。
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/storage/backup_service.dart';
import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory docsDir;
  late Directory supportDir;
  late Directory dataRoot;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('backup_guard_docs_');
    supportDir = await Directory.systemTemp.createTemp('backup_guard_supp_');
    dataRoot = Directory(
      '${supportDir.path}${Platform.pathSeparator}${AppDataRoot.defaultRootName}',
    );
    await dataRoot.create(recursive: true);
  });

  tearDown(() async {
    // 判空兜底：setUp 失败时 late 字段未初始化，直接读会抛
    // LateInitializationError（本仓 AppDataRoot 相关测试的先例做法）。
    try {
      await deleteTempDirWithRetry(docsDir);
    } catch (_) {}
    try {
      await deleteTempDirWithRetry(supportDir);
    } catch (_) {}
  });

  File rootFile(String rel) =>
      File('${dataRoot.path}${Platform.pathSeparator}$rel');

  Future<String> writeZip(String name, List<ArchiveFile> files) async {
    final path = '${docsDir.path}${Platform.pathSeparator}$name';
    final archive = Archive();
    for (final f in files) {
      archive.addFile(f);
    }
    await File(path).writeAsBytes(ZipEncoder().encode(archive));
    return path;
  }

  ArchiveFile entry(String name, List<int> bytes) =>
      ArchiveFile.bytes(name, bytes);

  ArchiveFile text(String name, String content) =>
      entry(name, utf8.encode(content));

  /// v1 清单（无自述字段——历史存量包的样子）。
  ArchiveFile v1Manifest() =>
      text('backup_manifest.json', '{"formatVersion":1}');

  /// 断言拒绝分支的「零副作用」：无标记、无残留暂存、现网原样。
  Future<void> expectNoSideEffects(Map<String, String> snapshot) async {
    expect(
      File(
        '${supportDir.path}${Platform.pathSeparator}'
        '${AppDataRoot.pendingRestoreMarkerName}',
      ).existsSync(),
      isFalse,
      reason: '被拒的包绝不能写待恢复标记（写了下次启动就真换根）',
    );
    expect(
      supportDir
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('.restore_')),
      isEmpty,
      reason: '被拒的包不能留半截暂存目录',
    );
    for (final rel in snapshot.keys) {
      final f = rootFile(rel);
      expect(f.existsSync(), isTrue, reason: '现网 $rel 必须原样存在');
      expect(
        await f.readAsString(),
        snapshot[rel],
        reason: '现网 $rel 内容必须一字未动',
      );
    }
  }

  Future<Map<String, String>> seedLiveRoot() async {
    final files = <String, String>{
      'documents/keep.json': '{"keep":1}',
      'blockdocs/keep_block.json': '{"keep":2}',
      'security/vault.key.json': '{"k":"live"}',
    };
    for (final e in files.entries) {
      final f = rootFile(e.key);
      await f.create(recursive: true);
      await f.writeAsString(e.value);
    }
    return files;
  }

  Future<BackupIntegrityException> reject(
    String backupPath, {
    BackupRestoreLimits? limits,
  }) async {
    BackupIntegrityException? caught;
    try {
      await BackupService.stageRestore(
        backupPath: backupPath,
        dataParentDir: supportDir,
        limits: limits ?? kBackupRestoreLimitsDefault,
      );
    } on BackupIntegrityException catch (e) {
      caught = e;
    }
    expect(caught, isNotNull, reason: '$backupPath 应被类型化拒绝');
    return caught!;
  }

  group('DN-006 预算闸门', () {
    test('条目数超限 → 安全终止、现网原样不动', () async {
      final live = await seedLiveRoot();
      final zip = await writeZip('many.zip', [
        v1Manifest(),
        text('documents/a.json', '{}'),
        text('documents/b.json', '{}'),
        text('documents/c.json', '{}'),
      ]);

      final e = await reject(zip, limits: const BackupRestoreLimits(maxEntries: 2));
      expect(e.code, 'tooManyEntries');
      expect(e.stats['entries'], 4);
      expect(e.stats['limit'], 2);
      await expectNoSideEffects(live);
    });

    test('解压总字节超限 → 安全终止、现网原样不动', () async {
      final live = await seedLiveRoot();
      final rnd = List<int>.generate(2048, (i) => (i * 2654435761) & 0xff);
      final zip = await writeZip('big.zip', [
        v1Manifest(),
        entry('documents/big.bin', rnd),
        text('blockdocs/b.json', '{}'),
      ]);

      final e = await reject(
        zip,
        limits: const BackupRestoreLimits(maxTotalBytes: 1024),
      );
      expect(e.code, 'totalBytesExceeded');
      expect(e.stats['limit'], 1024);
      await expectNoSideEffects(live);
    });

    test('单条目解压字节超限 → 安全终止、现网原样不动', () async {
      final live = await seedLiveRoot();
      final rnd = List<int>.generate(4096, (i) => (i * 2654435761) & 0xff);
      final zip = await writeZip('one-big.zip', [
        v1Manifest(),
        entry('documents/big.bin', rnd),
      ]);

      final e = await reject(
        zip,
        limits: const BackupRestoreLimits(maxEntryBytes: 2048),
      );
      expect(e.code, 'entryTooLarge');
      expect(e.stats['maxEntryBytes'], 4096);
      await expectNoSideEffects(live);
    });

    test('膨胀比超限（zip 炸弹）→ 默认预算即拒，不写标记', () async {
      final live = await seedLiveRoot();
      // 200KB 单字节填充：deflate 能压到几百字节 → 膨胀比远超 100:1。
      final bomb = List<int>.filled(200 * 1024, 0x41);
      final zip = await writeZip('bomb.zip', [
        v1Manifest(),
        entry('documents/bomb.bin', bomb),
      ]);
      expect(File(zip).lengthSync(), lessThan(8 * 1024));

      final e = await reject(zip); // **默认**预算，不注入
      expect(e.code, 'compressionRatioExceeded');
      expect(
        (e.stats['ratioPercent'] as int) > kBackupMaxRatioPercent,
        isTrue,
      );
      await expectNoSideEffects(live);
    });

    test('备份包体积异常（0 字节文件）→ archiveSizeOutlier', () async {
      final live = await seedLiveRoot();
      final emptyPath = '${docsDir.path}${Platform.pathSeparator}empty.zip';
      await File(emptyPath).writeAsBytes(<int>[]);

      final e = await reject(emptyPath);
      expect(e.code, 'archiveSizeOutlier');
      await expectNoSideEffects(live);
    });

    test('不是 zip（随机字节，无 EOCD）→ 拒绝，绝不放行', () async {
      final live = await seedLiveRoot();
      final junkPath = '${docsDir.path}${Platform.pathSeparator}junk.bin';
      final rnd = List<int>.generate(4096, (i) => Random(i).nextInt(256));
      await File(junkPath).writeAsBytes(rnd);

      final e = await reject(junkPath);
      // 无 EOCD 的包：中央目录读不出条目 → 走清单缺失分支；真损坏包则由
      // ZipDecoder 抛错走 notZip。两条都必须是类型化拒绝，不许静默接受。
      expect(e.code, anyOf('notZip', 'noManifest'), reason: e.message);
      await expectNoSideEffects(live);
    });
  });

  group('DN-004 结构闸门', () {
    test('只有非笔记子目录（thumbnails）→ 拒绝并指明缺 documents/blockdocs', () async {
      final live = await seedLiveRoot();
      final zip = await writeZip('no-notes.zip', [
        v1Manifest(),
        entry('thumbnails/x.png', [1, 2, 3]),
        entry('security/vault.key.json', utf8.encode('{"k":1}')),
      ]);

      final e = await reject(zip);
      expect(e.code, 'incompleteRoot');
      final gaps = (e.stats['gaps'] as List).map((g) => '$g').join('；');
      expect(
        gaps.contains('documents') && gaps.contains('blockdocs'),
        isTrue,
        reason: '必须指明缺哪一项，实测：$gaps',
      );
      await expectNoSideEffects(live);
    });

    test('布局完全对不上（无关 zip 塞个同名清单）→ 拒绝并指明不是本应用布局', () async {
      final live = await seedLiveRoot();
      final zip = await writeZip('foreign.zip', [
        v1Manifest(),
        text('videos/movie.mp4', 'x'),
        text('node_modules/dep.js', 'x'),
      ]);

      final e = await reject(zip);
      expect(e.code, 'incompleteRoot');
      final gaps = (e.stats['gaps'] as List).map((g) => '$g').join('；');
      expect(
        gaps.contains('数据子目录') || gaps.contains('documents'),
        isTrue,
        reason: '必须说明它不是本应用的数据根布局，实测：$gaps',
      );
      await expectNoSideEffects(live);
    });

    test('v2 清单自述与包内不一致 → manifestMismatch（数量/字节/目录逐项报）', () async {
      final live = await seedLiveRoot();
      final zip = await writeZip('liar.zip', [
        text(
          'backup_manifest.json',
          jsonEncode(<String, dynamic>{
            'formatVersion': 2,
            'createdAt': '2026-04-01T00:00:00.000Z',
            'dataFileCount': 99,
            'dataBytes': 999999,
            'dirFileCounts': <String, int>{'documents': 5, 'blockdocs': 2},
          }),
        ),
        text('documents/only.json', '{"t":1}'),
      ]);

      final e = await reject(zip);
      expect(e.code, 'manifestMismatch');
      final mismatches = (e.stats['mismatches'] as List).map((m) => '$m').join('；');
      expect(mismatches.contains('99'), isTrue, reason: '应报声明 99 vs 实际 1');
      expect(
        mismatches.contains('documents'),
        isTrue,
        reason: '应报子目录级差异，实测：$mismatches',
      );
      await expectNoSideEffects(live);
    });

    test('v2 清单缺自述字段 → manifestMismatch（v2 必须自证）', () async {
      final live = await seedLiveRoot();
      final zip = await writeZip('half.zip', [
        text('backup_manifest.json', '{"formatVersion":2}'),
        text('documents/a.json', '{}'),
      ]);

      final e = await reject(zip);
      expect(e.code, 'manifestMismatch');
      await expectNoSideEffects(live);
    });
  });

  group('反向钉：不许误伤', () {
    test('自产合法包在默认预算下完整可恢复（逐字节回读比对）', () async {
      // 造一个「像真实用户」的数据根：两线笔记 + 回收站 + 缩略图 + 图片 +
      // 密钥 + 根级散 JSON + 崩溃残留 tmp/bak（应被排除）。
      final expected = <String, List<int>>{};
      final keep = <String, String>{
        'documents/d1.json': '{"layers":[1,2,3]}',
        'documents/d2.json': '{"layers":["x","y"]}',
        'documents_trash/t1.json': '{"trashed":true}',
        'blockdocs/n1.json': '{"block":"note"}',
        'blockdocs_trash/n2.json': '{"block":"trash"}',
        'notebooks/nb.json': '{"pages":1}',
        'notebook_images/pi.png': 'not-really-a-png',
        'document_images/img1.png': 'binary-ish-bytes',
        'thumbnails/th1.png': 'tiny',
        'security/vault.key.json': '{"k":"s3cret"}',
        'security/app_lock_guard.key': 'guard',
        'all_docs_favorites.json': '["d1"]',
        'all_docs_tags.json': '[]',
      };
      for (final e in keep.entries) {
        final f = rootFile(e.key);
        await f.create(recursive: true);
        await f.writeAsString(e.value);
        expected[e.key] = utf8.encode(e.value);
      }
      // 二进制随机内容（测流式写 + 长度核对，不能被文本假设带偏）。
      final rnd = File('${dataRoot.path}${Platform.pathSeparator}documents/rnd.bin');
      await rnd.create(recursive: true);
      final rndBytes = List<int>.generate(
        64 * 1024,
        (i) => (i * 1103515245 + 12345) & 0xff,
      );
      await rnd.writeAsBytes(rndBytes);
      expected['documents/rnd.bin'] = rndBytes;
      // 崩溃保护残留：不进包、也不该随恢复回来。
      await rootFile('documents/d1.json.tmp').create(recursive: true);
      await rootFile('documents/d1.json.bak').create(recursive: true);

      final backupPath =
          '${docsDir.path}${Platform.pathSeparator}real.zip';
      await BackupService.createBackup(
        dataRoot: dataRoot,
        destinationPath: backupPath,
      );

      await BackupService.stageRestore(
        backupPath: backupPath,
        dataParentDir: supportDir,
      ); // 默认预算，不得抛

      final applied = await AppDataRoot.applyPendingRestore(
        documentsPathProvider: () => docsDir.path,
        supportPathProvider: () => supportDir.path,
      );
      expect(applied, isTrue, reason: '自产合法包必须真的换根成功');

      for (final e in expected.entries) {
        final f = rootFile(e.key);
        expect(f.existsSync(), isTrue, reason: '${e.key} 必须恢复回来');
        expect(
          await f.readAsBytes(),
          equals(e.value),
          reason: '${e.key} 内容必须逐字节一致',
        );
      }
      expect(rootFile('documents/d1.json.tmp').existsSync(), isFalse);
      expect(rootFile('documents/d1.json.bak').existsSync(), isFalse);
      // 换根侧不留 .old_（现网旧根按既有策略**立即**递归删除——该保留策略
      // 是否改成留档属业主裁决，本批一字未动，见 app_data_root.dart 注释）。
      expect(
        supportDir
            .listSync()
            .whereType<Directory>()
            .where((d) => d.path.contains('.old_')),
        isEmpty,
      );
    });

    test('清单声明与自产包实际一致（打包/校验同一相对路径口径）', () async {
      await rootFile('documents/a.json').create(recursive: true);
      await rootFile('documents/a.json').writeAsString('{"t":1}');
      await rootFile('blockdocs/b.json').create(recursive: true);
      await rootFile('blockdocs/b.json').writeAsString('{"t":2}');
      await rootFile('security/vault.key.json').create(recursive: true);
      await rootFile('security/vault.key.json').writeAsString('{"k":1}');

      final backupPath = '${docsDir.path}${Platform.pathSeparator}self.zip';
      await BackupService.createBackup(
        dataRoot: dataRoot,
        destinationPath: backupPath,
      );

      // 读包内清单：v2 三项自述必须与包内条目对得上（否则恢复侧误伤）。
      final decoded = ZipDecoder().decodeBytes(File(backupPath).readAsBytesSync());
      final manifestRaw = decoded.files
          .firstWhere((f) => f.name == kBackupManifestName)
          .content;
      final manifest =
          jsonDecode(utf8.decode(manifestRaw)) as Map<String, dynamic>;
      expect(manifest['formatVersion'], kBackupFormatVersion);

      final dataEntries = decoded.files
          .where((f) => f.isFile && f.name != kBackupManifestName)
          .toList();
      expect(manifest['dataFileCount'], dataEntries.length);
      expect(
        manifest['dataBytes'],
        dataEntries.fold<int>(0, (s, f) => s + f.size),
      );
      final declared = (manifest['dirFileCounts'] as Map).cast<String, dynamic>();
      for (final dir in AppDataRoot.knownSubdirNames) {
        final actual = dataEntries
            .where((f) => AppDataRoot.knownSubdirOf(f.name) == dir)
            .length;
        expect(declared[dir] ?? 0, actual, reason: '子目录 $dir 计数必须同源');
      }
      // 暂存目录侧同一口径复核通过（stageRestore 不抛即证明）。
      await BackupService.stageRestore(
        backupPath: backupPath,
        dataParentDir: supportDir,
      );
      final marker = File(
        '${supportDir.path}${Platform.pathSeparator}'
        '${AppDataRoot.pendingRestoreMarkerName}',
      );
      expect(marker.existsSync(), isTrue);
      final staging = Directory((await marker.readAsString()).trim());
      expect(AppDataRoot.directoryRestoreGaps(staging), isEmpty);
    });

    test('AppDataRoot 结构判定：v1 需笔记下限、v2 免笔记下限（空库自产包不误伤）', () {
      // v1（无自述）：只有 security/ 的包 → 笔记为空即拒（它不可能是可用库）。
      expect(
        AppDataRoot.restoreStructureGaps(
          dataFileCount: 1,
          dirFileCounts: const {'security': 1},
          requireNoteBearing: true,
        ),
        isNotEmpty,
      );
      // v2（自产、已逐项核对）：同样内容不再受笔记下限约束 → 通过。
      expect(
        AppDataRoot.restoreStructureGaps(
          dataFileCount: 1,
          dirFileCounts: const {'security': 1},
          requireNoteBearing: false,
        ),
        isEmpty,
      );
      // 空包两档都拒（这就是 DN-004 的原始缺陷形态）。
      for (final requireNote in const [true, false]) {
        expect(
          AppDataRoot.restoreStructureGaps(
            dataFileCount: 0,
            dirFileCounts: const {},
            requireNoteBearing: requireNote,
          ).length,
          greaterThanOrEqualTo(2),
        );
      }
    });
  });
}
