// M4（第三轮专家审计）：`.bak` 从「只留最近一版」升级为**三级轮转**。
//
// 旧形状的问题很窄但致命：主文件与 `.bak` 同时损坏（或 `.bak` 被上一次失败
// 的写吃掉）时，读路径一个字节都拿不到，用户那篇笔记就永久没了——而盘上
// 明明还躺着上上一版、上上上一版。轮转的意义就是让「最近一版坏了」这件事
// 有东西可退。
//
// 本文件钉四组：
//  ① 写侧轮转：连续保存 N 版 ⇒ 盘上恰好三级，且级别越老内容越老；
//  ② 读侧回退：主文件损坏时按级别从近到远取第一份能读的；
//  ③ 轮转中途失败（注入）⇒ 不丢已有备份、不吞掉主文件；
//  ④ 删除/回收站/图片回收三个消费侧都认得三级（漏一个就是把还能读的画布
//     引用的图片判成孤儿）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/storage_directories.dart';
import 'package:drawing_notes_app/core/storage/storage_secret_session.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/storage_write_pipeline.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;
  late StorageService repo;
  late StorageDirectories dirs;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_rotation_');
    dirs = StorageDirectories(directoryProvider: () async => tempDir);
    await dirs.ensureDocuments();
    // 明文：本文件验的是**文件面**契约（哪一级存在、内容是谁），掺加密只会让
    // 逐字节断言变模糊。加密腿的回退由 storage_bak_recovery_test 钉。
    repo = StorageService(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    StorageWritePipeline.backupFaultForTest = null;
    await deleteTempDirWithRetry(tempDir);
  });

  Directory docsDir() => Directory(
    '${tempDir.path}${Platform.pathSeparator}documents',
  );

  String pathOf(String id) =>
      '${docsDir().path}${Platform.pathSeparator}$id.json';

  DrawingDocument doc(String id, String title) =>
      DrawingDocument(id: id, title: title, width: 400, height: 300);

  String markerOf(String id) => utf8.decode(File(pathOf(id)).readAsBytesSync());

  /// 三级备份路径（0 = 最近一版，沿用历史命名 `.bak`）。
  File bakOf(String id, int level) =>
      File(StorageWritePipeline.bakLevelPath(pathOf(id), level));

  group('① 写侧：三级轮转，级别越老内容越老', () {
    test('连续保存四版 ⇒ 盘上恰好三级，内容依次是 v3/v2/v1', () async {
      await repo.save(doc('rot_a', 'v1'));
      await repo.save(doc('rot_a', 'v2'));
      await repo.save(doc('rot_a', 'v3'));
      await repo.save(doc('rot_a', 'v4'));

      expect(
        markerOf('rot_a'),
        contains('v4'),
        reason: '主文件是最新一版',
      );
      expect(bakOf('rot_a', 0).readAsStringSync(), contains('v3'));
      expect(bakOf('rot_a', 1).readAsStringSync(), contains('v2'));
      expect(bakOf('rot_a', 2).readAsStringSync(), contains('v1'));

      // 级别数就是契约：多一级少一级都要在这里变红。
      expect(StorageWritePipeline.backupLevels, 3);
      for (var level = 0; level < StorageWritePipeline.backupLevels; level++) {
        expect(bakOf('rot_a', level).existsSync(), isTrue, reason: '第 $level 级缺失');
      }
    });

    test('只写过一次 ⇒ 只有主文件，没有任何备份级别', () async {
      await repo.save(doc('rot_b', 'only'));
      expect(File(pathOf('rot_b')).existsSync(), isTrue);
      for (var level = 0; level < StorageWritePipeline.backupLevels; level++) {
        expect(
          bakOf('rot_b', level).existsSync(),
          isFalse,
          reason: '首写没有「上一版」可备份——凭空造一份等于把同一个字节存两遍',
        );
      }
    });

    test('命名契约：0 级沿用 `.bak`，更老的是 `.bak.N`（备份打包排除模式认得）', () async {
      await repo.save(doc('rot_c', 'v1'));
      await repo.save(doc('rot_c', 'v2'));

      // `.bakN`（无点）不会被 AppDataRoot.restoreExcludedPattern 的
      // `\.(tmp|bak)(\..*)?$` 匹配——那会把轮转备份打进备份包。命名不是细节，
      // 是这条正则的输入。
      expect(bakOf('rot_c', 0).path, endsWith('.json.bak'));
      expect(bakOf('rot_c', 1).path, endsWith('.json.bak.1'));
      expect(bakOf('rot_c', 2).path, endsWith('.json.bak.2'));
      for (var level = 0; level < StorageWritePipeline.backupLevels; level++) {
        expect(
          RegExp(r'\.(tmp|bak)(\..*)?$').hasMatch(bakOf('rot_c', level).path),
          isTrue,
          reason: '第 $level 级必须被备份打包的排除模式认出来',
        );
      }
    });
  });

  group('② 读侧：主文件损坏时按级别从近到远回退', () {
    test('主文件损坏 ⇒ 退到最近一级（.0）', () async {
      await repo.save(doc('rot_d', 'v1'));
      await repo.save(doc('rot_d', 'v2'));
      await repo.save(doc('rot_d', 'v3'));

      // 主文件写坏（截断到不成 JSON）。
      File(pathOf('rot_d')).writeAsBytesSync(Uint8List.fromList([1, 2, 3]));

      final loaded = await repo.load('rot_d');
      expect(loaded, isNotNull, reason: '主文件损坏时必须从备份恢复');
      // 级别 0 装的是「这次保存之前的那一版」= v2（v3 是主文件，已损坏）。
      expect(loaded!.title, 'v2');
    });

    test('主文件与最近一级都损坏 ⇒ 退到更老的一级（.1）', () async {
      await repo.save(doc('rot_e', 'v1'));
      await repo.save(doc('rot_e', 'v2'));
      await repo.save(doc('rot_e', 'v3'));

      File(pathOf('rot_e')).writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      bakOf('rot_e', 0).writeAsBytesSync(Uint8List.fromList([4, 5, 6]));

      final loaded = await repo.load('rot_e');
      expect(loaded, isNotNull, reason: '这正是 M4 存在的理由：最近一版也坏了');
      // 级别 1 = v1（级别 0 是 v2、已损坏）。
      expect(loaded!.title, 'v1');
    });

    test('三级全坏 ⇒ 如实抛给调用方（不静默返回 null）', () async {
      await repo.save(doc('rot_f', 'v1'));
      await repo.save(doc('rot_f', 'v2'));

      for (var level = 0; level < StorageWritePipeline.backupLevels; level++) {
        if (bakOf('rot_f', level).existsSync()) {
          bakOf('rot_f', level).writeAsBytesSync(Uint8List.fromList([9]));
        }
      }
      File(pathOf('rot_f')).writeAsBytesSync(Uint8List.fromList([9]));

      await expectLater(
        repo.load('rot_f'),
        throwsA(isA<Object>()),
        reason: '一级都读不出来时必须把损坏如实抛给调用方——静默 null 会让用户'
            '以为笔记被删了',
      );
    });

    test('主文件缺失但备份在 ⇒ 取得到（rename 期崩溃的残留形态）', () async {
      await repo.save(doc('rot_g', 'v1'));
      await repo.save(doc('rot_g', 'v2'));
      File(pathOf('rot_g')).deleteSync();

      final loaded = await repo.load('rot_g');
      expect(loaded, isNotNull);
      // 两次保存 ⇒ 级别 0 = v1（v2 的主文件已被删）。
      expect(loaded!.title, 'v1');
    });
  });

  group('③ 轮转中途失败：不丢已有备份、不吞主文件', () {
    late StorageWritePipeline pipeline;

    setUp(() {
      pipeline = StorageWritePipeline(
        directories: dirs,
        secrets: StorageSecretSession(),
        keyProvider: null,
      );
    });

    Uint8List bytesOf(String marker) =>
        Uint8List.fromList(utf8.encode('{"marker":"$marker"}'));

    test('轮转到一半失败 ⇒ 主文件逐字节活着，已搬动的级别内容不变', () async {
      await pipeline.writeSealedBytes('rot_h', bytesOf('v1'));
      await pipeline.writeSealedBytes('rot_h', bytesOf('v2'));
      await pipeline.writeSealedBytes('rot_h', bytesOf('v3'));
      final path = pathOf('rot_h');
      final v3 = File(path).readAsBytesSync();
      final bak1 = bakOf('rot_h', 1).readAsBytesSync(); // v1

      // 在第 1 级往第 2 级搬的那一步注入失败（等价类：磁盘满 / 权限 / 被杀软拦）。
      StorageWritePipeline.backupFaultForTest = (id, level, from, to) =>
          id == 'rot_h' && level == 1;

      await expectLater(
        pipeline.writeSealedBytes('rot_h', bytesOf('v4')),
        throwsA(isA<FileSystemException>()),
      );
      StorageWritePipeline.backupFaultForTest = null;

      expect(
        File(path).readAsBytesSync(),
        equals(v3),
        reason: '备份失败发生在换入之前：主文件必须还是出事前的这一版',
      );
      // 注入点在第 1 级的写入：第 0 级**已经**被本轮的新字节（v3）覆盖，
      // 而第 1 级仍保留着它原本的 v1——这正是「写目标失败时来源完好」的形状。
      expect(
        bakOf('rot_h', 0).readAsBytesSync(),
        equals(bytesOf('v3')),
        reason: '第 0 级先写成功、第 1 级写入失败 ⇒ 0 级已是新字节',
      );
      expect(
        bakOf('rot_h', 1).readAsBytesSync(),
        equals(bak1),
        reason: '注入点在第 1 级 ⇒ 第 1 级自己必须原样还在（不能写一半）',
      );
    });

    test('注入解除后同一篇仍能正常写进去（失败没有毒住写尾队列）', () async {
      await pipeline.writeSealedBytes('rot_i', bytesOf('v1'));
      StorageWritePipeline.backupFaultForTest = (id, level, from, to) =>
          id == 'rot_i' && level == 0;
      await expectLater(
        pipeline.writeSealedBytes('rot_i', bytesOf('v2')),
        throwsA(isA<FileSystemException>()),
      );
      StorageWritePipeline.backupFaultForTest = null;

      await pipeline.writeSealedBytes('rot_i', bytesOf('v3'));
      expect(
        File(pathOf('rot_i')).readAsBytesSync(),
        equals(bytesOf('v3')),
      );
      expect(
        bakOf('rot_i', 0).readAsBytesSync(),
        equals(bytesOf('v1')),
        reason: '第 0 级备份的是这次写入之前的那一版（v1）',
      );
    });
  });

  group('④ 消费侧：三个 `.bak` 读者都认得三级', () {
    test('回收站：三级侧车都随正文一起消失', () async {
      await repo.save(doc('rot_j', 'v1'));
      await repo.save(doc('rot_j', 'v2'));
      await repo.save(doc('rot_j', 'v3'));

      expect(await repo.delete('rot_j'), isTrue);

      expect(File(pathOf('rot_j')).existsSync(), isFalse);
      for (var level = 0; level < StorageWritePipeline.backupLevels; level++) {
        expect(
          bakOf('rot_j', level).existsSync(),
          isFalse,
          reason: '第 $level 级侧车留着就是复活种子（load 读得回来、同步判成删除）',
        );
      }
      expect(await repo.load('rot_j'), isNull);
    });

    test('回收站：只剩轮转侧车（正文位空）也删得掉', () async {
      await repo.save(doc('rot_k', 'v1'));
      await repo.save(doc('rot_k', 'v2'));
      await repo.save(doc('rot_k', 'v3'));
      File(pathOf('rot_k')).deleteSync();

      expect(
        await repo.delete('rot_k'),
        isTrue,
        reason: '正文没了不代表这篇不存在——盘上还有两版可读',
      );
      for (var level = 0; level < StorageWritePipeline.backupLevels; level++) {
        expect(bakOf('rot_k', level).existsSync(), isFalse);
      }
      expect(await repo.load('rot_k'), isNull);
    });

    test('列表：备份级别不算一篇文档（不产生幽灵笔记）', () async {
      await repo.save(doc('rot_l', 'v1'));
      await repo.save(doc('rot_l', 'v2'));
      File(pathOf('rot_l')).deleteSync(); // 只剩侧车

      expect(
        (await repo.listDocuments()).map((m) => m.id),
        isNot(contains('rot_l')),
        reason: '列表只认 `.json`；备份级别是回退材料，不是文档',
      );
    });
  });
}
