// M11 契约测试：ScheduleEvent 领域模型 + ScheduleEventStore 持久化。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/schedule/domain/schedule_event.dart';
import 'package:drawing_notes_app/features/schedule/infrastructure/schedule_event_store.dart';

void main() {
  group('ScheduleEvent 模型', () {
    test('dayKey 生成补零对齐', () {
      expect(scheduleDayKey(DateTime(2026, 8, 5)), '2026-08-05');
      expect(scheduleDayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('minuteOfDay 时刻字段：序列化往返 + 越界拒绝', () {
      final e = ScheduleEvent(
        id: 'e9',
        title: '下午 2 点半开会',
        dayKey: '2026-08-30',
        minuteOfDay: 14 * 60 + 30,
        createdAt: DateTime(2026, 8, 30, 9),
      );
      final back = ScheduleEvent.fromJson(e.toJson());
      expect(back, e);
      expect(back!.minuteOfDay, 870);
      // 越界 fail-open → null
      final bad = ScheduleEvent.fromJson({
        'id': 'x',
        'title': 't',
        'dayKey': '2026-08-30',
        'minuteOfDay': 1440,
        'createdAt': '2026-08-30T09:00:00.000',
      });
      expect(bad, isNull);
      // 全天待办（无时刻字段）→ null
      final allday = ScheduleEvent.fromJson({
        'id': 'y',
        'title': 't',
        'dayKey': '2026-08-30',
        'createdAt': '2026-08-30T09:00:00.000',
      });
      expect(allday!.minuteOfDay, isNull);
    });

    test('JSON 往返一致', () {
      final e = ScheduleEvent(
        id: 'event_1',
        title: '画完草图',
        dayKey: '2026-08-30',
        isDone: true,
        createdAt: DateTime(2026, 8, 30, 10),
      );
      final back = ScheduleEvent.fromJson(e.toJson());
      expect(back, e);
    });

    test('损坏 JSON 返回 null', () {
      expect(ScheduleEvent.fromJson({}), isNull);
      expect(
        ScheduleEvent.fromJson({
          'id': 1,
          'title': 'x',
          'dayKey': 'y',
          'createdAt': 'z',
        }),
        isNull,
      );
    });

    test('P1：毒 dayKey 隔离（永不抛异常，坏行丢弃）', () {
      Map<String, Object?> base(String dayKey) => {
        'id': 'e1',
        'title': 't',
        'dayKey': dayKey,
        'createdAt': '2026-08-30T09:00:00.000',
      };
      // 格式非法 / 不存在日期 / 超长标题 / 空 id → 全部 null。
      expect(ScheduleEvent.fromJson(base('--')), isNull);
      expect(ScheduleEvent.fromJson(base('9999-99-99')), isNull);
      expect(ScheduleEvent.fromJson(base('2026-02-30')), isNull);
      expect(ScheduleEvent.fromJson(base('1-2')), isNull);
      expect(
        ScheduleEvent.fromJson(base('2026-08-30')..['title'] = 'x' * 501),
        isNull,
      );
      expect(ScheduleEvent.fromJson(base('2026-08-30')..['id'] = ''), isNull);
      // 合法通过。
      expect(ScheduleEvent.fromJson(base('2026-08-30'))!.dayKey, '2026-08-30');
      // tryParseDayKey 永不抛异常。
      expect(tryParseDayKey('--'), isNull);
      expect(tryParseDayKey('9999-99-99'), isNull);
      expect(tryParseDayKey('2026-02-30'), isNull);
      expect(tryParseDayKey('2026-08-30')?.day, 30);
    });
  });

  group('ScheduleEventStore（临时目录注入）', () {
    late Directory tempDir;
    late ScheduleEventStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sched_store_test');
      store = ScheduleEventStore(directoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('初始为空表', () async {
      expect(await store.loadAll(), isEmpty);
    });

    test('add 持久化，空白标题被忽略', () async {
      final added = await store.add(title: '写周报', dayKey: '2026-08-30');
      expect(added, isNotNull);
      expect(added!.title, '写周报');
      expect((await store.loadAll()).single.id, added.id);

      expect(await store.add(title: '   ', dayKey: '2026-08-30'), isNull);
      expect((await store.loadAll()).length, 1);
    });

    test('toggleDone 切换完成态', () async {
      final added = await store.add(title: 'A', dayKey: '2026-08-30');
      final toggled = await store.toggleDone(added!.id);
      expect(toggled!.isDone, isTrue);
      expect((await store.loadAll()).single.isDone, isTrue);
      expect((await store.toggleDone(added.id))!.isDone, isFalse);
    });

    test('add 带时刻（minuteOfDay）', () async {
      final added = await store.add(
        title: '14:30 站会',
        dayKey: '2026-08-30',
        minuteOfDay: 870,
      );
      expect(added!.minuteOfDay, 870);
      expect((await store.loadAll()).single.minuteOfDay, 870);
      // 越界忽略
      expect(
        await store.add(title: 'x', dayKey: '2026-08-30', minuteOfDay: 2000),
        isNull,
      );
    });

    test('remove 删除', () async {
      final a = await store.add(title: 'A', dayKey: '2026-08-30');
      await store.add(title: 'B', dayKey: '2026-08-31');
      await store.remove(a!.id);
      final rest = await store.loadAll();
      expect(rest.length, 1);
      expect(rest.single.title, 'B');
    });

    test('损坏文件 fail-open 返回空表', () async {
      await store.add(title: 'A', dayKey: '2026-08-30');
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}schedule_events.json',
      );
      await file.writeAsString('broken{{');
      final reopened = ScheduleEventStore(
        directoryProvider: () async => tempDir,
      );
      expect(await reopened.loadAll(), isEmpty);
    });

    test('跨实例持久化可读', () async {
      await store.add(title: 'A', dayKey: '2026-08-30');
      final reopened = ScheduleEventStore(
        directoryProvider: () async => tempDir,
      );
      expect((await reopened.loadAll()).single.title, 'A');
    });
  });
}
