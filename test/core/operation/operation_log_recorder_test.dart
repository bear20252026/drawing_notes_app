// A2 接线（协同方案 §10 的那半）：会话操作流 → 磁盘侧车的三条契约。
//
// 存储面自身的四条不变量在 `operation_log_store_test.dart`；本文件只管接线：
//  ①「没有新操作就一个字节都不写」（自动保存每 5 秒一次，而 append 是整份重写）
//  ②「水位线只在写成功时前进」（锁定 / 读不懂 / 写盘异常 ⇒ 下一轮重试同一批）
//  ③「侧车失败绝不挡住文档保存」（异常一律吞掉，只留审计）
// 另加两条只有接线面才有的坑：同一篇文档**关掉再打开**（内存日志换了实例，
// 序号从 1 重新开始）、以及 `await` 期间用户继续画（拿 `log.lastSerial` 收尾
// 会把那几笔当成已落盘而静默丢掉）。
//
// 突变自证（每行改完只让对应的用例变红，改完立刻还原；2026-10-15 实跑，
// 括号里是当轮真正变红的那条用例名）：
//  M1 去掉 `if (pending.isEmpty) return 0`        ⇒ （空日志 ⇒ 连 store 都不构造）
//  M2 收尾改用 `log.lastSerial`                    ⇒ （await 期间新记录的操作不算已落盘）
//  M3 `written == 0` 也照样推进水位                ⇒ （锁定 ⇒ 不推进、重试 seq 不重复；同一段停滞只报第一次）
//  M4 `_cursorFor` 里去掉「换实例 ⇒ 水位归零」      ⇒ （同一篇文档关掉再打开）
//  M5 `_seqBase` 失败时返回 0（凭空猜号段起点）      ⇒ （锁定那一轮问不出号段起点 ⇒ 不把猜来的 0 缓存下来）
//  M6 flush 里不再 try/catch                       ⇒ （写盘抛异常 ⇒ 吞掉、返回 0、水位不动，下一轮补齐）
//  M7 `_opLogStore` 恒传 keyProvider（丢掉建库判据） ⇒ （侧车加密判据与文档同一条：没建库⇒明文，建过库⇒DNV 信封）
//  M8 saveAndLog 里把 revision 挪到 save 之后       ⇒ （revision 必须取自 save 之前）
//  M9 把接线点换回裸 `storage.save(doc)`            ⇒ （editor_page 的自动保存真的走 saveAndLog）
//  M10 `_opLogStore` 的判据缺席默认改回 `?? false`   ⇒ （STO-012：判据缺席时侧车默认走加密腿，不抢跑一份明文）
//
// **M1/M5/M7 第一版是无效的**（改完仍全绿＝那条门禁根本没在守门），补法各不一样：
//  M1：`append` 对空列表本来就返回 0，「不建文件」看不出差别 ⇒ 改成注入**计数工厂**，
//      断言没有新操作时 store 一次都不被构造（连解析目录、读盘都不该发生）。
//  M5：store 自己的「读不懂就放弃写入」把猜来的 0 掩盖了 ⇒ 加一条**加密侧车**用例：
//      先落 2 条，再把密钥锁掉（load 抛）跑一轮，解锁后第 3 条必须接成 seq 3——
//      缓存了 0 的话它会被 seq 去重静默吞掉，正好是这条契约要防的形状。
//  M7：「没建库」那半边原来根本不传 keyProvider，判据那条 `configured ? … : null`
//      是死代码 ⇒ 改成按生产形状传一个「取不到密钥就返回 null」的 provider，
//      此时恒传 keyProvider 会让侧车被当成「建过库但锁定」，一份都不写。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/operation/document_operation.dart';
import 'package:drawing_notes_app/core/operation/operation_log.dart';
import 'package:drawing_notes_app/core/operation/operation_log_recorder.dart';
import 'package:drawing_notes_app/core/operation/operation_log_store.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oplog_wiring_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  File docFile(String docId) => File(
    '${tempDir.path}${Platform.pathSeparator}documents'
    '${Platform.pathSeparator}$docId.json',
  );

  File sidecar(String docId) => File(
    '${tempDir.path}${Platform.pathSeparator}oplog'
    '${Platform.pathSeparator}$docId.jsonl',
  );

  DrawingDocument doc({String id = 'doc_a', int rev = 1_700_000_000_000}) =>
      DrawingDocument(
        id: id,
        title: '接线',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(rev),
      );

  DocumentOperation op(int n) => OpLayerProp(
    layerId: 'l1',
    prop: OpLayerProp.propVisible,
    before: true,
    after: n.isEven,
  );

  OperationLogStore plainStore({
    Future<void> Function(String docId)? barrier,
  }) => OperationLogStore(
    directoryProvider: () async => tempDir,
  )..writeBarrierForTest = barrier;

  /// 锁定态：建过库但拿不到密钥（store 侧的 fail-closed 由存储面用例保证，
  /// 这里要的是「接线的水位线别跟着前进」）。
  OperationLogStore lockedStore() => OperationLogStore(
    directoryProvider: () async => tempDir,
    keyProvider: () async => null,
  );

  OperationLogRecorder recorderWith(
    Future<OperationLogStore> Function() factory,
  ) => OperationLogRecorder(factory);

  List<int> seqsOnDisk(String docId) {
    final text = sidecar(docId).readAsBytesSync();
    return [
      for (final line in const LineSplitter().convert(utf8.decode(text)))
        if (line.trim().isNotEmpty)
          (jsonDecode(line) as Map<String, dynamic>)['seq'] as int,
    ];
  }

  group('契约①：没有新操作就不碰盘', () {
    test('空日志 ⇒ 连 store 都不构造（不解析目录、不读盘、不写盘）', () async {
      var built = 0;
      final r = OperationLogRecorder(() async {
        built++;
        return plainStore();
      });
      expect(await r.flush(doc(), OperationLog(), 1_700_000_000_000), 0);
      expect(built, 0, reason: '没有新操作却去构造 store = 每 5 秒一次无谓的读盘');
      expect(sidecar('doc_a').existsSync(), isFalse);
    });

    test('落过一次之后同一批不再重放 ⇒ 盘上字节不变、返回 0', () async {
      final r = recorderWith(() async => plainStore());
      final log = OperationLog();
      log.record(op(1));
      expect(await r.flush(doc(), log, 100), 1);
      final bytes = sidecar('doc_a').readAsBytesSync();

      expect(await r.flush(doc(), log, 200), 0);
      expect(sidecar('doc_a').readAsBytesSync(), bytes);
    });

    test('只有新操作那一截会落，且 baseRev 用的是**正在落盘那一版**的 revision', () async {
      final r = recorderWith(() async => plainStore());
      final log = OperationLog();
      log.record(op(1));
      expect(await r.flush(doc(), log, 100), 1);
      log.record(op(2));
      expect(await r.flush(doc(rev: 250), log, 250), 1);

      final loaded = await plainStore().load('doc_a', docRevision: 250);
      expect(loaded.map((e) => e.seq), [1, 2]);
      expect(loaded.map((e) => e.baseRev), [100, 250]);
    });
  });

  group('契约②：水位线只在写成功时前进', () {
    test('锁定（append 返回 0）⇒ 不推进；解锁后重试同一批，seq 不重复', () async {
      var unlocked = false;
      final r = recorderWith(
        () async => unlocked ? plainStore() : lockedStore(),
      );
      final log = OperationLog();
      log.record(op(1));
      log.record(op(2));

      expect(await r.flush(doc(), log, 100), 0);
      expect(sidecar('doc_a').existsSync(), isFalse);

      unlocked = true;
      expect(await r.flush(doc(), log, 100), 2);
      expect(seqsOnDisk('doc_a'), [1, 2]);
      // 再冲一次必须是 0：说明重试没有被当成「已经落过两批」。
      expect(await r.flush(doc(), log, 100), 0);
    });

    test('写盘抛异常 ⇒ 吞掉、返回 0、水位不动，下一轮补齐', () async {
      var failNext = true;
      final r = recorderWith(
        () async => plainStore(
          barrier: (docId) async {
            if (!failNext) return;
            // 突变点：把 tmp 删掉 ⇒ 命中「回读校验失败」那一格（存储面 §3-C）。
            final dir = Directory('${tempDir.path}${Platform.pathSeparator}oplog');
            for (final e in dir.listSync()) {
              if (e is File && e.path.endsWith('.tmp')) await e.delete();
            }
          },
        ),
      );
      final log = OperationLog();
      log.record(op(1));

      expect(await r.flush(doc(), log, 100), 0); // 不抛出来 = 契约③
      failNext = false;
      expect(await r.flush(doc(), log, 100), 1);
      expect(seqsOnDisk('doc_a'), [1]);
    });

    test('现有侧车读不懂 ⇒ 不猜号段起点，什么都不写', () async {
      sidecar('doc_a').createSync(recursive: true);
      sidecar('doc_a').writeAsStringSync('这不是操作日志\n');
      final r = recorderWith(() async => plainStore());
      final log = OperationLog();
      log.record(op(1));

      expect(await r.flush(doc(), log, 100), 0);
      // 原样留着：没有用「我以为的开头」覆盖一份看不懂的日志。
      expect(sidecar('doc_a').readAsStringSync(), '这不是操作日志\n');
    });

    test('锁定那一轮问不出号段起点 ⇒ 不把猜来的 0 缓存下来', () async {
      // 盘上先有一份**加密**侧车（seq 1..2）。第一轮 recorder 拿不到密钥 ⇒ load 抛，
      // 号段起点问不出来；如果这里偷懒缓存 0，解锁后重发的那条会被 seq 去重**静默吞掉**。
      final key = Uint8List(32)..[0] = 7;
      final seeded = OperationLogStore(
        directoryProvider: () async => tempDir,
        keyProvider: () async => key,
      );
      await seeded.append('doc_seq', [
        OperationLogRecord(seq: 1, baseRev: 10, operation: op(1)),
        OperationLogRecord(seq: 2, baseRev: 20, operation: op(2)),
      ]);

      var locked = true;
      final r = OperationLogRecorder(
        () async => OperationLogStore(
          directoryProvider: () async => tempDir,
          keyProvider: () async => locked ? null : key,
        ),
      );
      final log = OperationLog()..record(op(3));

      locked = true;
      expect(await r.flush(doc(id: 'doc_seq'), log, 30), 0);
      locked = false;
      expect(await r.flush(doc(id: 'doc_seq'), log, 30), 1);

      final loaded = await seeded.load('doc_seq');
      expect(loaded.map((e) => e.seq), [1, 2, 3]);
    });

    test('同一篇文档关掉再打开（日志换实例）⇒ 新会话的操作继续接在盘上号之后', () async {
      final r = recorderWith(() async => plainStore());
      final first = OperationLog();
      first.record(op(1));
      first.record(op(2));
      expect(await r.flush(doc(), first, 100), 2);

      // 重开：控制器重建 ⇒ OperationLog 是新实例，序号从 1 重新开始。
      final second = OperationLog();
      second.record(op(3));
      expect(await r.flush(doc(), second, 200), 1);
      expect(seqsOnDisk('doc_a'), [1, 2, 3]);
    });

    test('await 期间新记录的操作不算已落盘（下一轮必须补上）', () async {
      final log = OperationLog();
      log.record(op(1));
      // 突变点落在这里：flush 里 append 飞行中又画了一笔。
      final r = recorderWith(() async => plainStore(
        barrier: (docId) async {
          log.record(op(2));
        },
      ));
      expect(await r.flush(doc(), log, 100), 1);
      expect(await r.flush(doc(), log, 100), 1);
      expect(seqsOnDisk('doc_a'), [1, 2]);
    });

    test('容量截断丢掉的旧操作不会把水位线错位（落的是窗口里剩下的那段）', () async {
      final r = recorderWith(() async => plainStore());
      final log = OperationLog(capacity: 2);
      log.record(op(1));
      log.record(op(2));
      log.record(op(3)); // 把 op1 挤出窗口
      expect(await r.flush(doc(), log, 100), 2);
      expect(seqsOnDisk('doc_a'), [1, 2]);
      expect(await r.flush(doc(), log, 100), 0);
    });
  });

  group('审计：失败要可见，但不许每 5 秒刷一条', () {
    test('同一段停滞只报第一次，成功之后允许报下一段', () async {
      int count() => AuditLogger.snapshot()
          .where((line) => line.contains('oplog.'))
          .length;
      final before = count();
      final r = recorderWith(() async => lockedStore());
      final log = OperationLog();
      log.record(op(1));
      await r.flush(doc(), log, 100);
      await r.flush(doc(), log, 100);
      expect(count() - before, 1);
    });
  });

  group('保存路径接线（§10 那一半）', () {
    test('真 StorageService.saveAndLog：正文落盘之后侧车才有那批操作', () async {
      final storage = StorageService(directoryProvider: () async => tempDir);
      final d = doc();
      final log = OperationLog();
      log.record(op(1));

      expect(sidecar('doc_a').existsSync(), isFalse);
      await storage.saveAndLog(d, log);
      expect(docFile('doc_a').existsSync(), isTrue);
      expect(sidecar('doc_a').existsSync(), isTrue);
      expect(seqsOnDisk('doc_a'), [1]);
      expect(
        await plainStore().load('doc_a', docRevision: d.updatedAt.millisecondsSinceEpoch),
        hasLength(1),
      );
    });

    test('saveAndLog 之后继续画 ⇒ 只有新增那一截进侧车', () async {
      final storage = StorageService(directoryProvider: () async => tempDir);
      final d = doc();
      final log = OperationLog();
      log.record(op(1));
      await storage.saveAndLog(d, log);
      log.record(op(2));
      d.touch();
      await storage.saveAndLog(d, log);
      expect(seqsOnDisk('doc_a'), [1, 2]);
    });

    test('editor_page 的自动保存真的走 saveAndLog，不是又退回裸 save', () {
      final src = File(
        'lib/features/drawing/presentation/editor_page_persistence.dart',
      ).readAsStringSync();
      expect(
        src,
        contains('await storage.saveAndLog(doc, _controller.operationLog);'),
        reason: 'A2 接线落点丢失：自动保存又变成不落操作日志了',
      );
      expect(
        RegExp(r'await\s+storage\.save\(').hasMatch(src),
        isFalse,
        reason: '保存链里不该再有裸 storage.save(doc)——那一条不会落侧车',
      );
    });

    test('侧车加密判据与文档同一条：没建库⇒明文，建过库⇒DNV 信封', () async {
      // 「没建库」这一半必须带着 keyProvider 来：生产注入的就是一个「取不到密钥就
      // 返回 null」的 provider，判据靠的是 `vaultConfigured` 而不是 provider 缺失。
      // 侧车那头顶着这条判据分流：未建库 ⇒ 明文；一旦把 keyProvider 原样传下去，
      // store 会把它当成「建过库但锁定」，一份都不写——画完就没了。
      final plain = StorageService(
        directoryProvider: () async => tempDir,
        vaultConfigured: () async => false,
        keyProvider: () async => null,
      );
      final log1 = OperationLog()..record(op(1));
      await plain.saveAndLog(doc(id: 'doc_plain'), log1);
      expect(sidecar('doc_plain').existsSync(), isTrue);
      expect(
        String.fromCharCodes(sidecar('doc_plain').readAsBytesSync().take(3)),
        isNot('DNV'),
      );

      final key = Uint8List(32);
      final vaulted = StorageService(
        directoryProvider: () async => tempDir,
        vaultConfigured: () async => true,
        keyProvider: () async => key,
      );
      final log2 = OperationLog()..record(op(1));
      await vaulted.saveAndLog(doc(id: 'doc_vault'), log2);
      expect(
        String.fromCharCodes(sidecar('doc_vault').readAsBytesSync().take(3)),
        'DNV',
      );
    });

    test('STO-012：判据缺席时侧车默认走加密腿，不抢跑一份明文', () async {
      // 组合根恒注入 `vaultConfigured`，所以「缺席」代表的是一种**装配失误**的形状：
      // 给了 keyProvider、忘了判据。这一格原本按「没建库」处理 ⇒ 明文侧车与加密正文
      // 同盘共存（等于给加密边界开了第二条通道）；现在必须与正文同向、走 fail-closed。
      // 反向对照用上面那条显式 `vaultConfigured: false` 的用例——那才是产品设计里的明文。
      final key = Uint8List(32);
      final storage = StorageService(
        directoryProvider: () async => tempDir,
        keyProvider: () async => key,
      );
      final log = OperationLog()..record(op(1));
      await storage.saveAndLog(doc(id: 'doc_no_detector'), log);

      final bytes = sidecar('doc_no_detector').readAsBytesSync();
      expect(
        String.fromCharCodes(bytes.take(3)),
        'DNV',
        reason: '判据缺席 ⇒ 侧车不许落明文（与本仓其余三条腿的默认同向）',
      );
    });

    test('保险库锁定 ⇒ 正文写路径本来就 fail-closed，侧车更不落明文', () async {
      // 注意抛点：是 `save` 自己拒绝（`_sealDocBytes`），不是侧车。
      // 锁定态下正文都写不下去，日志当然也不会先落一份明文出去。
      final storage = StorageService(
        directoryProvider: () async => tempDir,
        vaultConfigured: () async => true,
        keyProvider: () async => null,
      );
      final log = OperationLog()..record(op(1));
      await expectLater(
        storage.saveAndLog(doc(id: 'doc_locked'), log),
        throwsA(isA<VaultFileLockException>()),
      );
      expect(docFile('doc_locked').existsSync(), isFalse);
      expect(sidecar('doc_locked').existsSync(), isFalse);
    });

    test('侧车这一头出事 ⇒ 正文保存照样成功（契约③在接线点上的证明）', () async {
      final storage = StorageService(directoryProvider: () async => tempDir);
      // 先埋一份读不懂的侧车：`_seqBase` 问不出号段起点 ⇒ 放弃落盘，但不许抛。
      sidecar('doc_side').createSync(recursive: true);
      sidecar('doc_side').writeAsStringSync('不是操作日志\n');
      final log = OperationLog()..record(op(1));
      await storage.saveAndLog(doc(id: 'doc_side'), log);
      expect(docFile('doc_side').existsSync(), isTrue);
      expect(sidecar('doc_side').readAsStringSync(), '不是操作日志\n');
    });

    test('revision 必须取自 save 之前（语句顺序是这条接线的成立条件）', () {
      // 为什么要钉顺序而不是钉行为：要让它自然露馅，得给**正文**写路径开一个
      // 测试屏障（await 期间把 updatedAt 推后），那是 StorageService 的口子，
      // 不该为几 KB 的侧车开。顺序本身就是判据，直接钉住它。
      final src = File('lib/core/storage/storage_service.dart').readAsStringSync();
      final rev = src.indexOf('final revision = doc.updatedAt.millisecondsSinceEpoch;');
      final save = src.indexOf('final path = await save(doc);');
      expect(rev, greaterThan(-1), reason: 'saveAndLog 里取 revision 的那行被挪走了');
      expect(save, greaterThan(-1), reason: 'saveAndLog 不再走 save(doc)');
      expect(
        rev < save,
        isTrue,
        reason: 'revision 在 save 之后才取 ⇒ baseRev 会超前于盘上那一版，'
            '读侧不变量①会把这批记录当幻影整段丢掉',
      );
    });
  });
}
