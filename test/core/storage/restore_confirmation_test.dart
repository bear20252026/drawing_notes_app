// 恢复确认状态机（DN-203，第三轮专家审计 2026-10-13）。
//
// 审计结论原文要点：`stageRestore` 在校验完备份包之后就写待恢复标记，
// **而确认对话框是在那之后才弹出来的**——于是「暂存后崩溃」「用户在确认框
// 上直接杀进程」「页面已卸载 (`if (!context.mounted) return;`)」「取消时清
// 标记失败」四条路径都会留下一枚下次启动即换根并删旧根的标记。
//
// 本文件钉 STAGED → CONFIRMED → APPLIED 三态：
// ① 暂存（STAGED）绝不产生破坏：只写 inert 暂存记录，反复启动都不换根；
// ② 确认（CONFIRMED）才写可触发标记，且确认时复核暂存结构；
// ③ 应用（APPLIED）只对带确认字段的标记生效；
// ④ 旧格式（≤1.17.65 的裸路径标记）按「未确认」处理——降级为暂存 + 留痕，
//    由设置页请用户重新确认，不猜它的来源意图；
// ⑤ 反向钉：正常路径必须照样换根成功（别把修复做成「恢复再也用不了」）。
import 'dart:convert';
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
    docsDir = await Directory.systemTemp.createTemp('dn203_docs_');
    supportDir = await Directory.systemTemp.createTemp('dn203_supp_');
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

  File markerNamed(String name) =>
      File('${supportDir.path}${Platform.pathSeparator}$name');

  /// 造一份「有内容的数据根」并打包，返回备份包路径。
  Future<String> backupOf({String marker = 'backup'}) async {
    await rootFile('documents/a.json').create(recursive: true);
    await rootFile('documents/a.json').writeAsString('{"t":"$marker"}');
    await rootFile('security/vault.key.json').create(recursive: true);
    await rootFile('security/vault.key.json').writeAsString('{"k":1}');
    await rootFile('thumbnails/x.png').create(recursive: true);
    await rootFile('thumbnails/x.png').writeAsBytes([1, 2, 3]);
    final backupPath =
        '${docsDir.path}${Platform.pathSeparator}$marker.zip';
    await BackupService.createBackup(
      dataRoot: dataRoot,
      destinationPath: backupPath,
    );
    return backupPath;
  }

  /// 把现网改成「与备份时点不同」的样子，好让换根结果可观测。
  Future<void> churnLiveRoot() async {
    await rootFile('documents/a.json').writeAsString('{"t":"live"}');
    await rootFile('documents/live_only.json').create(recursive: true);
  }

  Future<bool> apply() => AppDataRoot.applyPendingRestore(
    documentsPathProvider: () => docsDir.path,
    supportPathProvider: () => supportDir.path,
  );

  test('①暂存不是恢复：确认之前反复启动都不换根，现网一字未动', () async {
    final backupPath = await backupOf();
    await churnLiveRoot();
    final liveBefore = await rootFile('documents/a.json').readAsString();

    await BackupService.stageRestore(
      backupPath: backupPath,
      dataParentDir: supportDir,
    );

    expect(
      markerNamed(AppDataRoot.restoreStageMarkerName).existsSync(),
      isTrue,
      reason: '暂存事实要留痕，设置页才提醒得出来',
    );
    expect(
      markerNamed(AppDataRoot.pendingRestoreMarkerName).existsSync(),
      isFalse,
      reason: '确认之前绝不能存在可触发换根的标记',
    );

    // 崩溃/杀进程的等价类：什么都不做，重启 N 次。
    for (var i = 0; i < 3; i++) {
      expect(await apply(), isFalse, reason: '第 $i 次启动都不该换根');
    }
    expect(
      await rootFile('documents/a.json').readAsString(),
      liveBefore,
      reason: '现网内容必须一字未动',
    );
    expect(rootFile('documents/live_only.json').existsSync(), isTrue);
    // 暂存标记本身不受启动流程影响（既不被消费也不被清理）。
    expect(markerNamed(AppDataRoot.restoreStageMarkerName).existsSync(), isTrue);
  });

  test('②③确认后才换根，且确认后暂存标记让位给待恢复标记', () async {
    final backupPath = await backupOf();
    await churnLiveRoot();
    await BackupService.stageRestore(
      backupPath: backupPath,
      dataParentDir: supportDir,
    );

    expect(
      await AppDataRoot.confirmRestoreStage(parentDir: supportDir),
      RestoreStageDecision.confirmed,
    );
    expect(
      markerNamed(AppDataRoot.restoreStageMarkerName).existsSync(),
      isFalse,
      reason: '确认即消费暂存记录，避免同一暂存被确认两次',
    );
    final pending = markerNamed(AppDataRoot.pendingRestoreMarkerName);
    expect(pending.existsSync(), isTrue);
    final payload = jsonDecode(await pending.readAsString());
    expect(payload, isA<Map>(), reason: '确认标记是带字段的 JSON，不是裸路径');
    expect((payload as Map)['confirmedAtMs'], isA<int>(), reason: '确认时间戳是判据');

    expect(await apply(), isTrue);
    expect(
      await rootFile('documents/a.json').readAsString(),
      '{"t":"backup"}',
      reason: '确认后本次恢复照常生效',
    );
    expect(rootFile('documents/live_only.json').existsSync(), isFalse);
  });

  test('②之反向钉：没有暂存记录时确认是无操作，不会凭空产生标记', () async {
    expect(
      await AppDataRoot.confirmRestoreStage(parentDir: supportDir),
      RestoreStageDecision.noStagedRestore,
    );
    expect(
      markerNamed(AppDataRoot.pendingRestoreMarkerName).existsSync(),
      isFalse,
    );
    expect(await apply(), isFalse);
  });

  test('②确认时复核暂存：暂存在确认框停留期间被破坏则拒绝确认', () async {
    final backupPath = await backupOf();
    await BackupService.stageRestore(
      backupPath: backupPath,
      dataParentDir: supportDir,
    );
    final stagingPath = (await markerNamed(
      AppDataRoot.restoreStageMarkerName,
    ).readAsString()).trim();
    // 模拟上次解压被中断 / 磁盘满 / 人工删档：暂存还在，但已不是可用数据根。
    Directory('$stagingPath${Platform.pathSeparator}documents')
        .deleteSync(recursive: true);
    Directory('$stagingPath${Platform.pathSeparator}security')
        .deleteSync(recursive: true);

    expect(
      await AppDataRoot.confirmRestoreStage(parentDir: supportDir),
      RestoreStageDecision.stagingInvalid,
    );
    expect(
      markerNamed(AppDataRoot.pendingRestoreMarkerName).existsSync(),
      isFalse,
      reason: '坏暂存绝不能拿到可触发换根的标记',
    );
    expect(
      markerNamed(AppDataRoot.restoreStageMarkerName).existsSync(),
      isFalse,
      reason: '不合格就退掉提醒，别留一条永远确认不了的横幅',
    );
    expect(await apply(), isFalse);
  });

  test('放弃：暂存记录与暂存目录一并清掉，现网不受影响', () async {
    final backupPath = await backupOf();
    await churnLiveRoot();
    await BackupService.stageRestore(
      backupPath: backupPath,
      dataParentDir: supportDir,
    );
    final stagingPath = (await markerNamed(
      AppDataRoot.restoreStageMarkerName,
    ).readAsString()).trim();
    expect(Directory(stagingPath).existsSync(), isTrue);

    await AppDataRoot.discardRestoreStage(parentDir: supportDir);

    expect(markerNamed(AppDataRoot.restoreStageMarkerName).existsSync(), isFalse);
    expect(
      Directory(stagingPath).existsSync(),
      isFalse,
      reason: '放弃就要连暂存一起回收，否则磁盘上长期多一份全库副本',
    );
    expect(await apply(), isFalse);
    expect(
      await rootFile('documents/a.json').readAsString(),
      '{"t":"live"}',
    );
  });

  test('④旧格式裸路径标记按未确认处理：不自动换根，降级为暂存并留痕', () async {
    // 1.17.65 及更早：标记内容就是暂存目录的绝对路径，且它可能在用户确认之前写好。
    final backupPath = await backupOf();
    await churnLiveRoot();
    await BackupService.stageRestore(
      backupPath: backupPath,
      dataParentDir: supportDir,
    );
    final stagingPath = (await markerNamed(
      AppDataRoot.restoreStageMarkerName,
    ).readAsString()).trim();
    await markerNamed(AppDataRoot.restoreStageMarkerName).delete();
    await markerNamed(
      AppDataRoot.pendingRestoreMarkerName,
    ).writeAsString(stagingPath, flush: true);

    expect(
      await apply(),
      isFalse,
      reason: '无法判定用户是否确认过的旧标记，一律不自动换根',
    );
    expect(
      await rootFile('documents/a.json').readAsString(),
      '{"t":"live"}',
      reason: '现网必须原样',
    );
    // 降级成 inert 暂存：设置页据此请用户重新确认，而不是丢掉这次恢复。
    expect(markerNamed(AppDataRoot.restoreStageMarkerName).existsSync(), isTrue);
    expect(
      markerNamed(AppDataRoot.pendingRestoreMarkerName).existsSync(),
      isFalse,
    );
    expect(
      File(
        '${supportDir.path}${Platform.pathSeparator}'
        '${AppDataRoot.restoreFailureLogName}',
      ).readAsStringSync(),
      contains('unconfirmed_marker'),
      reason: '降级这件事要能在诊断里回溯',
    );
    // 重新确认可继续（升级在途的那次恢复不作废）。
    expect(
      await AppDataRoot.confirmRestoreStage(parentDir: supportDir),
      RestoreStageDecision.confirmed,
    );
    expect(await apply(), isTrue);
    expect(
      await rootFile('documents/a.json').readAsString(),
      '{"t":"backup"}',
    );
  });

  test('④旧格式标记指向的暂存已不存在：只清标记，不造出半个恢复', () async {
    await markerNamed(AppDataRoot.pendingRestoreMarkerName).writeAsString(
      '${supportDir.path}${Platform.pathSeparator}早已被回收的暂存',
      flush: true,
    );
    final live = rootFile('documents/live.json');
    await live.create(recursive: true);
    await live.writeAsString('{"t":"live"}');

    expect(await apply(), isFalse);
    expect(
      markerNamed(AppDataRoot.pendingRestoreMarkerName).existsSync(),
      isFalse,
    );
    expect(
      markerNamed(AppDataRoot.restoreStageMarkerName).existsSync(),
      isFalse,
      reason: '暂存都没了，提醒也就没有意义',
    );
    expect(await live.readAsString(), '{"t":"live"}');
  });

  test('损坏 JSON 的确认标记同样不当作已确认（不拿半写状态换根）', () async {
    await markerNamed(AppDataRoot.pendingRestoreMarkerName).writeAsString(
      '{"stagingPath":"/tmp/x"', // 写到一半截断
      flush: true,
    );
    await rootFile('documents/keep.json').create(recursive: true);
    await rootFile('documents/keep.json').writeAsString('{"t":"keep"}');

    expect(await apply(), isFalse);
    expect(rootFile('documents/keep.json').existsSync(), isTrue);
  });
}
