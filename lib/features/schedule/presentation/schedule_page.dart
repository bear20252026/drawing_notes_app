import 'package:flutter/material.dart' as fm show Material, MaterialType;
import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/schedule/domain/schedule_entry.dart';
import 'package:drawing_notes_app/features/schedule/domain/schedule_event.dart';
import 'package:drawing_notes_app/features/schedule/infrastructure/schedule_event_store.dart';
import 'package:drawing_notes_app/features/schedule/presentation/schedule_calendar.dart';
import 'package:drawing_notes_app/shared/widgets/ambient_background.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

/// 日历 —— 月历 + 待办/日程 + 文档动态看板。
///
/// 上半月历：带活动点的日期会高亮（文档动态或待办事件），点击某天
/// 可只看那一天的记录。
/// 下方看板分两段：
/// - 「待办 · 日程」：用户亲手创建的真实事件（可新增/勾选完成/删除），
///   持久化于本地；
/// - 「文档动态」：按日期分组排列「那天动过的文档」，点击直接跳转。
///
/// M11：原 HomePage「时间线」并入此处（日历选日、看板看事）。
///
/// 为了不触碰架构边界（schedule 不能 import 其它 feature 的
/// application/infrastructure/presentation），文档数据由 app 组合层通过
/// [loadNotebooks] / [onOpen] 注入，页面只依赖 notes / drawing 的
/// domain 实体与 core 存储。
class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    this.storage,
    this.loadNotebooks,
    this.onOpen,
    this.eventStore,
  });

  /// 文档存储（core）—— 用于列出画板。
  final StorageService? storage;

  /// 笔记本加载回调（由 app 层注入，避免 schedule 依赖 notes 基础设施）。
  final Future<List<Notebook>> Function()? loadNotebooks;

  /// 点击某条记录，由 app 层负责跳转。
  final void Function(ScheduleEntry entry)? onOpen;

  /// 待办/日程事件存储（测试可注入临时目录实现）。
  final ScheduleEventStore? eventStore;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  List<ScheduleEntry> _entries = [];
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
    final docsFuture = widget.storage?.listDocuments();
    final nbsFuture = widget.loadNotebooks?.call();
    final docs = await (docsFuture ?? Future.value(const <DocumentMeta>[]));
    final nbs = await (nbsFuture ?? Future.value(const <Notebook>[]));
    final events = await _eventStore.loadAll();

    final entries = <ScheduleEntry>[
      for (final d in docs)
        ScheduleEntry(
          id: d.id,
          title: d.title,
          kind: ScheduleEntryKind.drawing,
          at: d.updatedAt,
        ),
      for (final nb in nbs)
        for (final p in nb.pages)
          ScheduleEntry(
            id: p.id,
            title: p.title,
            kind: ScheduleEntryKind.note,
            at: p.updatedAt,
            notebookId: nb.id,
            pageId: p.id,
          ),
    ];
    entries.sort((a, b) => b.at.compareTo(a.at));

    if (!mounted) return;
    setState(() {
      _entries = entries;
      _events = events;
      _loading = false;
    });
  }

  bool _hasActivity(DateTime day) {
    final key = _dayKey(day);
    if (_entries.any((e) => _dayKey(e.at) == key)) return true;
    return _events.any((e) => e.dayKey == key);
  }

  List<ScheduleEntry> _boardEntries() {
    if (_selectedDate == null) return _entries;
    final key = _dayKey(_selectedDate!);
    return _entries.where((e) => _dayKey(e.at) == key).toList();
  }

  /// 按日期分组的看板（日期倒序）。
  List<MapEntry<String, List<ScheduleEntry>>> _groups() {
    final map = <String, List<ScheduleEntry>>{};
    for (final e in _boardEntries()) {
      map.putIfAbsent(_dayKey(e.at), () => []).add(e);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.first.at.compareTo(a.value.first.at));
    return entries;
  }

  void _onDateTap(DateTime day) {
    setState(() {
      if (_selectedDate != null && _sameDay(_selectedDate!, day)) {
        _selectedDate = null; // 再点一次取消单日筛选，回到全部
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
                _buildEventHeader(scheme),
                const SizedBox(height: 8),
                ..._buildEventSection(),
                const SizedBox(height: 20),
                _buildBoardHeader(scheme),
                const SizedBox(height: 8),
                ..._buildBoard(),
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
                '日程',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '哪一天做了什么事，一眼看清',
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

  Widget _buildBoardHeader(ColorScheme scheme) {
    return Row(
      children: [
        Icon(Icons.view_timeline_outlined, size: 18, color: scheme.tertiary),
        const SizedBox(width: 6),
        Text(
          '文档动态',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const Spacer(),
        if (_selectedDate != null)
          TextButton(
            onPressed: () => setState(() => _selectedDate = null),
            child: Text('显示全部日期'),
          ),
      ],
    );
  }

  // ---------------- 待办 · 日程（M11 新增：真实事件） ----------------

  Widget _buildEventHeader(ColorScheme scheme) {
    return Row(
      children: [
        Icon(Icons.checklist_rounded, size: 18, color: scheme.primary),
        const SizedBox(width: 6),
        Text(
          '待办 · 日程',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: '添加待办（日期为选中日，未选中则为今天）',
          icon: const Icon(Icons.add_task_rounded),
          color: scheme.primary,
          onPressed: _showAddEventDialog,
        ),
      ],
    );
  }

  /// 待办展示列表：选中日 → 只看当天；否则全部按日期升序分组。
  Map<String, List<ScheduleEvent>> _eventGroups() {
    final filtered = _selectedDate == null
        ? _events
        : _events.where((e) => e.dayKey == _dayKey(_selectedDate!));
    final map = <String, List<ScheduleEvent>>{};
    for (final e in filtered) {
      map.putIfAbsent(e.dayKey, () => []).add(e);
    }
    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
  }

  List<Widget> _buildEventSection() {
    if (_loading) return const [];

    final groups = _eventGroups();
    if (groups.isEmpty) {
      return [
        _emptyState(
          '还没有待办',
          _selectedDate == null
              ? '点右上角 ＋ 写下第一条待办或日程。'
              : '这一天没有待办。点右上角 ＋ 给这天安排一件事。',
        ),
      ];
    }

    return [
      for (final entry in groups.entries) ...[
        _dayHeader(_parseDayKey(entry.key)),
        const SizedBox(height: 8),
        for (final e in entry.value) ...[
          _EventCard(
            event: e,
            onToggle: () => _toggleEvent(e),
            onDelete: () => _removeEvent(e),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
      ],
    ];
  }

  Future<void> _showAddEventDialog() async {
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(
            _selectedDate == null
                ? '添加待办（今天）'
                : '添加待办（${_dayLabel(_selectedDate!)}）',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '要做点什么？'),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
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
        );
      },
    );
    if (title == null) return;
    final day = _selectedDate == null ? DateTime.now() : _selectedDate!;
    final added = await _eventStore.add(title: title, dayKey: _dayKey(day));
    if (added == null) return;
    setState(() => _events = [..._events, added]);
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

  List<Widget> _buildBoard() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final groups = _groups();
    if (_entries.isEmpty) {
      return [_emptyState('还没有记录', '画点东西，或写几页笔记，就会出现在这里。')];
    }
    if (groups.isEmpty) {
      return [_emptyState('这一天没有记录', '选中别的日期，或切回「全部日期」看看。')];
    }

    return [
      for (final g in groups) ...[
        _dayHeader(g.value.first.at),
        const SizedBox(height: 8),
        for (final e in g.value) ...[
          _BoardCard(entry: e, onTap: () => widget.onOpen?.call(e)),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
      ],
    ];
  }

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

/// 待办/日程卡片：勾选完成 + 删除。
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
      // 双方言并存：mui 的 InkWell 要求（mui 的）Material 祖先，
      // flutter 的 Checkbox 要求（flutter 的）Material 祖先——各包一层。
      child: Material(
        type: MaterialType.transparency,
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
                  Checkbox(value: event.isDone, onChanged: (_) => onToggle()),
                  const SizedBox(width: 4),
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
      ),
    );
  }
}

/// 看板中的一条记录卡片。
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.entry, required this.onTap});

  final ScheduleEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDrawing = entry.kind == ScheduleEntryKind.drawing;

    return GlassSurface(
      borderRadius: const BorderRadius.all(
        Radius.circular(AppDesign.controlRadius),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppDesign.controlRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color:
                      (isDrawing
                              ? scheme.primaryContainer
                              : scheme.tertiaryContainer)
                          .withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppDesign.controlRadius),
                  ),
                ),
                child: Icon(
                  isDrawing ? Icons.brush_outlined : Icons.edit_note,
                  size: 20,
                  color: isDrawing ? scheme.primary : scheme.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title.isEmpty ? '未命名' : entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDrawing ? '画板' : '笔记',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _timeLabel(entry.at),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _dayLabel(DateTime d) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${d.month} 月 ${d.day} 日 · ${weekdays[d.weekday - 1]}';
}

String _timeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
