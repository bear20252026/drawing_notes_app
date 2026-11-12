// SYNC-003 冲突台账：值模型 + 内存实现的契约锁。
//
// 这一层要钉死的形状只有四条，每条都对应一个「做错了不会报错、只会悄悄
// 丢用户决定」的后果：
//  ① 同一篇反复冲突是**合并**而不是覆盖（firstDetectedAtMs 是历史，
//     count 是「这篇在反复分叉」这个信号——抹掉它，用户就不知道该设改判了）；
//  ② record **绝不触碰**改判（改判是长期决定，被一次新冲突顺手清掉等于
//     每次都要重选，而用户以为自己设过了）；
//  ③ setOverride 对**没发生过冲突**的 docId 不凭空造条目（台账里出现只有
//     改判、没有事实的空壳行，就无法回答「上次按什么处理的」）；
//  ④ load 按最近冲突时刻倒序（UI 的第一屏必须是最新的那条）。

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict_ledger.dart';

const _t0 = 1700000000000; // 固定钟点：台账的时间戳是数据，不是「现在」

SyncConflict _conflict(
  String docId, {
  int local = 20,
  int remote = 30,
  ConflictResolution? resolved,
}) => SyncConflict(
  docId: docId,
  localUpdatedAt: local,
  localSize: 7,
  remoteUpdatedAt: remote,
  remoteSize: 9,
  resolvedResolution: resolved,
);

ConflictLedgerEntry _entry(
  String docId, {
  int first = _t0,
  int last = _t0,
  int count = 1,
  SyncConflict? conflict,
  ConflictResolution? override,
  int? overriddenAt,
}) => ConflictLedgerEntry(
  docId: docId,
  firstDetectedAtMs: first,
  lastDetectedAtMs: last,
  count: count,
  lastConflict: conflict ?? _conflict(docId),
  resolutionOverride: override,
  overriddenAtMs: overriddenAt,
);

