// BackupService + AppDataRoot 待恢复交换 单测（批次 M + S-02 方案 B）。
//
// 覆盖：打包（含 manifest、排除 tmp/bak）→ 暂存恢复 → 启动期原子交换
// 全链路 roundtrip；无效包 fail-fast；zip slip 防护；fail-safe（暂存
// 缺失时放弃恢复且清除标记）；Documents 在途标记仍可应用到新根。
//
// DN-004（P0 数据安全，2026-10-12）更正说明——**原「zip slip 防护」用例把
// 缺陷行为当成了预期**：它构造的 evil 包只有一个 manifest + 一条上跳条目，
// 却断言「暂存目录里只有 1 个文件（仅 manifest）＝恢复被接受」。真正想钉的
// 是「上跳条目不落盘」，不是「manifest-only 包合法」。本批把它拆成两条：
// 路径穿越防护（evil 包补齐成合法数据根 → 恢复被接受，但 evil 条目既不落在
// 暂存之外、也不落在暂存之内）与 manifest-only 包必须被拒绝。
// 预算/结构校验的分支覆盖另见 backup_restore_integrity_test.dart。
import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/storage/backup_service.dart';
import 'package:drawing_notes_app/core/storage/document_budgets.dart';
import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory docsDir;
  late Directory supportDir;
  late Directory dataRoot;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('backup_test_docs_');
    supportDir = await Directory.systemTemp.createTemp('backup_test_supp_');
    // S-02 方案 B：现网数据根在 ApplicationSupport 下。
    dataRoot = Directory(
      '${supportDir.path}${Platform.pathSeparator}${AppDataRoot.defaultRootName}',
    );
    await dataRoot.create(recursive: true);
  });

  tearDown(() async {
    try {
      await deleteTempDirWithRetry(docsDir);
    } catch (_) {}
    try {
      await deleteTempDirWithRetry(supportDir);
    } catch (_) {}
  });

  File rootFile(String rel) =>
      File('${dataRoot.path}${Platform.pathSeparator}$rel');

  test('roundtrip：打包（排除 tmp/bak）→ 暂存 → 启动期交换还原', () async {
    await rootFile('documents/a.json').create(recursive: true);
    await rootFile('documents/a.json').writeAsString('{"t":1}');
    await rootFile('security/vault.key.json').create(recursive: true);
    await rootFile('security/vault.key.json').writeAsString('{"k":1}');
    await rootFile('thumbnails/x.png').create(recursive: true);
    await rootFile('thumbnails/x.png').writeAsBytes([1, 2, 3]);
    // 崩溃保护残留：不应进包。
    await rootFile('documents/a.json.tmp').create(recursive: true);
    await rootFile('documents/a.json.bak').create(recursive: true);

    final backupPath =
        '${docsDir.path}${Platform.pathSeparator}backup.zip';
    await BackupService.createBackup(
      dataRoot: dataRoot,
      destinationPath: backupPath,
    );
    expect(File(backupPath).existsSync(), isTrue);

    // 模拟现网在备份后继续变化：新增文件 + 删除既有文件。
    await rootFile('documents/new_after_backup.json').create(recursive: true);
    await rootFile('documents/a.json').delete();

    // 暂存恢复（标记写在数据根父目录 = ApplicationSupport）。
    await BackupService.stageRestore(
      backupPath: backupPath,
      dataParentDir: supportDir,
    );
    final pending = File(
      '${supportDir.path}${Platform.pathSeparator}'
      '${AppDataRoot.pendingRestoreMarkerName}',
    );
    final staged = File(
      '${supportDir.path}${Platform.pathSeparator}'
      '${AppDataRoot.restoreStageMarkerName}',
    );
    // DN-203：暂存只留 inert 记录，可触发换根的标记此刻**必须还不存在**。
    expect(staged.existsSync(), isTrue);
    expect(
      pending.existsSync(),
      isFalse,
      reason: '用户还没确认，任何启动都不该换根',
    );
    final stagingPath = (await staged.readAsString()).trim();
    expect(
      File('$stagingPath${Platform.pathSeparator}backup_manifest.json')
          .existsSync(),
      isTrue,
    );
    expect(
      File('$stagingPath${Platform.pathSeparator}documents${Platform.pathSeparator}a.json')
          .existsSync(),
      isTrue,
    );
    // 备份点之后的新文件不在暂存（恢复语义 = 回到备份时点）。
    expect(
      File('$stagingPath${Platform.pathSeparator}documents${Platform.pathSeparator}new_after_backup.json')
          .existsSync(),
      isFalse,
    );

    // 用户确认 → 才产生待恢复标记；再走启动期交换。
    expect(
      await AppDataRoot.confirmRestoreStage(parentDir: supportDir),
      RestoreStageDecision.confirmed,
    );
    final applied = await AppDataRoot.applyPendingRestore(
      documentsPathProvider: () => docsDir.path,
      supportPathProvider: () => supportDir.path,
    );
    expect(applied, isTrue);
    expect(pending.existsSync(), isFalse);
    // 现网回到备份时点。
    expect(rootFile('documents/a.json').existsSync(), isTrue);
    expect(
      await rootFile('documents/a.json').readAsString(),
      '{"t":1}',
    );
    expect(rootFile('security/vault.key.json').existsSync(), isTrue);
    expect(rootFile('documents/new_after_backup.json').existsSync(), isFalse);
    // 排除项不会随恢复回来。
    expect(rootFile('documents/a.json.tmp').existsSync(), isFalse);
    expect(rootFile('documents/a.json.bak').existsSync(), isFalse);
    // DN-208：换根成功后保留**一份**恢复前快照（不再立即递归删除旧根），
    // 且留下的那份必须就是换根前的现网内容——选错备份包时它是唯一的回退依据。
    final snapshots = supportDir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.contains('.old_'))
        .toList();
    expect(snapshots, hasLength(1), reason: '磁盘上限一份，不无限增长');
    expect(
      File(
        '${snapshots.single.path}${Platform.pathSeparator}documents'
        '${Platform.pathSeparator}new_after_backup.json',
      ).existsSync(),
      isTrue,
      reason: '快照里要有恢复前现网新增的那个文件——它才是「选错包还能退回」的证据',
    );

    // 幂等：无标记时再调返回 false。
    expect(
      await AppDataRoot.applyPendingRestore(
        documentsPathProvider: () => docsDir.path,
        supportPathProvider: () => supportDir.path,
      ),
      isFalse,
    );
  });

  test('S-02 B 兼容：Documents 在途标记仍应用到 ApplicationSupport 根', () async {
    // 构造一份最小合法备份包放在 Documents 标记指向的暂存目录。
    final staging = Directory(
      '${docsDir.path}${Platform.pathSeparator}'
      '${AppDataRoot.defaultRootName}.restore_compat',
    );
    await staging.create(recursive: true);
    await File(
      '${staging.path}${Platform.pathSeparator}backup_manifest.json',
    ).writeAsString('{"formatVersion":1}');
    final aJson = File(
      '${staging.path}${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}a.json',
    );
    aJson.createSync(recursive: true);
    await aJson.writeAsString('{"from":"docs-marker"}');

    await AppDataRoot.writePendingRestoreMarker(
      parentDir: docsDir,
      stagingPath: staging.path,
    );

    final applied = await AppDataRoot.applyPendingRestore(
      documentsPathProvider: () => docsDir.path,
      supportPathProvider: () => supportDir.path,
    );
    expect(applied, isTrue);
    expect(
      rootFile('documents/a.json').existsSync(),
      isTrue,
      reason: '在途 Documents 标记必须交换到 ApplicationSupport 现网根',
    );
    expect(
      await rootFile('documents/a.json').readAsString(),
      '{"from":"docs-marker"}',
    );
  });

  test('无效备份（无 manifest）抛 FormatException，不写标记', () async {
    final junkPath = '${docsDir.path}${Platform.pathSeparator}junk.zip';
    final archive = Archive()
      ..addFile(ArchiveFile('not_manifest.txt', 2, [1, 2]));
    await File(junkPath).writeAsBytes(ZipEncoder().encode(archive));

    await expectLater(
      BackupService.stageRestore(backupPath: junkPath, dataParentDir: supportDir),
      throwsFormatException,
    );
    expect(
      File(
        '${supportDir.path}${Platform.pathSeparator}'
        '${AppDataRoot.pendingRestoreMarkerName}',
      ).existsSync(),
      isFalse,
    );
  });

  test('zip slip 防护：上跳条目被跳过，既不落在暂存之外也不落在暂存之内', () async {
    // evil 包**补齐为一个合法数据根**（v1 清单 + documents/a.json），这样
    // 本用例判的才是它本意要判的东西——穿越条目不落盘——而不是
    // 「manifest-only 包也被接受」（那是 DN-004 修的缺陷，见下一条用例）。
    final evilPath = '${docsDir.path}${Platform.pathSeparator}evil.zip';
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'backup_manifest.json',
          utf8.encode('{"formatVersion":1}'),
        ),
      )
      ..addFile(
        ArchiveFile.bytes('documents/a.json', utf8.encode('{"t":1}')),
      )
      ..addFile(ArchiveFile.bytes('../../evil.txt', [9, 9]))
      ..addFile(ArchiveFile.bytes('/etc/evil2.txt', [9, 9]))
      ..addFile(ArchiveFile.bytes('security/../evil3.txt', [9, 9]));
    await File(evilPath).writeAsBytes(ZipEncoder().encode(archive));

    await BackupService.stageRestore(
      backupPath: evilPath,
      dataParentDir: supportDir,
    );

    final staged = File(
      '${supportDir.path}${Platform.pathSeparator}'
      '${AppDataRoot.restoreStageMarkerName}',
    );
    expect(
      staged.existsSync(),
      isTrue,
      reason: '合法数据根 + 穿越条目 → 接受包、跳过条目',
    );
    expect(
      File(
        '${supportDir.path}${Platform.pathSeparator}'
        '${AppDataRoot.pendingRestoreMarkerName}',
      ).existsSync(),
      isFalse,
      reason: 'DN-203：接受暂存 ≠ 用户已确认',
    );
    final stagingPath = (await staged.readAsString()).trim();
    // 穿越条目一个都不许落在暂存之外。
    expect(
      File('${supportDir.path}${Platform.pathSeparator}evil.txt').existsSync(),
      isFalse,
    );
    expect(
      File('${docsDir.path}${Platform.pathSeparator}evil.txt').existsSync(),
      isFalse,
    );
    // 暂存目录内也只有合法条目：顶层仅清单（`security/../evil3.txt` 被跳过，
    // security/ 目录因此根本不会建立）。
    expect(
      Directory(stagingPath).listSync().whereType<File>().length,
      1,
      reason: '暂存顶层只有清单本体',
    );
    expect(
      File(
        '$stagingPath${Platform.pathSeparator}documents'
        '${Platform.pathSeparator}a.json',
      ).existsSync(),
      isTrue,
    );
    expect(
      Directory(stagingPath)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('evil'))
          .toList(),
      isEmpty,
    );
  });

  test('DN-004：manifest-only 包必须被拒绝——不写 marker、不换根', () async {
    // 这条正是原「zip slip」用例的反例证据：只有一个清单文件的包此前
    // 会被接受（并进而把现网整库换掉）。
    final lonelyPath = '${docsDir.path}${Platform.pathSeparator}lonely.zip';
    await File(lonelyPath).writeAsBytes(
      ZipEncoder().encode(
        Archive()
          ..addFile(
            ArchiveFile.bytes(
              'backup_manifest.json',
              utf8.encode(
                '{"formatVersion":1,"createdAt":"2026-01-01T00:00:00.000Z"}',
              ),
            ),
          ),
      ),
    );

    // 现网先放一个真文件，证明「拒绝 = 现网一字未动」。
    await rootFile('documents/keep.json').create(recursive: true);
    await rootFile('documents/keep.json').writeAsString('{"keep":true}');

    BackupIntegrityException? thrown;
    try {
      await BackupService.stageRestore(
        backupPath: lonelyPath,
        dataParentDir: supportDir,
      );
    } on BackupIntegrityException catch (e) {
      thrown = e;
    }
    expect(thrown, isNotNull, reason: 'manifest-only 包必须被类型化拒绝');
    expect(thrown!.code, 'incompleteRoot');
    expect(
      thrown.stats['gaps'],
      isA<List<Object?>>().having(
        (l) => l.any((g) => '$g'.contains('数据文件')),
        '含缺失项说明',
        isTrue,
      ),
      reason: '拒绝必须带缺失项统计（不静默）',
    );
    expect(
      File(
        '${supportDir.path}${Platform.pathSeparator}'
        '${AppDataRoot.pendingRestoreMarkerName}',
      ).existsSync(),
      isFalse,
    );
    // 不留半截暂存目录。
    expect(
      supportDir
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('.restore_')),
      isEmpty,
    );
    expect(
      await rootFile('documents/keep.json').readAsString(),
      '{"keep":true}',
    );
  });

  test('DN-004 版本兼容：v1 旧包（无自述字段）仍可完整恢复', () async {
    // kBackupFormatVersion 已 bump 到 2，但校验口径是「> 当前即拒」，
    // 历史 v1 包天然通过——这条反向钉不许因版本演进而漂走。
    expect(kBackupFormatVersion, 2);
    expect(kBackupFormatVersionMin, 1);

    final v1Path = '${docsDir.path}${Platform.pathSeparator}v1.zip';
    await File(v1Path).writeAsBytes(
      ZipEncoder().encode(
        Archive()
          ..addFile(
            ArchiveFile.bytes(
              'backup_manifest.json',
              utf8.encode(
                '{"formatVersion":1,"createdAt":"2026-03-01T00:00:00.000Z"}',
              ),
            ),
          )
          ..addFile(
            ArchiveFile.bytes(
              'documents/old.json',
              utf8.encode('{"from":"v1"}'),
            ),
          )
          ..addFile(
            ArchiveFile.bytes(
              'blockdocs/old_block.json',
              utf8.encode('{"block":"v1"}'),
            ),
          )
          ..addFile(
            ArchiveFile.bytes(
              'security/vault.key.json',
              utf8.encode('{"k":"v1"}'),
            ),
          ),
      ),
    );

    await BackupService.stageRestore(
      backupPath: v1Path,
      dataParentDir: supportDir,
    );
    // DN-203：暂存之后仍需确认，v1 兼容性判定与这条状态机互不豁免。
    expect(
      await AppDataRoot.confirmRestoreStage(parentDir: supportDir),
      RestoreStageDecision.confirmed,
    );
    final applied = await AppDataRoot.applyPendingRestore(
      documentsPathProvider: () => docsDir.path,
      supportPathProvider: () => supportDir.path,
    );
    expect(applied, isTrue, reason: 'v1 包换根侧也必须被认可（两道闸同口径）');
    expect(
      await rootFile('documents/old.json').readAsString(),
      '{"from":"v1"}',
    );
    expect(
      await rootFile('blockdocs/old_block.json').readAsString(),
      '{"block":"v1"}',
    );
    expect(rootFile('security/vault.key.json').existsSync(), isTrue);
  });

  test('DN-004 版本闸门：更高版本的包被拒（升级前不猜格式）', () async {
    final futurePath = '${docsDir.path}${Platform.pathSeparator}future.zip';
    await File(futurePath).writeAsBytes(
      ZipEncoder().encode(
        Archive()
          ..addFile(
            ArchiveFile.bytes(
              'backup_manifest.json',
              utf8.encode('{"formatVersion":${kBackupFormatVersion + 1}}'),
            ),
          )
          ..addFile(ArchiveFile.bytes('documents/a.json', utf8.encode('{}'))),
      ),
    );
    await expectLater(
      BackupService.stageRestore(
        backupPath: futurePath,
        dataParentDir: supportDir,
      ),
      throwsA(
        isA<BackupIntegrityException>().having(
          (e) => e.code,
          'code',
          'versionTooNew',
        ),
      ),
    );
  });

  test('DN-006 阈值与画布文档预算同源（不 import，靠测试钉住等值防漂移）', () {
    // 单条目上限 = DocumentBudgets.maxFileBytes × 2（依据见 backup_service.dart
    // 注释）。不用 import 建立关系：core/storage 全域受 architecture_test
    // 规则 3b 的 Martin instability ≤ 0.4 约束，多一条出向依赖当场撞红。
    expect(kBackupMaxEntryBytes, DocumentBudgets.maxFileBytes * 2);
    expect(kBackupMaxTotalBytes, kBackupMaxArchiveBytes);
    expect(kBackupMaxRatioPercent, 10000); // 100:1
    expect(kBackupMaxManifestBytes, 1 << 20); // 对齐 AuditLogger._maxFileBytes
    expect(kBackupMaxEntries, greaterThan(15000)); // ≥ PROPFIND 4MiB 的 1.5 万对象档
    expect(kBackupRestoreLimitsDefault.maxEntries, kBackupMaxEntries);
    expect(kBackupRestoreLimitsDefault.maxTotalBytes, kBackupMaxTotalBytes);
    expect(kBackupRestoreLimitsDefault.maxEntryBytes, kBackupMaxEntryBytes);
  });

  test('fail-safe：标记存在但暂存缺失 → 放弃恢复并清标记', () async {
    await AppDataRoot.writePendingRestoreMarker(
      parentDir: supportDir,
      stagingPath:
          '${supportDir.path}${Platform.pathSeparator}nonexistent_staging',
    );
    final applied = await AppDataRoot.applyPendingRestore(
      documentsPathProvider: () => docsDir.path,
      supportPathProvider: () => supportDir.path,
    );
    expect(applied, isFalse);
    expect(
      File(
        '${supportDir.path}${Platform.pathSeparator}'
        '${AppDataRoot.pendingRestoreMarkerName}',
      ).existsSync(),
      isFalse,
    );
    // 数据根未被触碰。
    expect(dataRoot.existsSync(), isTrue);
  });
}
