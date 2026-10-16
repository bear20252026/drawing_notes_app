// 孤儿原子写临时文件的清扫（审计 2026-10-16 新发现）。
//
// 缺陷形状：写 tmp → rename 换入这套原子写在本仓有 **8 个生产者**（实测
// `grep ".LocalIdGenerator.next('"`：`write` 5 处、`thumb` 2 处、`oplog` 1 处），
// 失败路径各自都清了 tmp，但**进程在 write 与 rename 之间被杀**时留下的那一份没人回收
// ——只有保险库那条腿有清扫（`vault_key_service._sweepStaleTmpFiles`）。「一修就漏七处」。
//
// 实测证据（本机真实数据根 `Documents/绘图笔记数据/`，2026-10-16 只读列出、未删）：
// **7 枚**孤儿，横跨三个目录、两种前缀：
//   · `documents/`  4 枚 `*.write_*.tmp`（最老 2026-09-04 07:18，最大 1,546,137 字节）
//   · `notebooks/`  2 枚 `*.write_*.tmp`（最新 2026-09-06 14:32，最大 4,644,724 字节）
//   · `thumbnails/` 1 枚 `*.thumb_*.tmp`
//   前六枚合计 7,649,024 字节（≈7.3 MB），每枚里面都是**整份正文的副本**——保险库那条腿
//   的注释把同类残留定性为「隐私残留」，那这些同样是。
//   `blockdocs/` 今天没有残留 ⇒ 那条腿的接线是**预防**，不是已观测到的漏（见用例⑤）。
//
// 本文件钉住判据的五个面，每一面都是「做错一种就出事」的形状：
//   ① 命名（两半各自都得能红）：以 `.tmp` 结尾 **且** 最后一段是 `LocalIdGenerator`
//      自己的 id 形状。前者挡住 `<目标>.tmp.<时间>.<十六进制>` 这一族与 `.bak`；
//      后者是**授权边界**——没有它，递归扫整个数据根就等于替别人的 `.tmp` 做主。
//      判据只有 [LocalIdGenerator.generatedIdPattern] 这一份定义，测试直接调它，
//      不抄第二份（抄了就是本仓「一份判据 N 份副本」那一族的复发）。
//   ② 时间：超过 10 分钟才删（在途写是秒级，这道线保证不抢删并发写入中的文件）；
//   ③ 族别：`write`/`thumb`/`oplog` 三家前缀都得被同一条判据接住（只认 `write_`
//      就是当着「修一条漏五条」的面把风险切掉一半，见 M4）；
//   ④ 范围：正式 `.json` 与回滚用的 `.bak` 永不触碰（递归时尤其要钉）；
//   ⑤ 接线：画布腿从数据根递归扫一次、块文档腿本地扫一次——**光有判据没接上等于没修**。
//
// 突变自证（五条都实测过；计数是**本文件单独跑**的 +绿 −红，基线 8 全绿）：
//   M1 去掉年龄判据            ⇒ +4 −4（新鲜在途 tmp 被抢删：只删超龄/审计/两条接线）
//   M2 去掉形状授权那一半      ⇒ +7 −1（**只有判据表红**——见下）
//   M3 去掉后缀、任一段像就当 ⇒ +7 −1（同样**只有判据表红**）
//   M4 收窄回只认 `write_`     ⇒ +5 −3（判据表 + 三家前缀 + 画布接线的 thumbnails 那一格）
//   M5 把两处接线短路掉         ⇒ +6 −2（两条接线用例红：文件还躺着）
//
// M2/M3 只能被判据表抓到，说明这一格的**全部**裁决力都在那张表上：行为用例造的文件
// 都顺手同时满足两半，改坏任一半都不会让「实际删了什么」发生变化。这不是表多余，
// 而是「canary 必须与判据共用同一份定义」的实际收益——所以表里既有本机实测原名、
// 也有 `LocalIdGenerator.next()` 现产的名字，两头都钉住。
//
// 诚实说明：M3 那一格（`x.json.write_….bak`，带生成器 id 却以 `.bak` 结尾）钉的是
// 「后缀」这半边，而**本仓目前没有生产者**会造出这种名字（`.bak` 一律是 `<目标>.bak`，
// 不带 id）。所以 M3 测的是纵深防御的一格，不是某个真实残留。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/stale_tmp_cleanup.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';

import '../../helpers/temp_dir_cleanup.dart';

