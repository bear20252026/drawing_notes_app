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
      final reopened = ScheduleEventStore(directoryProvider: () async => tempDir);
      expect(await reopened.loadAll(), isEmpty);
    });

    test('跨实例持久化可读', () async {
      await store.add(title: 'A', dayKey: '2026-08-30');
      final reopened = ScheduleEventStore(directoryProvider: () async => tempDir);
      expect((await reopened.loadAll()).single.title, 'A');
    });
  });
}
