import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/schedule/domain/schedule_entry.dart';
import 'package:drawing_notes_app/features/schedule/presentation/schedule_calendar.dart';
import 'package:drawing_notes_app/shared/widgets/ambient_background.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

/// 日程 / 日期 —— 月历 + 看板。
///
/// 上半月历：带活动点的日期会高亮，点击某天可只看那一天的记录。
/// 下半看板：按日期分组排列「那天做过的事」（画板或笔记页），点击直接
/// 跳转到对应页面。这其实就是把原来的「时间线」和 AFFiNE 式的「日历」
/// 合并在了一起：日历选日、看板看事。
///
/// 为了不触碰架构边界（schedule 不能 import 其它 feature 的
/// application/infrastructure/presentation），数据由 app 组合层通过
/// [loadNotebooks] / [onOpen] 注入，页面只依赖 notes / drawing 的
/// domain 实体与 core 存储。
class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    this.storage,
    this.loadNotebooks,
    this.onOpen,
  });

  /// 文档存储（core）—— 用于列出画板。
  final StorageService? storage;

  /// 笔记本加载回调（由 app 层注入，避免 schedule 依赖 notes 基础设施）。
  final Future<List<Notebook>> Function()? loadNotebooks;

  /// 点击某条记录，由 app 层负责跳转。
  final void Function(ScheduleEntry entry)? onOpen;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  List<ScheduleEntry> _entries = [];
  bool _loading = true;
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDate;

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
      _loading = false;
    });
  }

  bool _hasActivity(DateTime day) =>
      _entries.any((e) => _dayKey(e.at) == _dayKey(day));

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
                    onMonthChanged: (m) =>
                        setState(() => _focusedMonth = DateTime(m.year, m.month)),
                    onDateTap: _onDateTap,
                  ),
                ),
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
          '看板',
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
      return [
        _emptyState('还没有记录', '画点东西，或写几页笔记，就会出现在这里。'),
      ];
    }
    if (groups.isEmpty) {
      return [
        _emptyState('这一天没有记录', '选中别的日期，或切回「全部日期」看看。'),
      ];
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
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppDesign.accent,
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
      borderRadius: const BorderRadius.all(Radius.circular(AppDesign.cardRadius)),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
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
      borderRadius: const BorderRadius.all(Radius.circular(AppDesign.controlRadius)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(AppDesign.controlRadius)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (isDrawing ? scheme.primaryContainer : scheme.tertiaryContainer)
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
