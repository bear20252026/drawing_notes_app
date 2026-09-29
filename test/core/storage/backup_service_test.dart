// BackupService + AppDataRoot 待恢复交换 单测（批次 M，2026-09-27）。
//
// 覆盖：打包（含 manifest、排除 tmp/bak）→ 暂存恢复 → 启动期原子交换
// 全链路 roundtrip；无效包 fail-fast；zip slip 防护；fail-safe（暂存
// 缺失时放弃恢复且清除标记）。
import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/storage/backup_service.dart';
import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory docsDir;
  late Directory dataRoot;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('backup_test_docs_');
    dataRoot = Directory(
      '${docsDir.path}${Platform.pathSeparator}${AppDataRoot.defaultRootName}',
    );
    await dataRoot.create(recursive: true);
  });

  tearDown(() async {
    try {
      await deleteTempDirWithRetry(docsDir);
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

    // 暂存恢复。
    await BackupService.stageRestore(
      backupPath: backupPath,
      documentsDir: docsDir,
    );
    final marker = File(
      '${docsDir.path}${Platform.pathSeparator}'
      '${AppDataRoot.pendingRestoreMarkerName}',
    );
    expect(marker.existsSync(), isTrue);
    final stagingPath = (await marker.readAsString()).trim();
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

    // 启动期交换。
    final applied = await AppDataRoot.applyPendingRestore(
      documentsPathProvider: () => docsDir.path,
    );
    expect(applied, isTrue);
    expect(marker.existsSync(), isFalse);
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
    // 残留 .old_<ts> 已清理。
    expect(
      docsDir
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('.old_'))
          .isEmpty,
      isTrue,
    );

    // 幂等：无标记时再调返回 false。
    expect(
      await AppDataRoot.applyPendingRestore(
        documentsPathProvider: () => docsDir.path,
      ),
      isFalse,
    );
  });

  test('无效备份（无 manifest）抛 FormatException，不写标记', () async {
    final junkPath = '${docsDir.path}${Platform.pathSeparator}junk.zip';
    final archive = Archive()
      ..addFile(ArchiveFile('not_manifest.txt', 2, [1, 2]));
    await File(junkPath).writeAsBytes(ZipEncoder().encode(archive));

    await expectLater(
      BackupService.stageRestore(backupPath: junkPath, documentsDir: docsDir),
      throwsFormatException,
    );
    expect(
      File(
        '${docsDir.path}${Platform.pathSeparator}'
        '${AppDataRoot.pendingRestoreMarkerName}',
      ).existsSync(),
      isFalse,
    );
  });

  test('zip slip 防护：上跳条目被跳过，不落在暂存之外', () async {
    final evilPath = '${docsDir.path}${Platform.pathSeparator}evil.zip';
    final archive = Archive()
      ..addFile(ArchiveFile('backup_manifest.json', 2, utf8.encode('{"formatVersion":1}')))
      ..addFile(ArchiveFile('../evil.txt', 2, [9, 9]));
    await File(evilPath).writeAsBytes(ZipEncoder().encode(archive));

    await BackupService.stageRestore(
      backupPath: evilPath,
      documentsDir: docsDir,
    );

    final marker = File(
      '${docsDir.path}${Platform.pathSeparator}'
      '${AppDataRoot.pendingRestoreMarkerName}',
    );
    final stagingPath = (await marker.readAsString()).trim();
    expect(
      File('${docsDir.path}${Platform.pathSeparator}evil.txt').existsSync(),
      isFalse,
    );
    expect(
      Directory(stagingPath).listSync().whereType<File>().length,
      1, // 仅 manifest
    );
  });

  test('fail-safe：标记存在但暂存缺失 → 放弃恢复并清标记', () async {
    await AppDataRoot.writePendingRestoreMarker(
      documentsDir: docsDir,
      stagingPath:
          '${docsDir.path}${Platform.pathSeparator}nonexistent_staging',
    );
    final applied = await AppDataRoot.applyPendingRestore(
      documentsPathProvider: () => docsDir.path,
    );
    expect(applied, isFalse);
    expect(
      File(
        '${docsDir.path}${Platform.pathSeparator}'
        '${AppDataRoot.pendingRestoreMarkerName}',
      ).existsSync(),
      isFalse,
    );
    // 数据根未被触碰。
    expect(dataRoot.existsSync(), isTrue);
  });
}
