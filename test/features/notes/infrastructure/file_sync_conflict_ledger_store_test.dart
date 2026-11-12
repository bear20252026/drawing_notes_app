// 文件版冲突台账（file_sync_conflict_ledger_store.dart）单测。
//
// 与基线存储那条测试相比，这里多两条**只有读-改-写 store 才会有**的判据，
// 也是审计 2026-10-16 点名的本仓头号复发形态：
//  ① 「文件在但读不出来」≠「文件不存在」——前者必须落审计、且**覆盖之前**
//     把原件复制成 `.corrupt-*`；后者是正常的空台账。两者答成同一个答案，
//     一次半写之后下一次 record 就会把用户的全部冲突历史整体抹掉。
//  ② 条目级 fail-closed：一条坏条目只丢它自己，其余照常读出（把整份台账
//     当成空的，就是把「一条读不懂」放大成「全部不存在」）。
//
// 另外锁两条写侧纪律：随机 tmp + flush + rename（无 `.tmp` 残留）、
// record/setOverride 的读-改-写在队列里串行（快速连点不丢更新）。

import 'dart:convert';
import 'dart:io';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/file_sync_conflict_ledger_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/temp_dir_cleanup.dart';

const _t0 = 1700000000000;

SyncConflict _conflict(
  String docId, {
  int local = 20,
  int remote = 30,
  ConflictResolution? resolved,
  String? localDigest,
  String? remoteDigest,
}) => SyncConflict(
  docId: docId,
  localUpdatedAt: local,
  localSize: 7,
  remoteUpdatedAt: remote,
  remoteSize: 9,
  resolvedResolution: resolved,
  localDigest: localDigest,
  remoteDigest: remoteDigest,
);

