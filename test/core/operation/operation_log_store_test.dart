// A2（协同方案 §9）：操作日志磁盘侧车的不变量与崩溃窗口。
//
// 三条不变量各自成组：②幂等（同 seq 重放不拉长日志）、①文档是权威
// （baseRev 超前于盘上 revision 的尾巴读回时丢弃）、③加密降级不留第二通道
// （锁定 ⇒ 什么都不写，已建库 ⇒ 不落明文）。另钉两个崩溃窗口——它们靠
// `writeBarrierForTest` 停在「tmp 已写、尚未改名」那一格，不靠调度碰运气
// （与 DN-207 的 `rewriteBarrierForTest` 同一纪律）。
//
// 本阶段侧车**尚未接进保存路径**（接线受 editor_page 行数棘轮约束，见提交
// 说明），所以这里验的是存储面自身的契约，不是「保存后日志一定在」。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/operation/document_operation.dart';
import 'package:drawing_notes_app/core/operation/operation_log_store.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oplog_store_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  String pathOf(String docId) =>
      '${tempDir.path}${Platform.pathSeparator}oplog'
      '${Platform.pathSeparator}$docId.jsonl';

  File sidecar(String docId) => File(pathOf(docId));

  OperationLogRecord rec(int seq, int baseRev) => OperationLogRecord(
    seq: seq,
    baseRev: baseRev,
    operation: OpLayerProp(
      layerId: 'l1',
      prop: OpLayerProp.propVisible,
      before: true,
      after: seq.isEven,
    ),
  );

  OperationLogStore storePlain({OperationLogLimits? limits}) =>
      OperationLogStore(
        directoryProvider: () async => tempDir,
        limits: limits ?? OperationLogLimits.standard,
      );

  OperationLogStore storeVaulted(Uint8List key) => OperationLogStore(
    directoryProvider: () async => tempDir,
    keyProvider: () async => key,
  );

  group('不变量②幂等', () {
    test('同一批记录投两次 ⇒ 第二次不新增，盘上仍只有那些行', () async {
      final store = storePlain();
      final batch = [rec(1, 10), rec(2, 20)];

      expect(await store.append('idem_a', batch), 2);
      expect(await store.append('idem_a', batch), 0);

      final loaded = await store.load('idem_a');
      expect(loaded.map((r) => r.seq), [1, 2]);
      expect(loaded.map((r) => r.baseRev), [10, 20]);
    });

    test('部分重叠的批次只补差集（按 seq 判等，不按 payload）', () async {
      final store = storePlain();
      expect(await store.append('idem_b', [rec(1, 10), rec(2, 20)]), 2);
      // seq 2 重放、seq 3 才是新的——两条同 seq 但内容不同的记录里，
      // 后者按定义是「同一序号的重复投递」，必须以已落盘的那条为准。
      expect(await store.append('idem_b', [rec(2, 999), rec(3, 30)]), 1);

      final loaded = await store.load('idem_b');
      expect(loaded.map((r) => r.seq), [1, 2, 3]);
      expect(loaded[1].baseRev, 20, reason: '重复的 seq 不得覆盖既有记录');
    });

    test('操作载荷跨读写逐字段保真（信封字段不落进工程文件）', () async {
      final store = storePlain();
      await store.append('roundtrip', [rec(4, 40)]);
      final loaded = await store.load('roundtrip');
      expect(loaded.single.operation.toJson(), {
        'type': 'layer.prop',
        'layerId': 'l1',
        'prop': 'visible',
        'before': true,
        'after': true, // rec(4, …) 的 after = seq.isEven
      });
      // 侧车里的 `seq`/`baseRev` 只活在日志行上。
      final line = const LineSplitter().convert(sidecar('roundtrip').readAsStringSync()).single;
      expect(line, contains('"seq":4'));
      expect(line, contains('"baseRev":40'));
      expect(line, contains('"op":{'));
    });
  });

  group('不变量①文档是权威', () {
    test('baseRev 超前于盘上 revision 的尾巴读回时丢弃', () async {
      final store = storePlain();
      await store.append('authoritative', [rec(1, 10), rec(2, 20), rec(3, 30)]);

      final truncated = await store.load('authoritative', docRevision: 20);
      expect(truncated.map((r) => r.seq), [1, 2]);
      expect(truncated.map((r) => r.baseRev), [10, 20]);

      // 截断只发生在读侧：盘上仍是全量，文档 revision 追上来后记录又可用。
      expect(sidecar('authoritative').readAsStringSync(), contains('"seq":3'));
      expect((await store.load('authoritative', docRevision: 30)).length, 3);
    });

    test('不传 docRevision ⇒ 全量读回（不替调用方裁决）', () async {
      final store = storePlain();
      await store.append('full_read', [rec(1, 10), rec(2, 20)]);
      expect((await store.load('full_read')).map((r) => r.seq), [1, 2]);
    });

    test('盘上无侧车 ⇒ 空列表（新文档未落过盘）', () async {
      expect(await storePlain().load('never_written'), isEmpty);
      expect(sidecar('never_written').existsSync(), isFalse);
    });
  });

  group('上限必须有', () {
    test('记录数超上限 ⇒ 只保最新 maxRecords 条', () async {
      final store = storePlain(
        limits: const OperationLogLimits(maxRecords: 3),
      );
      expect(await store.append('cap_n', [for (var i = 1; i <= 5; i++) rec(i, i * 10)]), 5);

      final loaded = await store.load('cap_n');
      expect(loaded.map((r) => r.seq), [3, 4, 5]);
      // 截断后仍能正确去重：lastSeq 取的是保留段的最大值。
      expect(await store.append('cap_n', [rec(4, 40)]), 0);
    });

    test('字节超上限 ⇒ 裁到装得下，并保住最新那条', () async {
      final store = storePlain(
        limits: const OperationLogLimits(maxRecords: 100, maxBytes: 220),
      );
      await store.append('cap_bytes', [for (var i = 1; i <= 8; i++) rec(i, i * 10)]);

      final raw = sidecar('cap_bytes').readAsStringSync();
      final lines = const LineSplitter().convert(raw);
      expect(raw.length, lessThanOrEqualTo(220));
      expect(lines, isNotEmpty);
      expect(int.parse(lines.last.split('"seq":').last.split(',').first), 8,
          reason: '裁剪必须从最旧一端下手，最新记录不能被丢掉');
    });
  });

  group('不变量③加密降级不留第二条通道', () {
    test('保险库锁定 ⇒ 什么都不写，append 如实返回 0', () async {
      final store = OperationLogStore(
        directoryProvider: () async => tempDir,
        keyProvider: () async => null, // 建过库但取不到密钥
      );

      expect(await store.append('locked', [rec(1, 10)]), 0);
      expect(sidecar('locked').existsSync(), isFalse);
      expect(Directory('${tempDir.path}${Platform.pathSeparator}oplog').listSync(), isEmpty);
    });

    test('有密钥 ⇒ 盘上是 DNV 信封，读回逐条一致且不见明文', () async {
      final key = VaultKeyService.randomBytes(32);
      final store = storeVaulted(key);
      expect(await store.append('sealed', [rec(1, 10), rec(2, 20)]), 2);

      final raw = await sidecar('sealed').readAsBytes();
      expect(VaultFileCodec.isEncrypted(raw), isTrue);
      expect(latin1.decode(raw), isNot(contains('"seq"')));
      expect((await store.load('sealed')).map((r) => r.seq), [1, 2]);
    });

    test('已建库却遇到明文侧车 ⇒ 拒绝回放，也拒绝覆盖', () async {
      final key = VaultKeyService.randomBytes(32);
      final store = storeVaulted(key);
      final file = sidecar('plain_invader');
      file.createSync(recursive: true);
      file.writeAsStringSync('${jsonEncode(rec(1, 10).toJson())}\n');

      await expectLater(
        store.load('plain_invader'),
        throwsA(isA<VaultFileLockException>()),
        reason: '来路不明的明文不能当成可信记录回放',
      );
      expect(await store.append('plain_invader', [rec(2, 20)]), 0);
      expect(
        file.readAsStringSync(),
        '${jsonEncode(rec(1, 10).toJson())}\n',
        reason: '读不懂现有侧车时不得用「我以为的开头」把它抹掉',
      );
    });

    test('侧车被改名挪到别的文档 ⇒ AAD 绑定让它不可读', () async {
      final key = VaultKeyService.randomBytes(32);
      final store = storeVaulted(key);
      await store.append('sidecar_a', [rec(1, 10)]);
      final bytes = await sidecar('sidecar_a').readAsBytes();
      sidecar('sidecar_b').createSync(recursive: true);
      await sidecar('sidecar_b').writeAsBytes(bytes);

      await expectLater(
        store.load('sidecar_b'),
        throwsA(isA<VaultFileException>()),
      );
      expect(await store.append('sidecar_b', [rec(2, 20)]), 0);
      expect(await sidecar('sidecar_b').readAsBytes(), equals(bytes));
    });
  });

  group('崩溃窗口（时序屏障钉死）', () {
    test('窗口 1：tmp 已写、尚未改名时崩溃 ⇒ 上一份逐字节不变，无 .tmp 残留', () async {
      final store = storePlain();
      await store.append('crash1', [rec(1, 10)]);
      final before = await sidecar('crash1').readAsBytes();

      store.writeBarrierForTest = (_) async {
        throw const FileSystemException('模拟改名前断电');
      };
      await expectLater(
        store.append('crash1', [rec(2, 20)]),
        throwsA(isA<FileSystemException>()),
      );
      store.writeBarrierForTest = null;

      expect(await sidecar('crash1').readAsBytes(), equals(before));
      expect((await store.load('crash1')).map((r) => r.seq), [1]);
      final residue = Directory('${tempDir.path}${Platform.pathSeparator}oplog')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'));
      expect(residue, isEmpty, reason: '失败路径必须回收临时文件，不留半份日志');
    });

    test('窗口 2：改名完成后崩溃 ⇒ 读回恰为新内容，没有半行', () async {
      final store = storePlain();
      await store.append('crash2', [rec(1, 10)]);
      store.writeBarrierForTest = (_) async {}; // 停在「tmp 已写」这一格并放行
      expect(await store.append('crash2', [rec(2, 20)]), 1);
      store.writeBarrierForTest = null;

      // 换一个实例读：断言的是盘上真相，不是同实例的缓存。
      final reloaded = await storePlain().load('crash2');
      expect(reloaded.map((r) => r.seq), [1, 2]);
      final raw = sidecar('crash2').readAsStringSync();
      expect(raw.endsWith('\n'), isTrue, reason: '整行落盘，末行不带半截');
      expect(const LineSplitter().convert(raw), hasLength(2));
    });
  });

  group('崩溃残留：上一轮留下的 .tmp', () {
    test('残留临时文件不算侧车，也不干扰后续读写', () async {
      await storePlain().append('residue', [rec(1, 10)]);
      // 改名之前断电留下的半份内容：文件名带随机 token，正式文件名不可能撞上。
      final stale = File(
        '${sidecar('residue').path}.oplog_crashresidue.tmp',
      );
      stale.writeAsStringSync('{"seq":99,"baseRev":99,"op":{"type":"no.such"}}');

      // 读侧只认 `<docId>.jsonl`：残留既不会被当成第二份日志，也不会让
      // 已有记录读不出来（append 的兜底会把「读不懂现有侧车」判成放弃写入，
      // 误把残留当侧车就会从此不再落盘）。
      expect((await storePlain().load('residue')).map((r) => r.seq), [1]);
      expect(await storePlain().append('residue', [rec(2, 20)]), 1);
      expect((await storePlain().load('residue')).map((r) => r.seq), [1, 2]);
      expect(
        stale.readAsStringSync(),
        contains('no.such'),
        reason: '本用例只主张「残留不碍事」，不主张它会被清扫',
      );
    });
  });

  group('畸形输入与非法 id（fail-closed）', () {
    test('未知操作类型 ⇒ load 抛 FormatException（回放不容静默丢弃）', () async {
      final file = sidecar('unknown_op');
      file.createSync(recursive: true);
      file.writeAsStringSync(
        '{"seq":1,"baseRev":10,"op":{"type":"no.such.op"}}\n',
      );
      await expectLater(
        storePlain().load('unknown_op'),
        throwsA(isA<FormatException>()),
      );
    });

    test('信封字段残缺 ⇒ 同样抛，不猜它大概是什么', () async {
      final file = sidecar('bad_envelope');
      file.createSync(recursive: true);
      file.writeAsStringSync('{"seq":1,"op":{"type":"layer.prop"}}\n');
      await expectLater(
        storePlain().load('bad_envelope'),
        throwsA(isA<FormatException>()),
      );
    });

    test('非法文档 id ⇒ ArgumentError，且不产生任何目录副作用', () async {
      final store = storePlain();
      await expectLater(
        store.append('../evil', [rec(1, 10)]),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        store.load('a/b'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        Directory('${tempDir.path}${Platform.pathSeparator}oplog').existsSync(),
        isFalse,
        reason: 'id 校验必须发生在创建目录之前',
      );
    });
  });
}