/// 2026-10-16 从本机真实数据根**原样抄下来**的三枚孤儿名字（三种前缀、三个目录）。
const _measuredWrite1 =
    'doc_hlzc0d2psw_0000_1ra34y1.json.write_hlzc0xjyt5_0019_0qc7mzs.tmp';
const _measuredWrite2 =
    'notebook_hm0r49aofy_0001_1xb5m9j.json.write_hm1vdk5d5s_000g_1bq2lc4.tmp';
const _measuredThumb =
    'doc_hm0xbm1q2h_0001_1samrv2.png.thumb_hm1gvu0aa0_002t_04uumwz.tmp';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('stale_tmp_');
    AuditLogger.clear();
  });

  tearDown(() async {
    await deleteTempDirWithRetry(root);
  });

  /// 造一个文件并把修改时间拨到 [age] 之前（默认「刚刚」= 在途）。
  Future<File> put(String rel, {Duration age = Duration.zero}) async {
    final f = File('${root.path}${Platform.pathSeparator}$rel');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(Uint8List.fromList([1, 2, 3, 4]), flush: true);
    f.setLastModifiedSync(DateTime.now().subtract(age));
    return f;
  }

  /// 孤儿名字**由生成器自己产**（与八条写腿同一来源）：这样判据、写腿、用例三者
  /// 永远同步移动，不会各抄一份形状、改一处悄悄漏三处。
  String orphan(String target, [String kind = 'write']) =>
      '$target.${LocalIdGenerator.next(kind)}.tmp';

  const stale = Duration(minutes: 30);

  group('判据五个面', () {
    test('判据表：与清扫共用同一份定义，两半各自都得能红', () {
      final shapes = <(String, bool)>[
        // ── 该删：本机实测原名（write / thumb 两族）+ 生成器现产 ──
        (_measuredWrite1, true),
        (_measuredWrite2, true),
        (_measuredThumb, true),
        (orphan('gen.json', 'write'), true),
        (orphan('side.json', 'oplog'), true),
        (orphan('t.png', 'thumb'), true),
        // ── 不该删 ──
        ('somebody-else.tmp', false), // 没有生成器 id ⇒ 不在授权范围内
        ('live.json', false),
        ('d.json.bak', false),
        ('trash.meta.tmp', false), // 回收站那条腿用的是裸 .tmp，不带 id
        (
          'all_docs_tags.json.tmp.1721123456789012.ab12cd34',
          false,
        ), // 点后缀那一族：由保险库自己的前缀清扫负责
        (
          'doc_hm0xbm1q2h_0001_1samrv2.json.write_hm1gvsvt4h_002p_1y8wrh6.bak',
          false,
        ), // M3 那一格：带 id 但不是 .tmp 结尾
      ];
      // 分母下限先于结论：表被改成「全是同一类」时，判据塌空也照样「全对」。
      expect(shapes.length, greaterThanOrEqualTo(10), reason: '表本身缩水了');
      expect(
        shapes.where((e) => e.$2).length,
        greaterThanOrEqualTo(3),
        reason: '正控不足⇒「什么都不删」也能全绿',
      );
      expect(
        shapes.where((e) => !e.$2).length,
        greaterThanOrEqualTo(4),
        reason: '反向锁不足⇒「见 .tmp 就删」也能全绿',
      );
      for (final (name, want) in shapes) {
        expect(
          isStaleLocalIdTempName(name),
          want,
          reason: '$name 应为 $want（①：必须以 .tmp 结尾且末段是生成器形状）',
        );
      }
    });

    test('三家前缀同判（③）：write / thumb / oplog 超龄的都走，缺一家就是漏一条', () async {
      final w = await put('documents/${orphan('a.json', 'write')}', age: stale);
      final t = await put('thumbnails/${orphan('b.png', 'thumb')}', age: stale);
      final o = await put('documents/${orphan('c.json', 'oplog')}', age: stale);

      expect(await sweepStaleTempFiles(root, auditScope: 'fam', recursive: true), 3);
      for (final f in [w, t, o]) {
        expect(f.existsSync(), isFalse, reason: '${f.path} 该被同一条判据接住');
      }
    });

    test('只删超龄的；新鲜、无关、正式、.bak 全不碰（①②④）', () async {
      final gone = await put('documents/${orphan('a.json')}', age: stale);
      final fresh = await put('documents/${orphan('b.json')}');
      final unrelated = await put('documents/somebody-else.tmp', age: const Duration(hours: 3));
      final real = await put('documents/c.json', age: const Duration(hours: 3));
      final backup = await put('documents/d.json.bak', age: const Duration(hours: 3));

      final n = await sweepStaleTempFiles(root, auditScope: 'test', recursive: true);

      expect(n, 1, reason: '只有那一枚孤儿 tmp 该走');
      expect(gone.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue, reason: '在途写入的文件不能抢删（②）');
      expect(unrelated.existsSync(), isTrue, reason: '不在授权形状内（①）');
      expect(real.existsSync(), isTrue, reason: '正式文件永不被碰（④）');
      expect(backup.existsSync(), isTrue, reason: '.bak 是崩溃恢复的唯一依托（④）');
      expect(
        AuditLogger.snapshot().any(
          (l) => l.contains('storage.stale_tmp_swept') && l.contains('test:n=1'),
        ),
        isTrue,
        reason: '删过就要留下可查的记录，数量也要在',
      );
    });

    test('没删到东西就不落审计（否则日志会被每轮一次的空扫填满）', () async {
      await put('documents/${orphan('live.json')}');
      // 递归扫：这样「返回 0」的理由只能是年龄判据，不能是浅扫没看见。
      expect(
        await sweepStaleTempFiles(root, auditScope: 'test', recursive: true),
        0,
      );
      expect(
        AuditLogger.snapshot().any((l) => l.contains('stale_tmp_swept')),
        isFalse,
      );
    });

    test('recursive=false 只扫一层；嵌套子目录要 recursive=true 才覆盖', () async {
      final nested = await put('notebooks/n1/media/${orphan('e.json')}', age: stale);
      expect(
        await sweepStaleTempFiles(root, recursive: false),
        0,
        reason: '浅扫不该假装成功（返回 0 就是 0）',
      );
      expect(nested.existsSync(), isTrue);
      expect(await sweepStaleTempFiles(root, recursive: true), 1);
      expect(
        nested.existsSync(),
        isFalse,
        reason: '媒体/PDF 导入/缩略图那几条腿的 tmp 落在子目录里，只能靠递归覆盖',
      );
    });

    test('目录不存在 ⇒ 返回 0 而不是抛（清扫不能变成新故障源）', () async {
      expect(
        await sweepStaleTempFiles(
          Directory('${root.path}${Platform.pathSeparator}nope'),
          recursive: true,
        ),
        0,
      );
    });
  });

  group('接线（光有判据没接上等于没修）', () {
    test('画布这条腿：第一次保存时从数据根递归清扫，三个目录两种前缀都覆盖', () async {
      final inDocuments = await put('documents/${orphan('old.json')}', age: stale);
      final inMedia = await put('notebooks/n1/media/${orphan('old.png', 'thumb')}', age: stale);
      final inThumbs = await put('thumbnails/${orphan('t.png', 'thumb')}', age: stale);
      final live = await put('documents/${orphan('inflight.json')}');

      final storage = StorageService(
        directoryProvider: () async => root,
        keyProvider: () async => null,
        // 未建库：走明文腿，才会真的进到 writeSealedBytes（否则先被锁异常掐掉）
        vaultConfigured: () async => false,
      );
      await storage.save(DrawingDocument(id: 'w1', title: '触发一次保存'));

      expect(inDocuments.existsSync(), isFalse, reason: 'M5：接线被拆掉这里就红');
      expect(inMedia.existsSync(), isFalse, reason: '只扫 documents/ 会漏掉嵌套子目录');
      expect(inThumbs.existsSync(), isFalse, reason: '只认 write_ 会漏掉 thumb_ 那一族（M4）');
      expect(live.existsSync(), isTrue, reason: '新鲜的不碰（②）');
    });

    test('块文档这条腿：第一次保存时本地清扫 blockdocs/', () async {
      final orphanFile = await put('blockdocs/${orphan('bd_old.json')}', age: stale);
      final fresh = await put('blockdocs/${orphan('bd_live.json')}');
      final header = await put('blockdocs/bd_real.json', age: const Duration(hours: 2));

      final store = NoteBlockDocStore(directoryProvider: () async => root);
      await store.saveDocument(
        NoteBlockDoc(
          id: 'bd_new',
          title: '接线验证',
          body: const [],
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        ),
      );

      expect(orphanFile.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(header.existsSync(), isTrue, reason: '正式块文档永不被清扫碰');
    });
  });
}
