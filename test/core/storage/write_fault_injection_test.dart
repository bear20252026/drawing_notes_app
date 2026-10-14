// 批次 D（第三轮专家审计 2026-10-13）：磁盘故障注入矩阵——**正常保存腿**。
//
// 前两批把「懒迁移腿」和「块文档腿」的失败面钉住了（`.bak` 被占、落盘前复查、
// 时序屏障），但 `StorageService.save` 这条**用户最常走**的腿一直是空白：它走
// `writeSealedBytes`（tmp → copy .bak → replaceWithTemp），失败后
// ① 正式文件字节必须原样活着，② 不许留 `.tmp` 残留，③ 每个 id 的写尾队列必须
// 继续可用——那三条此前只有别的腿在证。另有崩溃残留一行：断电留下的 `.tmp`
// 绝不能被列表/读路径当成一篇文档，否则首页会出现一篇打不开的幽灵笔记。
//
// 刻意不写「断言 tmp 会被清扫」：本仓现在**没有** documents/ 的 tmp 清扫器
// （只有保险库密钥侧有一条），那是现状而不是承诺，钉死了反而挡住将来的改进。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/storage/storage_directories.dart';
import 'package:drawing_notes_app/core/storage/storage_secret_session.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/storage_write_pipeline.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;
  late StorageService repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('write_fault_');
    // 不给 keyProvider：明文落盘是产品默认形态，本矩阵要验的是**文件面**契约，
    // 掺进加密只会让字节断言变模糊。
    repo = StorageService(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  Directory docsDir() => Directory(
    '${tempDir.path}${Platform.pathSeparator}documents',
  );

  String pathOf(String id) =>
      '${docsDir().path}${Platform.pathSeparator}$id.json';

  List<String> tmpResidue() => docsDir()
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.tmp'))
      .map((f) => f.path.split(Platform.pathSeparator).last)
      .toList();

  DrawingDocument doc(String id, String title) =>
      DrawingDocument(id: id, title: title, width: 400, height: 300);

  group('正常保存腿：备份位被占住时的三件套', () {
    test('备份失败 ⇒ 抛错、原字节逐字节活着、不留 .tmp', () async {
      await repo.save(doc('fault_a', '第一版'));
      final before = File(pathOf('fault_a')).readAsBytesSync();

      // 把 `.bak` 目标位占成目录：copy 必失败（与 S-003/块文档那两条同口径）。
      final blocker = Directory('${pathOf('fault_a')}.bak');
      blocker.createSync(recursive: true);

      await expectLater(
        repo.save(doc('fault_a', '第二版')),
        throwsA(isA<FileSystemException>()),
      );

      expect(
        File(pathOf('fault_a')).readAsBytesSync(),
        equals(before),
        reason: '失败的保存不许吃掉用户唯一的上一版——那是回退的唯一依据',
      );
      expect(
        tmpResidue(),
        isEmpty,
        reason: '失败路径必须回收自己的临时文件，不留半份内容',
      );
      expect(
        blocker.existsSync(),
        isTrue,
        reason: '失败清理只许动自己建的东西；占位的目录不是它造的，不能顺手删',
      );
    });

    test('解除阻塞后同一 id 必须还能写进去（写尾队列没被那次失败毒住）', () async {
      await repo.save(doc('fault_b', '第一版'));
      final path = pathOf('fault_b');
      final blocker = Directory('$path.bak')..createSync(recursive: true);
      await expectLater(repo.save(doc('fault_b', '坏的那次')), throwsA(isA<Object>()));
      blocker.deleteSync(recursive: true);

      await repo.save(doc('fault_b', '第三版'));

      final text = utf8.decode(File(path).readAsBytesSync());
      expect(
        text,
        contains('第三版'),
        reason: '一次失败之后队列若还挂着被拒的 Future，这一笔就永远落不了地',
      );
      expect(text, isNot(contains('坏的那次')));
      expect(tmpResidue(), isEmpty);
    });

    test('一篇卡在失败链上时，另一篇的保存不受影响（per-id 尾队列不互堵）', () async {
      await repo.save(doc('fault_c', 'C1'));
      final blocker = Directory('${pathOf('fault_c')}.bak')
        ..createSync(recursive: true);
      await expectLater(
        repo.save(doc('fault_c', 'C2')),
        throwsA(isA<Object>()),
      );

      // 不同 id 走不同的尾队列：这次必须照常成功，且不能被 fault_c 拖住。
      await repo.save(doc('fault_d', 'D1'));
      expect(
        utf8.decode(File(pathOf('fault_d')).readAsBytesSync()),
        contains('D1'),
      );

      blocker.deleteSync(recursive: true);
    });

    test('连续两次失败 + 一次成功：每次都回收 tmp，最后一次真落地', () async {
      await repo.save(doc('fault_e', '初版'));
      final blocker = Directory('${pathOf('fault_e')}.bak')
        ..createSync(recursive: true);

      for (var i = 0; i < 2; i++) {
        await expectLater(
          repo.save(doc('fault_e', '失败$i')),
          throwsA(isA<Object>()),
        );
      }
      expect(tmpResidue(), isEmpty);

      blocker.deleteSync(recursive: true);
      await repo.save(doc('fault_e', '终于落地板'));
      expect(
        utf8.decode(File(pathOf('fault_e')).readAsBytesSync()),
        contains('终于落地板'),
      );
      expect(tmpResidue(), isEmpty, reason: '成功路径同样不得留下临时文件');
    });
  });

  group('崩溃残留：上一轮断电留下的 .tmp', () {
    test('残留 tmp 不算一篇文档（列表不多一条、读的还是真文档）', () async {
      await repo.save(doc('residue_a', '真文档'));
      // 模拟「tmp 写完、rename 之前断电」留下的半份内容。
      final stale = File('${pathOf('residue_a')}.write_crashresidue.tmp');
      stale.writeAsStringSync('{"document":{"id":"residue_a","title":"半截的"}}');

      final metas = await repo.listDocuments();
      expect(
        metas.map((m) => m.id),
        ['residue_a'],
        reason: '首页绝不能多出一篇打不开的幽灵笔记——那会让用户以为笔记坏了',
      );
      final loaded = await repo.load('residue_a');
      expect(loaded?.title, '真文档');
      expect(loaded?.id, 'residue_a');

      // 残留存在时，新的成功保存照样按正常契约落盘（不被半份内容干扰）。
      await repo.save(doc('residue_a', '保存后的'));
      expect(
        utf8.decode(File(pathOf('residue_a')).readAsBytesSync()),
        contains('保存后的'),
      );
      expect(
        File('${pathOf('residue_a')}.write_crashresidue.tmp').readAsStringSync(),
        contains('半截的'),
        reason: '本批不主张「残留会被清扫」——只主张它不碍事',
      );
    });

    test('拿残留文件名当 id 去 load ⇒ 被 id 白名单挡掉，不读盘上那个文件', () async {
      await repo.save(doc('residue_b', '正文'));
      // `.json.<token>.tmp` 里有 `.`，不是合法文档 id；路径遍历防护必须先挡住，
      // 否则「文件名即 id」这件事会把半份内容读进编辑器。
      await expectLater(
        repo.load('residue_b.json.whatever.tmp'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
  // 故障注入钩子挂在 StorageWritePipeline 上，所以这一组直接驱动
  // `writeSealedBytes`——走 StorageService 反而碰不到它（那条只是调用方之一）。
  group('批次 D 故障注入：tmp 第一笔字节 与 改名换入 这两格', () {
    late StorageWritePipeline pipeline;

    setUp(() async {
      final dirs = StorageDirectories(directoryProvider: () async => tempDir);
      await dirs.ensureDocuments();
      // 不给 keyProvider：本组验的是文件面，明文最便于逐字节断言。
      pipeline = StorageWritePipeline(
        directories: dirs,
        secrets: StorageSecretSession(),
        keyProvider: null,
      );
    });

    tearDown(() {
      pipeline.tmpPathObserverForTest = null;
      pipeline.renameBarrierForTest = null;
    });

    Uint8List bytesOf(String marker) =>
        Uint8List.fromList(utf8.encode('{"marker":"$marker"}'));

    test('(a) tmp 写第一笔字节就失败 ⇒ 抛错、原文件没动、既不建 .bak 也不留 tmp', () async {
      await pipeline.writeSealedBytes('inj_a', bytesOf('v1'));
      final path = pathOf('inj_a');
      final before = File(path).readAsBytesSync();

      String? observed;
      pipeline.tmpPathObserverForTest = (id, tmpPath) {
        observed = tmpPath;
        // 把 tmp 路径占成目录 ⇒ writeAsBytes 必失败。代表的等价类是
        // 「磁盘满 / 目录权限 / 杀软抢占新建文件」，不是特指某一种。
        Directory(tmpPath).createSync(recursive: true);
      };

      await expectLater(
        pipeline.writeSealedBytes('inj_a', bytesOf('v2')),
        throwsA(isA<FileSystemException>()),
      );
      expect(observed, isNotNull, reason: '钩子没被调到 = 这条用例什么都没验');

      // 收拾本用例自己造的占位目录（生产不会造它，它也不是数据）。
      final blocker = Directory(observed!);
      if (blocker.existsSync()) blocker.deleteSync();

      expect(File(path).readAsBytesSync(), equals(before));
      expect(
        File('$path.bak').existsSync(),
        isFalse,
        reason: '备份排在 tmp 之后：tmp 都没写成，就不该凭空多出一份 .bak',
      );
      expect(tmpResidue(), isEmpty);
    });

    test('(b) 改名失败 ⇒ 上一版逐字节活着、tmp 被回收、.bak 正是这一版', () async {
      await pipeline.writeSealedBytes('inj_b', bytesOf('v1'));
      await pipeline.writeSealedBytes('inj_b', bytesOf('v2'));
      final path = pathOf('inj_b');
      final v2 = File(path).readAsBytesSync();
      AuditLogger.clear();

      pipeline.renameBarrierForTest = (id, tmpPath) async {
        // 制造 rename 失败的**等价类**：把 tmp 移走 ⇒ rename 抛错，Linux 与
        // Windows 同判。真实共享冲突那一格由 storage_encryption_test:225 的
        // Windows 用例覆盖（它只在 Windows 上跑），两条不互相顶替。
        File(tmpPath).deleteSync();
      };

      await expectLater(
        pipeline.writeSealedBytes('inj_b', bytesOf('v3')),
        throwsA(isA<FileSystemException>()),
      );

      expect(
        File(path).readAsBytesSync(),
        equals(v2),
        reason: '换入失败绝不能把上一版一起带走',
      );
      expect(tmpResidue(), isEmpty);
      expect(
        File('$path.bak').readAsBytesSync(),
        equals(v2),
        reason: '备份先于换入：出事的这一刻 .bak 里必须正好是被保住的 v2',
      );
      expect(
        AuditLogger.snapshot().any(
          (l) => l.contains('storage.write_rolled_back_from_backup'),
        ),
        isTrue,
        reason: '兜底删过正式文件又换入失败 ⇒ 必须由回滚放回去，且留下可诊断痕迹',
      );
    });

    test('(b2) 首写就撞上改名失败 ⇒ 盘上没有半份文件，也没有 .bak 与 tmp', () async {
      // 诚实记录后果：这一笔新内容**确实丢了**（没有上一版可保）。本用例主张的是
      // 「不留下半份文件骗过下一次读」，不是「不丢数据」。
      pipeline.renameBarrierForTest = (id, tmpPath) async {
        File(tmpPath).deleteSync();
      };

      await expectLater(
        pipeline.writeSealedBytes('inj_c', bytesOf('only')),
        throwsA(isA<FileSystemException>()),
      );

      expect(File(pathOf('inj_c')).existsSync(), isFalse);
      expect(File('${pathOf('inj_c')}.bak').existsSync(), isFalse);
      expect(tmpResidue(), isEmpty);
      expect(await repo.load('inj_c'), isNull);
    });
  });
}