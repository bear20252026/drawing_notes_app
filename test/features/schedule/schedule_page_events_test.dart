// M11 契约测试：SchedulePage 待办/日程区（内存 Fake Store，规避 FakeAsync×IO）。
//
// 注意：testWidgets 主体运行在 FakeAsync 区，不驱动真实文件 IO。
// 因此这里注入内存版 [ScheduleEventStore] 子类（方法在 Dart 中均为虚方法），
// 持久化语义本身由 schedule_event_store_test.dart（真实 IO，普通 test()）锁定。
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' as m show Checkbox;
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/schedule/domain/schedule_event.dart';
import 'package:drawing_notes_app/features/schedule/infrastructure/schedule_event_store.dart';
import 'package:drawing_notes_app/features/schedule/presentation/schedule_page.dart';

/// 内存版事件存储（FakeAsync 安全）。
class _InMemoryEventStore extends ScheduleEventStore {
  final List<ScheduleEvent> _events = [];

  @override
  Future<List<ScheduleEvent>> loadAll() async => List.unmodifiable(_events);

  @override
  Future<ScheduleEvent?> add({
    required String title,
    required String dayKey,
    int? minuteOfDay,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;
    final event = ScheduleEvent(
      id: 'event_${_events.length + 1}',
      title: trimmed,
      dayKey: dayKey,
      minuteOfDay: minuteOfDay,
      createdAt: DateTime(2026, 8, 30, 9),
    );
    _events.add(event);
    return event;
  }

  @override
  Future<ScheduleEvent?> toggleDone(String id) async {
    final index = _events.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    final updated = _events[index].copyWith(isDone: !_events[index].isDone);
    _events[index] = updated;
    return updated;
  }

  @override
  Future<void> remove(String id) async {
    _events.removeWhere((e) => e.id == id);
  }
}

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required _InMemoryEventStore store,
    List<({String title, String dayKey})> seed = const [],
  }) async {
    for (final s in seed) {
      await store.add(title: s.title, dayKey: s.dayKey);
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        // 与 app_shell 一致：SchedulePage 实际在 Scaffold 内渲染
        //（Scaffold 为 mui 方言组件提供 Material 祖先）。
        home: Scaffold(body: SchedulePage(eventStore: store)),
      ),
    );
    // AmbientBackground 常驻动画，不能 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('种子事件在待办区可见且带勾选框', (tester) async {
    final store = _InMemoryEventStore();
    await pumpPage(
      tester,
      store: store,
      seed: [(title: '写周报', dayKey: '2026-08-30')],
    );
    expect(find.text('写周报'), findsOneWidget);
    expect(find.byType(m.Checkbox), findsOneWidget);
  });

  testWidgets('勾选切换完成态', (tester) async {
    final store = _InMemoryEventStore();
    await pumpPage(
      tester,
      store: store,
      seed: [(title: '写周报', dayKey: '2026-08-30')],
    );
    await tester.ensureVisible(find.byType(m.Checkbox));
    await tester.pump();
    await tester.tap(find.byType(m.Checkbox));
    await tester.pump();
    expect(store._events.single.isDone, isTrue);
  });

  testWidgets('删除按钮移除事件并刷新 UI', (tester) async {
    final store = _InMemoryEventStore();
    await pumpPage(
      tester,
      store: store,
      seed: [(title: '写周报', dayKey: '2026-08-30')],
    );
    await tester.ensureVisible(find.byTooltip('删除'));
    await tester.pump();
    await tester.tap(find.byTooltip('删除'));
    await tester.pump();
    expect(find.text('写周报'), findsNothing);
    expect(store._events, isEmpty);
  });

  testWidgets('选中某天仅看当天待办', (tester) async {
    final store = _InMemoryEventStore();
    await pumpPage(
      tester,
      store: store,
      seed: [
        (title: '周一的事', dayKey: '2026-08-24'),
        (title: '周日的事', dayKey: '2026-08-30'),
      ],
    );
    // 全部可见（按日期分组）。
    expect(find.text('周一的事'), findsOneWidget);
    expect(find.text('周日的事'), findsOneWidget);
  });
}
