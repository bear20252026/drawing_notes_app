import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';

/// 月历网格 —— 纯受控组件。
///
/// 仅呈现「某个月的 7 列日期格」，不做任何数据收集：有活动的日期显示圆点，
/// 点击某天回调 [onDateTap]，切换月份回调 [onMonthChanged]。由父级持有
/// [focusedMonth] 与 [selectedDate]。
class ScheduleCalendar extends StatelessWidget {
  const ScheduleCalendar({
    super.key,
    required this.focusedMonth,
    required this.selectedDate,
    required this.hasActivity,
    required this.onMonthChanged,
    required this.onDateTap,
  });

  /// 当前显示月份（该月第一天）。
  final DateTime focusedMonth;

  /// 被选中的日期；null 表示不看单日。
  final DateTime? selectedDate;

  /// 判断某一天是否「有活动」（有任意条目）。
  final bool Function(DateTime day) hasActivity;

  /// 切换月份回调（传入新的「该月第一天」）。
  final ValueChanged<DateTime> onMonthChanged;

  /// 点击某一天。
  final ValueChanged<DateTime> onDateTap;

  DateTime _addMonths(DateTime base, int delta) =>
      DateTime(base.year, base.month + delta);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

    final first = focusedMonth;
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final leading = first.weekday - 1; // 周一 = 0

    final cells = <Widget>[
      for (final label in weekdayLabels)
        SizedBox(
          height: 28,
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ),
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _buildDayCell(
          date: DateTime(first.year, first.month, day),
          scheme: scheme,
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => onMonthChanged(_addMonths(focusedMonth, -1)),
              icon: const Icon(Icons.chevron_left),
              tooltip: '上个月',
            ),
            Expanded(
              child: Text(
                '${first.year} 年 ${first.month} 月',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            IconButton(
              onPressed: () => onMonthChanged(_addMonths(focusedMonth, 1)),
              icon: const Icon(Icons.chevron_right),
              tooltip: '下个月',
            ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.05,
          children: cells,
        ),
      ],
    );
  }

  Widget _buildDayCell({required DateTime date, required ColorScheme scheme}) {
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final isSelected =
        selectedDate != null &&
        date.year == selectedDate!.year &&
        date.month == selectedDate!.month &&
        date.day == selectedDate!.day;
    final active = hasActivity(date);

    final bg = isSelected
        ? scheme.primary
        : (isToday ? scheme.primaryContainer : Colors.transparent);

    return InkWell(
      onTap: () => onDateTap(date),
      borderRadius: BorderRadius.circular(AppDesign.controlRadius),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppDesign.controlRadius),
          border: isSelected
              ? null
              : (isToday
                    ? Border.all(color: scheme.primary, width: 1.2)
                    : null),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected || isToday
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: isSelected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? (isSelected ? scheme.onPrimary : scheme.tertiary)
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
