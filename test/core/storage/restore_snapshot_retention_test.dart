// 恢复前快照的保留策略（DN-208，第三轮专家审计 2026-10-13）。
//
// 审计结论：`applyPendingRestore` 换根成功后**立即**递归删除旧根。那条路径是
// 「成功」路径——DN-103 的失败回滚根本不会触发，所以用户选错备份包时，应用内
// 没有任何退回手段。本批裁决为「保留最近一份」：本次换下的 `.old_<毫秒>` 留下，
// 只有时间戳**严格更早**的兄弟目录才被清（磁盘上因此最多一份快照，不无限增长）。
//
// 判据用目录名里的毫秒而不是路径字符串相等：Windows 上 `listSync()` 回来的路径
// 写法可能与拼出来的 keep 路径不一致，比较一旦失败就会删掉刚留下的那份——
// 正好是要防的事反过来发生。时间戳相等或更新的目录一律不动。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/storage/backup_service.dart';
import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory docsDir;
  late Directory supportDir;
  late Directory dataRoot;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('dn208_docs_');
    supportDir = await Directory.systemTemp.createTemp('dn208_supp_');
    dataRoot = Directory(
      '${supportDir.path}${Platform.pathSeparator}${AppDataRoot.defaultRootName}',
    );
    await dataRoot.create(recursive: true);
  });

  tearDown(() async {
    for (final d in [docsDir, supportDir]) {
      try {
        await deleteTempDirWithRetry(d);
      } catch (_) {}
    }
  });

  File rootFile(String rel) =>
      File('${dataRoot.path}${Platform.pathSeparator}$rel');

  String snapshotName(int stamp) =>
      '${AppDataRoot.defaultRootName}.old_$stamp';

  Directory seedSnapshot(int stamp, String marker) {
    final dir = Directory(
      '${supportDir.path}${Platform.pathSeparator}${snapshotName(stamp)}',
    );
    File(
      '${dir.path}${Platform.pathSeparator}documents${Platform.pathSeparator}a.json',
    ).createSync(recursive: true);
    File(
      '${dir.path}${Platform.pathSeparator}documents${Platform.pathSeparator}a.json',
    ).writeAsStringSync('{"t":"$marker"}');
    return dir;
  }

  /// 造一份「现网内容 = [marker]」的备份包并走完 暂存 → 确认 → 启动期换根。
  Future<void> restoreFrom(String marker) async {
    await rootFile('documents/a.json').create(recursive: true);
    await rootFile('documents/a.json').writeAsString('{"t":"$marker"}');
    await rootFile('security/vault.key.json').create(recursive: true);
    await rootFile('security/vault.key.json').writeAsString('{"k":1}');
    await rootFile('thumbnails/x.png').create(recursive: true);
    await rootFile('thumbnails/x.png').writeAsBytes([1, 2, 3]);
    final backupPath = '${docsDir.path}${Platform.pathSeparator}$marker.zip';
    await BackupService.createBackup(
      dataRoot: dataRoot,
      destinationPath: backupPath,
    );
    await BackupService.stageRestore(
      backupPath: backupPath,
      dataParentDir: supportDir,
    );
    expect(
      await AppDataRoot.confirmRestoreStage(parentDir: supportDir),
      RestoreStageDecision.confirmed,
    );
    expect(
      await AppDataRoot.applyPendingRestore(
        documentsPathProvider: () => docsDir.path,
        supportPathProvider: () => supportDir.path,
      ),
      isTrue,
      reason: '$marker 的恢复应当换根成功',
    );
  }

  List<Directory> snapshotsOnDisk() => supportDir
      .listSync()
      .whereType<Directory>()
      .where(
        (d) =>
            d.path.replaceAll('\\', '/').contains('${AppDataRoot.defaultRootName}.old_'),
      )
      .toList();

  test('换根成功后保留本次快照，且内容确实是恢复前的现网（可回退的数据是真的）', () async {
    // 现网 = liveA，恢复 backup restored（内容 different）→ 换根后现网是 restored，
    // 而恢复**前**的 liveA 必须还能在磁盘上找到。
    await rootFile('documents/a.json').create(recursive: true);
    await rootFile('documents/a.json').writeAsString('{"t":"liveA"}');
    await rootFile('security/vault.key.json').create(recursive: true);
    await rootFile('security/vault.key.json').writeAsString('{"k":1}');
    final backupPath = '${docsDir.path}${Platform.pathSeparator}restored.zip';
    // 另建一个内容不同的库来打包。
    final otherRoot = Directory(
      '${docsDir.path}${Platform.pathSeparator}other_root',
    );
    File(
      '${otherRoot.path}${Platform.pathSeparator}documents${Platform.pathSeparator}a.json',
    ).createSync(recursive: true);
    File(
      '${otherRoot.path}${Platform.pathSeparator}documents${Platform.pathSeparator}a.json',
    ).writeAsStringSync('{"t":"restored"}');
    File(
      '${otherRoot.path}${Platform.pathSeparator}security${Platform.pathSeparator}vault.key.json',
    ).createSync(recursive: true);
    File(
      '${otherRoot.path}${Platform.pathSeparator}security${Platform.pathSeparator}vault.key.json',
    ).writeAsStringSync('{"k":1}');
    await BackupService.createBackup(
      dataRoot: otherRoot,
      destinationPath: backupPath,
    );
    await BackupService.stageRestore(
      backupPath: backupPath,
      dataParentDir: supportDir,
    );
    await AppDataRoot.confirmRestoreStage(parentDir: supportDir);
    expect(
      await AppDataRoot.applyPendingRestore(
        documentsPathProvider: () => docsDir.path,
        supportPathProvider: () => supportDir.path,
      ),
      isTrue,
    );

    expect(await rootFile('documents/a.json').readAsString(), '{"t":"restored"}');
    final kept = snapshotsOnDisk();
    expect(kept, hasLength(1), reason: '必须留下一份恢复前快照');
    expect(
      File(
        '${kept.single.path}${Platform.pathSeparator}documents${Platform.pathSeparator}a.json',
      ).readAsStringSync(),
      '{"t":"liveA"}',
      reason: '留下的那份就是恢复前的现网，内容要真实可用',
    );
  });

  test('只清严格更早的快照：本次快照与更晚的目录都不许动', () async {
    final older = seedSnapshot(1000, '更老的一份');
    final newer = seedSnapshot(9999999999999, '比本次晚的');
    final before = DateTime.now().millisecondsSinceEpoch;

    await restoreFrom('second');

    // 与生产侧同口径：只按平台分隔符归一，别写字面反斜杠。
    int stampOf(String path) => int.parse(
          path.replaceAll(Platform.pathSeparator, '/').split('.old_').last,
        );
    final remaining = snapshotsOnDisk().map((d) => d.path).toList();
    // 本次换下的快照时间戳必然不早于开始时刻，且严格早于手工塞的「更晚」目录。
    final current = remaining.firstWhere((p) => stampOf(p) >= before);
    expect(stampOf(current), greaterThanOrEqualTo(before));
    expect(
      remaining.any((p) => stampOf(p) == 9999999999999),
      isTrue,
      reason: '时间戳不早于本次快照的目录一律不动',
    );
    expect(
      remaining.any((p) => stampOf(p) == 1000),
      isFalse,
      reason: '严格更早的那份才被回收（磁盘上限 1 份）',
    );
    expect(older.existsSync(), isFalse);
    expect(newer.existsSync(), isTrue);
  });

  test('反向钉：恢复被拒（暂存不合格）时，既有快照一份都不能少', () async {
    final seeded = seedSnapshot(1000, '上一次留下的快照');
    await rootFile('documents/a.json').create(recursive: true);
    await rootFile('documents/a.json').writeAsString('{"t":"live"}');
    final backupPath = '${docsDir.path}${Platform.pathSeparator}ok.zip';
    await BackupService.createBackup(
      dataRoot: dataRoot,
      destinationPath: backupPath,
    );
    await BackupService.stageRestore(
      backupPath: backupPath,
      dataParentDir: supportDir,
    );
    final stagingPath = (await File(
      '${supportDir.path}${Platform.pathSeparator}'
      '${AppDataRoot.restoreStageMarkerName}',
    ).readAsString()).trim();
    // 暂存在确认前被外部破坏 → 确认必须拒绝，任何清理都不许发生。
    Directory('$stagingPath${Platform.pathSeparator}documents')
        .deleteSync(recursive: true);
    expect(
      await AppDataRoot.confirmRestoreStage(parentDir: supportDir),
      RestoreStageDecision.stagingInvalid,
    );
    expect(
      await AppDataRoot.applyPendingRestore(
        documentsPathProvider: () => docsDir.path,
        supportPathProvider: () => supportDir.path,
      ),
      isFalse,
    );
    expect(seeded.existsSync(), isTrue, reason: '没换成根就不该回收任何快照');
    expect(
      await rootFile('documents/a.json').readAsString(),
      '{"t":"live"}',
    );
  });

  test('解析不出时间戳的 .old_ 目录不动（宁可多占磁盘也不猜）', () async {
    final weird = Directory(
      '${supportDir.path}${Platform.pathSeparator}'
      '${AppDataRoot.defaultRootName}.old_未知来源',
    )..createSync(recursive: true);
    File(
      '${weird.path}${Platform.pathSeparator}KEEP',
    ).writeAsStringSync('别删我');

    await restoreFrom('fresh');

    expect(weird.existsSync(), isTrue);
    expect(
      File('${weird.path}${Platform.pathSeparator}KEEP').readAsStringSync(),
      '别删我',
    );
  });
}