void main() {
  group('ConflictLedgerEntry.copyWith', () {
    test('省略参数 = 全部保留（null 不是「清空」）', () {
      final src = _entry(
        'a',
        override: ConflictResolution.keepLocal,
        overriddenAt: 123,
      );
      final out = src.copyWith();
      expect(identical(out, src), isFalse, reason: '不可变值模型：必须是新对象');
      expect(out.docId, src.docId);
      expect(out.firstDetectedAtMs, src.firstDetectedAtMs);
      expect(out.lastDetectedAtMs, src.lastDetectedAtMs);
      expect(out.count, src.count);
      expect(out.lastConflict, src.lastConflict);
      expect(out.resolutionOverride, src.resolutionOverride);
      expect(out.overriddenAtMs, src.overriddenAtMs);
    });

    test('clearOverride 同时清掉 overriddenAtMs（不留无主人的时间戳）', () {
      final out = _entry(
        'a',
        override: ConflictResolution.keepLocal,
        overriddenAt: 123,
      ).copyWith(clearOverride: true);
      expect(out.resolutionOverride, isNull);
      expect(out.overriddenAtMs, isNull);
      expect(out.hasOverride, isFalse);
      // 其余字段不动。
      expect(out.count, 1);
      expect(out.lastConflict.docId, 'a');
    });

    test('改判换值时 overriddenAtMs 可被显式改写', () {
      final out = _entry('a', override: ConflictResolution.keepLocal).copyWith(
        resolutionOverride: ConflictResolution.keepBoth,
        overriddenAtMs: 456,
      );
      expect(out.resolutionOverride, ConflictResolution.keepBoth);
      expect(out.overriddenAtMs, 456);
    });

    test('相等性与 hashCode 覆盖全部字段', () {
      final a = _entry('a', count: 3, override: ConflictResolution.keepRemote);
      final b = _entry('a', count: 3, override: ConflictResolution.keepRemote);
      final c = _entry('a', count: 4, override: ConflictResolution.keepRemote);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('MemorySyncConflictLedgerStore.record', () {
    test('首次记录：first == last == now，count 1，无改判', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('a')], nowMs: _t0);

      final loaded = await store.load();
      expect(loaded, hasLength(1));
      final e = loaded.single;
      expect(e.docId, 'a');
      expect(e.firstDetectedAtMs, _t0);
      expect(e.lastDetectedAtMs, _t0);
      expect(e.count, 1);
      expect(e.hasOverride, isFalse);
      expect(e.overriddenAtMs, isNull);
      expect(e.lastConflict.docId, 'a');
    });

    test('同一 docId 再冲突 → 合并：count 累加、保留 first、刷新 last 与事实',
        () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('a', resolved: ConflictResolution.keepRemote)],
          nowMs: _t0);
      final second = _conflict(
        'a',
        local: 25,
        resolved: ConflictResolution.keepLocal,
      );
      await store.record([second], nowMs: _t0 + 5000);

      final e = (await store.load()).single;
      expect(e.count, 2, reason: '同一篇反复分叉是这个字段存在的唯一理由');
      expect(e.firstDetectedAtMs, _t0, reason: '历史起点不能被最近一次顶掉');
      expect(e.lastDetectedAtMs, _t0 + 5000);
      expect(e.lastConflict, second, reason: '最近一次的事实才是「当时按什么处理的」');
    });

    test('同一批里同 docId 出现两次 → 也算两次（不丢计数）', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([
        _conflict('a'),
        _conflict('a', local: 21),
      ], nowMs: _t0);

      expect((await store.load()).single.count, 2);
    });

    test('不同 docId 各一条，互不干扰', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('a'), _conflict('b')], nowMs: _t0);
      expect((await store.load()).map((e) => e.docId).toSet(), {'a', 'b'});
    });

    test('空列表是 no-op（不写盘、不报错）', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record(const []);
      expect(await store.load(), isEmpty);
    });

    test('record 保留已有改判（长期决定不被一次新冲突清掉）', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('a')], nowMs: _t0);
      await store.setOverride('a', ConflictResolution.keepBoth, nowMs: _t0 + 1);

      await store.record([
        _conflict('a', resolved: ConflictResolution.keepBoth),
      ], nowMs: _t0 + 9000);

      final e = (await store.load()).single;
      expect(
        e.resolutionOverride,
        ConflictResolution.keepBoth,
        reason: '用户设过的方向必须跨轮存活，否则等于每次都要重选',
      );
      expect(e.overriddenAtMs, _t0 + 1, reason: '改判时刻也不该被 record 顶掉');
      expect(e.count, 2);
    });

    test('无改判时 record 也不会凭空造出改判', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('a')], nowMs: _t0);
      await store.record([_conflict('a')], nowMs: _t0 + 1);
      expect((await store.load()).single.hasOverride, isFalse);
    });
  });

  group('MemorySyncConflictLedgerStore.setOverride', () {
    test('设定改判：写入方向与时刻', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('a')], nowMs: _t0);
      await store.setOverride('a', ConflictResolution.keepRemote, nowMs: _t0 + 7);

      final e = (await store.load()).single;
      expect(e.hasOverride, isTrue);
      expect(e.resolutionOverride, ConflictResolution.keepRemote);
      expect(e.overriddenAtMs, _t0 + 7);
    });

    test('改判可以被改（后一次覆盖前一次）', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('a')], nowMs: _t0);
      await store.setOverride('a', ConflictResolution.keepLocal, nowMs: _t0 + 1);
      await store.setOverride('a', ConflictResolution.keepBoth, nowMs: _t0 + 2);

      final e = (await store.load()).single;
      expect(e.resolutionOverride, ConflictResolution.keepBoth);
      expect(e.overriddenAtMs, _t0 + 2);
    });

    test('传 null = 清除改判（回到「下次重新问」）', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('a')], nowMs: _t0);
      await store.setOverride('a', ConflictResolution.keepLocal, nowMs: _t0 + 1);
      await store.setOverride('a', null);

      final e = (await store.load()).single;
      expect(e.hasOverride, isFalse);
      expect(e.overriddenAtMs, isNull);
      expect(e.count, 1, reason: '清除改判不该顺手改事实');
    });

    test('对没发生过冲突的 docId 不设改判、也不造条目', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('a')], nowMs: _t0);

      await store.setOverride('never-conflicted', ConflictResolution.keepLocal);

      expect(
        (await store.load()).map((e) => e.docId).toList(),
        ['a'],
        reason: '台账里不允许出现「只有改判、没有事实」的空壳行',
      );
    });

    test('空台账上设改判 → 仍然什么都不做', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.setOverride('ghost', ConflictResolution.keepBoth);
      expect(await store.load(), isEmpty);
    });
  });

  group('MemorySyncConflictLedgerStore.load', () {
    test('按 lastDetectedAtMs 倒序（最近冲突的在最前）', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('old')], nowMs: _t0);
      await store.record([_conflict('new')], nowMs: _t0 + 60000);
      await store.record([_conflict('mid')], nowMs: _t0 + 30000);

      expect((await store.load()).map((e) => e.docId).toList(), [
        'new',
        'mid',
        'old',
      ]);
    });

    test('同一篇被再次记录后，排到它最近冲突的位置', () async {
      final store = MemorySyncConflictLedgerStore();
      await store.record([_conflict('a')], nowMs: _t0);
      await store.record([_conflict('b')], nowMs: _t0 + 1000);
      await store.record([_conflict('a', local: 21)], nowMs: _t0 + 2000);

      expect((await store.load()).map((e) => e.docId).toList(), ['a', 'b']);
    });

    test('空台账返回空列表（不是 null）', () async {
      expect(await MemorySyncConflictLedgerStore().load(), isEmpty);
    });

    test('构造时可预置条目（供 UI 测试与诊断用）', () async {
      final store = MemorySyncConflictLedgerStore(
        initial: [_entry('seed', last: _t0 + 5)],
      );
      expect((await store.load()).single.docId, 'seed');
    });
  });
}
