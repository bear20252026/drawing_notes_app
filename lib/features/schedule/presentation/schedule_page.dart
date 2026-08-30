import 'package:flutter/material.dart'
    as fm
    show Checkbox, Material, MaterialType, TimeOfDay, showTimePicker;
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/features/schedule/domain/schedule_event.dart';
import 'package:drawing_notes_app/features/schedule/infrastructure/schedule_event_store.dart';
import 'package:drawing_notes_app/features/schedule/presentation/schedule_calendar.dart';
import 'package:drawing_notes_app/shared/widgets/ambient_background.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

/// 日历 —— 月历 + 待办/日程（24 小时时间轴）。
///
/// M11.2（去重）：文档活动时间线移除（并入主页 All Docs 的日期展示），
/// 本页只负责「日程」一件事：
/// - 月历选日（活动点 = 有待办的日期）；
/// - 选中某天 → **24 小时时间轴**：可把待办定位到几点几分；
///   未选中 → 全部日程按日期升序分组展示。
/// 新增时可设置时刻（几点几分），不设置则为全天待办。
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, this.eventStore});

  /// 待办/日程事件存储（测试可注入内存实现）。
  final ScheduleEventStore? eventStore;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  List<ScheduleEvent> _events = [];
  bool _loading = true;
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDate;

  late final ScheduleEventStore _eventStore =
      widget.eventStore ?? ScheduleEventStore();

  @override
  void initState() {
    super.initState();
    _focusedMonth = _startOfMonth(_focusedMonth);
    _load();
  }

  Future<void> _load() async {
    final events = await _eventStore.loadAll();
    if (!mounted) return;
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  bool _hasActivity(DateTime day) {
    final key = _dayKey(day);
    return _events.any((e) => e.dayKey == key);
  }

  void _onDateTap(DateTime day) {
    setState(() {
      if (_selectedDate != null && _sameDay(_selectedDate!, day)) {
        _selectedDate = null; // 再点一次取消单日筛选
      } else {
        _selectedDate = day;
      }
    });
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _focusedMonth = DateTime(now.year, now.month);
      _selectedDate = now;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AmbientBackground(
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppDesign.pagePadding,
              16,
              AppDesign.pagePadding,
              AppDesign.pagePadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(scheme),
                const SizedBox(height: 16),
                GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppDesign.cardRadius),
                  ),
                  child: ScheduleCalendar(
                    focusedMonth: _focusedMonth,
                    selectedDate: _selectedDate,
                    hasActivity: _hasActivity,
                    onMonthChanged: (m) => setState(
                      () => _focusedMonth = DateTime(m.year, m.month),
                    ),
                    onDateTap: _onDateTap,
                  ),
                ),
                const SizedBox(height: 20),
                _buildAgendaHeader(scheme),
                const SizedBox(height: 8),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ..._buildAgenda(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '日历 · 待办',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '选中日期，把事情安排到几点几分',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: _goToday,
          icon: const Icon(Icons.today, size: 18),
          label: const Text('今天'),
        ),
      ],
    );
  }

  Widget _buildAgendaHeader(ColorScheme scheme) {
    return Row(
      children: [
        Icon(Icons.checklist_rounded, size: 18, color: scheme.primary),
        const SizedBox(width: 6),
        Text(
          _selectedDate == null ? '全部日程' : '当日安排 · 24 小时',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const Spacer(),
        if (_selectedDate != null)
          TextButton(
            onPressed: () => setState(() => _selectedDate = null),
            child: const Text('显示全部日期'),
          ),
        IconButton(
          tooltip: '添加待办（日期为选中日，未选中则为今天）',
          icon: const Icon(Icons.add_task_rounded),
          color: scheme.primary,
          onPressed: _showAddEventDialog,
        ),
      ],
    );
  }

  // ---------------- 当日 24 小时时间轴 ----------------

  /// 当天（或全部日期）的日程区。
  List<Widget> _buildAgenda() {
    if (_selectedDate != null) {
      return _buildDayTimeline(_selectedDate!);
    }
    return _buildAllDaysAgenda();
  }

  /// 选中日：全天 + 0..23 小时行。
  List<Widget> _buildDayTimeline(DateTime day) {
    final key = _dayKey(day);
    final dayEvents = _events.where((e) => e.dayKey == key).toList()
      ..sort((a, b) {
        final am = a.minuteOfDay ?? -1;
        final bm = b.minuteOfDay ?? -1;
        return am.compareTo(bm);
      });
    final allDay = dayEvents.where((e) => e.minuteOfDay == null).toList();

    return [
      _dayHeader(day),
      const SizedBox(height: 8),
      // 全天待办区
      if (allDay.isNotEmpty) ...[
        for (final e in allDay) ...[
          _EventCard(
            event: e,
            onToggle: () => _toggleEvent(e),
            onDelete: () => _removeEvent(e),
          ),
          const SizedBox(height: 8),
        ],
      ],
      // 0..23 小时行
      for (var hour = 0; hour < 24; hour++)
        _HourRow(
          hour: hour,
          events: dayEvents
              .where(
                (e) => e.minuteOfDay != null && e.minuteOfDay! ~/ 60 == hour,
              )
              .toList(),
          onAddAt: () => _showAddEventDialog(preHour: hour),
          onToggle: _toggleEvent,
          onDelete: _removeEvent,
        ),
      if (dayEvents.isEmpty) ...[
        const SizedBox(height: 4),
        Text(
          '这一天还没有安排。点某个小时行右侧 ＋，把事情安排到具体时刻。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }

  /// 未选中日：全部日程按日期升序分组。
  List<Widget> _buildAllDaysAgenda() {
    if (_events.isEmpty) {
      return [_emptyState('还没有待办', '先在月历上选个日子，再点右上角 ＋ 添加。\n可以设置几点几分，也可以全天。')];
    }
    final byDay = <String, List<ScheduleEvent>>{};
    for (final e in _events) {
      byDay.putIfAbsent(e.dayKey, () => []).add(e);
    }
    final keys = byDay.keys.toList()..sort();
    return [
      for (final key in keys) ...[
        _dayHeader(_parseDayKey(key)),
        const SizedBox(height: 8),
        ...((byDay[key]!..sort(
              (a, b) => (a.minuteOfDay ?? -1).compareTo(b.minuteOfDay ?? -1),
            ))
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EventCard(
                  event: e,
                  onToggle: () => _toggleEvent(e),
                  onDelete: () => _removeEvent(e),
                ),
              ),
            )),
        const SizedBox(height: 8),
      ],
    ];
  }

  // ---------------- 增删改 ----------------

  Future<void> _showAddEventDialog({int? preHour}) async {
    var minuteOfDay = preHour == null ? null : preHour * 60;
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(
              _selectedDate == null
                  ? '添加待办（今天）'
                  : '添加待办（${_dayLabel(_selectedDate!)}）',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '要做点什么？'),
                  onSubmitted: (v) => Navigator.of(ctx).pop(v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(
                        minuteOfDay == null
                            ? '全天（不设时间）'
                            : _fmtMinute(minuteOfDay),
                      ),
                      onPressed: () async {
                        final cur = minuteOfDay;
                        final picked = await fm.showTimePicker(
                          context: ctx,
                          initialTime: cur == null
                              ? const fm.TimeOfDay(hour: 9, minute: 0)
                              : fm.TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
                        );
                        if (picked != null) {
                          final newMinute = picked.hour * 60 + picked.minute;
                          setDialogState(() => minuteOfDay = newMinute);
                        }
                      },
                    ),
                    if (minuteOfDay != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () =>
                            setDialogState(() => minuteOfDay = null),
                        child: const Text('改为全天'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                child: const Text('添加'),
              ),
            ],
          ),
        );
      },
    );
    if (title == null) return;
    final day = _selectedDate ?? DateTime.now();
    final added = await _eventStore.add(
      title: title,
      dayKey: _dayKey(day),
      minuteOfDay: minuteOfDay,
    );
    if (added == null) return;
    setState(() {
      _events = [..._events, added];
      // 新增后自动聚焦到该日，方便看到它出现在时间轴上。
      _selectedDate ??= day;
    });
  }

  Future<void> _toggleEvent(ScheduleEvent event) async {
    final updated = await _eventStore.toggleDone(event.id);
    if (updated == null) return;
    setState(() {
      _events = [
        for (final e in _events)
          if (e.id == updated.id) updated else e,
      ];
    });
  }

  Future<void> _removeEvent(ScheduleEvent event) async {
    await _eventStore.remove(event.id);
    setState(() {
      _events = _events.where((e) => e.id != event.id).toList();
    });
  }

  DateTime _parseDayKey(String key) {
    final parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  // ---------------- 通用小组件 ----------------

  Widget _dayHeader(DateTime at) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _dayLabel(at),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String title, String detail) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      borderRadius: const BorderRadius.all(
        Radius.circular(AppDesign.cardRadius),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 待办/日程卡片：勾选完成 + 时刻标签 + 删除。
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.onToggle,
    required this.onDelete,
  });

  final ScheduleEvent event;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GlassSurface(
      borderRadius: const BorderRadius.all(
        Radius.circular(AppDesign.controlRadius),
      ),
      // Checkbox（flutter/material 方言）要求（flutter 方言的）Material 祖先。
      child: fm.Material(
        type: fm.MaterialType.transparency,
        child: InkWell(
          onTap: onToggle,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppDesign.controlRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                fm.Checkbox(value: event.isDone, onChanged: (_) => onToggle()),
                const SizedBox(width: 4),
                if (event.minuteOfDay != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _fmtMinute(event.minuteOfDay),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: event.isDone
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                      decoration: event.isDone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: scheme.onSurfaceVariant,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个小时行：左侧时刻标签，右侧该小时的事件（空则画一条淡分隔线）。
class _HourRow extends StatelessWidget {
  const _HourRow({
    required this.hour,
    required this.events,
    required this.onAddAt,
    required this.onToggle,
    required this.onDelete,
  });

  final int hour;
  final List<ScheduleEvent> events;
  final VoidCallback onAddAt;
  final void Function(ScheduleEvent event) onToggle;
  final void Function(ScheduleEvent event) onDelete;

  String get _label => '${hour.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: events.isEmpty ? muted : scheme.onSurfaceVariant,
                  fontWeight: events.isEmpty
                      ? FontWeight.w400
                      : FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: events.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Container(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final e in events) ...[
                        _EventCard(
                          event: e,
                          onToggle: () => onToggle(e),
                          onDelete: () => onDelete(e),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
          ),
          SizedBox(
            width: 32,
            height: 30,
            child: IconButton(
              tooltip: '在 $hour 点添加',
              icon: const Icon(Icons.add, size: 16),
              color: scheme.onSurfaceVariant,
              padding: EdgeInsets.zero,
              onPressed: onAddAt,
            ),
          ),
        ],
      ),
    );
  }
}

DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _dayLabel(DateTime d) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${d.month} 月 ${d.day} 日 · ${weekdays[d.weekday - 1]}';
}

String _fmtMinute(int? minuteOfDay) {
  if (minuteOfDay == null) return '全天';
  final h = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
  final m = (minuteOfDay % 60).toString().padLeft(2, '0');
  return '$h:$m';
}
