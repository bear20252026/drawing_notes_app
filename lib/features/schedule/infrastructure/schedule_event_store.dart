/// 日程/待办事件本地存储门面。
///
/// 存储文件（应用文档目录下）：
///   `appDir/schedule_events.json`
///     `{"events": [ {id,title,dayKey,isDone,createdAt}, ... ]}`
///
/// 仅依赖 [ScheduleEvent]（domain）+ dart:io + directoryProvider；
/// 不 import presentation，层方向严格 domain ← infrastructure
/// （与 NoteBlockDocStore / FavoriteStore 同模式）。
library;

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/features/schedule/domain/schedule_event.dart';

/// 日程/待办事件存储门面。
class ScheduleEventStore {
  /// 创建事件存储门面。
  ///
  /// [directoryProvider] 为可选的目录提供者回调。测试时可注入临时目录，
  /// 生产环境默认使用系统文档目录。
  ScheduleEventStore({this.directoryProvider});

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  File? _file;

  /// 写链（P2 修复：`loadAll+_writeAll` 非原子——快速连点 add/toggle/
  /// remove 交错即丢事件；同一 store 内写操作串行化，不同 store 互不干扰）。
  Future<void> _tail = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() fn) {
    final task = _tail.then((_) => fn());
    _tail = task.then((_) {}, onError: (_) {});
    return task;
  }

  Future<File> _fileRef() async {
    if (_file != null) return _file!;
    final provider = directoryProvider;
    final base = provider != null
        ? await provider()
        : await AppDataRoot.defaultRootDir();
    _file = File('${base.path}${Platform.pathSeparator}schedule_events.json');
    return _file!;
  }

  /// 读取全部事件。文件不存在或损坏时返回空表（fail-open）。
  Future<List<ScheduleEvent>> loadAll() async {
    try {
      final file = await _fileRef();
      if (!await file.exists()) return const [];
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final list = decoded['events'];
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(ScheduleEvent.fromJson)
          .whereType<ScheduleEvent>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeAll(List<ScheduleEvent> events) async {
    final file = await _fileRef();
    // P2 修复：随机 tmp（固定名 symlink 劫持）+ flush + 失败清理。
    final r = Random.secure();
    final suffix = List<int>.generate(
      8,
      (_) => r.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final tmp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    try {
      await tmp.writeAsString(
        jsonEncode({
          'events': [for (final e in events) e.toJson()],
        }),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// 新增一条事件（标题去空白后为空则忽略）。
  /// [minuteOfDay] 可选：当天内的时刻（0..1439），null = 全天待办。
  /// P2 修复：标题 500 字上限 + dayKey 合法性（与 fromJson 同口径）。
  Future<ScheduleEvent?> add({
    required String title,
    required String dayKey,
    int? minuteOfDay,
  }) => _enqueue(() async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed.length > 500) return null;
    if (minuteOfDay != null && (minuteOfDay < 0 || minuteOfDay > 1439)) {
      return null;
    }
    if (tryParseDayKey(dayKey) == null) return null;
    final event = ScheduleEvent(
      id: LocalIdGenerator.next('event'),
      title: trimmed,
      dayKey: dayKey,
      minuteOfDay: minuteOfDay,
      createdAt: DateTime.now(),
    );
    final events = [...await loadAll(), event];
    await _writeAll(events);
    return event;
  });

  /// 切换完成状态，返回更新后的事件；不存在时返回 null。
  Future<ScheduleEvent?> toggleDone(String id) => _enqueue(() async {
    final events = await loadAll();
    final index = events.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    final updated = events[index].copyWith(isDone: !events[index].isDone);
    final next = [...events]..[index] = updated;
    await _writeAll(next);
    return updated;
  });

  /// 删除一条事件。
  Future<void> remove(String id) => _enqueue(() async {
    final events = await loadAll();
    await _writeAll(events.where((e) => e.id != id).toList());
  });
}