void main() {
  late Directory tempDir;
  late File ledgerFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('conflict_ledger_test_');
    ledgerFile = File(
      '${tempDir.path}${Platform.pathSeparator}'
      '${FileSyncConflictLedgerStore.fileName}',
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await deleteTempDirWithRetry(tempDir);
    }
  });

  FileSyncConflictLedgerStore makeStore() =>
      FileSyncConflictLedgerStore(directoryProvider: () async => tempDir);

  /// 读回盘上原始 JSON（断言编码形状用，不是再走一遍 load）。
  Map<String, dynamic> readRaw() =>
      jsonDecode(ledgerFile.readAsStringSync()) as Map<String, dynamic>;

  test('文件不存在时 load 返回空列表（不是 null、不抛）', () async {
    expect(await makeStore().load(), isEmpty);
  });

  test('record→load 往返：条目字段与改判完整恢复', () async {
    final store = makeStore();
    await store.record([
      _conflict(
        'doc-a',
        resolved: ConflictResolution.keepBoth,
        localDigest: 'aaa',
        remoteDigest: 'bbb',
      ),
    ], nowMs: _t0);
    await store.setOverride('doc-a', ConflictResolution.keepRemote, nowMs: _t0 + 5);

    final loaded = await makeStore().load();
    expect(loaded, hasLength(1));
    final e = loaded.single;
    expect(e.docId, 'doc-a');
    expect(e.firstDetectedAtMs, _t0);
    expect(e.lastDetectedAtMs, _t0);
    expect(e.count, 1);
    expect(e.resolutionOverride, ConflictResolution.keepRemote);
    expect(e.overriddenAtMs, _t0 + 5);
    expect(e.lastConflict.resolvedResolution, ConflictResolution.keepBoth);
    expect(e.lastConflict.localDigest, 'aaa');
    expect(e.lastConflict.remoteDigest, 'bbb');
    expect(e.lastConflict.localSize, 7);
    expect(e.lastConflict.remoteSize, 9);
  });

  test('同一 docId 再冲突 → 合并，first 保留、改判保留', () async {
    final store = makeStore();
    await store.record([_conflict('a')], nowMs: _t0);
    await store.setOverride('a', ConflictResolution.keepLocal, nowMs: _t0 + 1);
    await store.record([
      _conflict('a', local: 25, resolved: ConflictResolution.keepLocal),
    ], nowMs: _t0 + 5000);

    final e = (await makeStore().load()).single;
    expect(e.count, 2);
    expect(e.firstDetectedAtMs, _t0);
    expect(e.lastDetectedAtMs, _t0 + 5000);
    expect(e.resolutionOverride, ConflictResolution.keepLocal);
    expect(e.lastConflict.localUpdatedAt, 25);
  });

  test('编码形状：字段平铺在同一层、按 docId 排序、两次写逐字节一致', () async {
    final store = makeStore();
    await store.record([
      _conflict('b'),
      _conflict('a', resolved: ConflictResolution.keepLocal),
    ], nowMs: _t0);

    final first = ledgerFile.readAsStringSync();
    final decoded = jsonDecode(first) as Map<String, dynamic>;
    expect(decoded.keys, ['entries'], reason: '顶层只有清单键');
    final list = decoded['entries'] as List;
    expect(
      list.map((e) => (e as Map)['docId']).toList(),
      ['a', 'b'],
      reason: '稳定序是可比对、可测试的前提',
    );
    // SyncConflict 的字段与台账字段**平铺在同一层**（台账是人也要能读的文件）。
    final a = list.first as Map<String, dynamic>;
    expect(a['docId'], 'a');
    expect(a['localUpdatedAt'], 20);
    expect(a['remoteSize'], 9);
    expect(a['resolvedResolution'], 'keepLocal');
    expect(a.containsKey('lastConflict'), isFalse, reason: '不该有嵌套对象');
    expect(a.containsKey('localDigest'), isFalse, reason: 'null 字段不写出');

    // 换一个目录、**相反的录入顺序**再写一遍：逐字节相同才说明输出只取决于
    // 内容，不取决于「谁先录进来」——这是比对与诊断能成立的前提。
    final otherDir = await Directory.systemTemp.createTemp(
      'conflict_ledger_test_mirror_',
    );
    addTearDown(() async {
      if (otherDir.existsSync()) await deleteTempDirWithRetry(otherDir);
    });
    await FileSyncConflictLedgerStore(
      directoryProvider: () async => otherDir,
    ).record([
      _conflict('a', resolved: ConflictResolution.keepLocal),
      _conflict('b'),
    ], nowMs: _t0);
    final mirror = File(
      '${otherDir.path}${Platform.pathSeparator}'
      '${FileSyncConflictLedgerStore.fileName}',
    );
    expect(mirror.readAsStringSync(), first);
  });

  test('原子写：目录内无 .tmp 残留，只有一份正式文件', () async {
    final store = makeStore();
    await store.record([_conflict('a')], nowMs: _t0);
    await store.setOverride('a', ConflictResolution.keepBoth, nowMs: _t0 + 1);

    final names = tempDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(names, [FileSyncConflictLedgerStore.fileName]);
  });

  test('并发 record 两条 → 两条都在（读-改-写串行，不丢更新）', () async {
    final store = makeStore();
    await Future.wait([
      store.record([_conflict('a')], nowMs: _t0),
      store.record([_conflict('b')], nowMs: _t0 + 1),
    ]);

    expect((await makeStore().load()).map((e) => e.docId).toSet(), {'a', 'b'});
  });

  test('并发 record + setOverride → 改判不丢', () async {
    final store = makeStore();
    await store.record([_conflict('a')], nowMs: _t0);
    await Future.wait([
      store.record([_conflict('a', local: 21)], nowMs: _t0 + 1),
      store.setOverride('a', ConflictResolution.keepBoth, nowMs: _t0 + 2),
    ]);

    final e = (await makeStore().load()).single;
    expect(e.count, 2);
    expect(e.resolutionOverride, ConflictResolution.keepBoth);
  });

  test('损坏 JSON：load 返回空列表，不抛', () async {
    await ledgerFile.writeAsString('{这不是合法 JSON');
    expect(await makeStore().load(), isEmpty);
  });

  test('顶层形状不对（缺 entries / entries 不是数组）：同样按读不出来处理', () async {
    await ledgerFile.writeAsString('{"somethingElse": []}');
    expect(await makeStore().load(), isEmpty);

    await ledgerFile.writeAsString('{"entries": {"a": {}}}');
    expect(await makeStore().load(), isEmpty);
  });

  test('读不出来之后 record：原件被抢救成 .corrupt-*，新台账落盘', () async {
    await ledgerFile.writeAsString('{"entries": [半写');
    final store = makeStore();

    // 先读一次：确认三态里的「读不出来」被识别（不抛、不落 audit 断言）。
    expect(await store.load(), isEmpty);
    expect(store.salvagedOriginalName, isNull, reason: '只读不该复制原件');

    await store.record([_conflict('a')], nowMs: _t0);

    // 覆盖之前必须留下原件，否则用户会以为历史是「从来没有过」。
    expect(store.salvagedOriginalName, isNotNull);
    // 保留件的名字自带正式文件名前缀（`<正式名>.corrupt-...`），拼回目录即可。
    final preserved = File(
      '${tempDir.path}${Platform.pathSeparator}${store.salvagedOriginalName}',
    );
    expect(preserved.existsSync(), isTrue);
    expect(preserved.readAsStringSync(), '{"entries": [半写');

    // 新台账本身完好。
    expect((await makeStore().load()).single.docId, 'a');
  });

  test('一条坏条目只丢它自己，其余照常读出（条目级 fail-closed）', () async {
    final store = makeStore();
    await store.record([_conflict('good-1'), _conflict('good-2')], nowMs: _t0);

    final list = (readRaw()['entries'] as List).toList();
    list.add({'docId': 'broken', 'count': 'not-a-number'}); // 数字写成 String
    await ledgerFile.writeAsString(jsonEncode({'entries': list}));

    final loaded = await makeStore().load();
    expect(loaded.map((e) => e.docId).toSet(), {'good-1', 'good-2'});
  });

  test('count < 1 的条目被丢弃（计数不可能为 0）', () async {
    await ledgerFile.writeAsString(jsonEncode({
      'entries': [
        {
          'docId': 'zero',
          'firstDetectedAtMs': _t0,
          'lastDetectedAtMs': _t0,
          'count': 0,
          'localUpdatedAt': 20,
          'localSize': 7,
          'remoteUpdatedAt': 30,
          'remoteSize': 9,
        }
      ]
    }));
    expect(await makeStore().load(), isEmpty);
  });

  test('缺必填数字字段 → 丢该条（不猜默认值）', () async {
    await ledgerFile.writeAsString(jsonEncode({
      'entries': [
        {
          'docId': 'missing-size',
          'firstDetectedAtMs': _t0,
          'lastDetectedAtMs': _t0,
          'count': 1,
          'localUpdatedAt': 20,
          // localSize 缺失：尺寸是判据之一，缺了就无法复述「当时的事实」。
          'remoteUpdatedAt': 30,
          'remoteSize': 9,
        }
      ]
    }));
    expect(await makeStore().load(), isEmpty);
  });

  test('docId 为空串 → 丢该条', () async {
    await ledgerFile.writeAsString(jsonEncode({
      'entries': [
        {
          'docId': '',
          'firstDetectedAtMs': _t0,
          'lastDetectedAtMs': _t0,
          'count': 1,
          'localUpdatedAt': 20,
          'localSize': 7,
          'remoteUpdatedAt': 30,
          'remoteSize': 9,
        }
      ]
    }));
    expect(await makeStore().load(), isEmpty);
  });

  test('未知枚举名：resolvedResolution 当没写（条目保住），resolutionOverride 丢条目',
      () async {
    await ledgerFile.writeAsString(jsonEncode({
      'entries': [
        {
          'docId': 'unknown-resolved',
          'firstDetectedAtMs': _t0,
          'lastDetectedAtMs': _t0,
          'count': 1,
          'localUpdatedAt': 20,
          'localSize': 7,
          'remoteUpdatedAt': 30,
          'remoteSize': 9,
          'resolvedResolution': 'keepSometimes',
        },
        {
          'docId': 'unknown-override',
          'firstDetectedAtMs': _t0,
          'lastDetectedAtMs': _t0,
          'count': 1,
          'localUpdatedAt': 20,
          'localSize': 7,
          'remoteUpdatedAt': 30,
          'remoteSize': 9,
          'resolutionOverride': 'keepSometimes',
          'overriddenAtMs': _t0,
        },
      ]
    }));

    final loaded = await makeStore().load();
    expect(loaded.map((e) => e.docId).toList(), ['unknown-resolved']);
    expect(loaded.single.lastConflict.resolvedResolution, isNull);
    expect(loaded.single.hasOverride, isFalse);
  });

  test('数字写成 double（JSON 无 int/double 之分）→ 仍能读出', () async {
    await ledgerFile.writeAsString(jsonEncode({
      'entries': [
        {
          'docId': 'd',
          'firstDetectedAtMs': _t0.toDouble(),
          'lastDetectedAtMs': _t0.toDouble(),
          'count': 1.0,
          'localUpdatedAt': 20.0,
          'localSize': 7.0,
          'remoteUpdatedAt': 30.0,
          'remoteSize': 9.0,
        }
      ]
    }));

    final e = (await makeStore().load()).single;
    expect(e.docId, 'd');
    expect(e.count, 1);
    expect(e.lastDetectedAtMs, _t0);
  });

  test('setOverride 对没发生过冲突的 docId：不新增条目、不改台账内容', () async {
    final store = makeStore();
    await store.record([_conflict('a')], nowMs: _t0);
    final before = ledgerFile.readAsStringSync();

    await store.setOverride('ghost', ConflictResolution.keepBoth, nowMs: _t0 + 1);

    expect(ledgerFile.readAsStringSync(), before, reason: '没有事实就不该有写盘动作');
    expect((await makeStore().load()).map((e) => e.docId).toList(), ['a']);
  });

  test('load 按 lastDetectedAtMs 倒序', () async {
    final store = makeStore();
    await store.record([_conflict('old')], nowMs: _t0);
    await store.record([_conflict('new')], nowMs: _t0 + 60000);

    expect((await makeStore().load()).map((e) => e.docId).toList(), [
      'new',
      'old',
    ]);
  });
}
