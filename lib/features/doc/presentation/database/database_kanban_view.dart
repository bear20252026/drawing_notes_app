/// 数据库块 — 看板视图（P3-2 拆分的展示型子组件）。
///
/// 按指定 select 字段（[groupField]）把已排序记录分列成卡片墙。
/// 纯展示，把「删除」通过 [onRemoveRecord] 抛给协调者。
///
/// #16 完整虚拟化（2026-09-29）：任一分列记录数超过
/// [DatabaseListView.largeRecordThreshold] 时，该列改「限高 + 卡片
/// ListView.builder」行级虚拟化——此前 Column 一次性 build 全部卡片。
library;

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/features/doc/domain/note_database.dart';
import 'package:drawing_notes_app/features/doc/presentation/database/database_cell_editor.dart';
import 'package:drawing_notes_app/features/doc/presentation/database/database_list_view.dart';
import '../../../../core/theme/apple_design.dart';

/// 看板视图。
class DatabaseKanbanView extends StatelessWidget {
  const DatabaseKanbanView({
    super.key,
    required this.fields,
    required this.records,
    required this.groupField,
    required this.titleField,
    this.viewportHeight,
    required this.displayValue,
    required this.onRemoveRecord,
  });

  /// 与 list/table 视图共用的阈值与限高（语义耦合，批次 E/#16）。
  static const int largeRecordThreshold =
      DatabaseListView.largeRecordThreshold;
  static const double maxViewportHeight =
      DatabaseListView.maxViewportHeight;

  final List<NoteFieldDef> fields;
  final List<NoteRecord> records;

  /// 分列依据的 select 字段（null 时由调用方给出空态）。
  final NoteFieldDef? groupField;
  final NoteFieldDef? titleField;

  /// 大列限高视口；null 用默认 [maxViewportHeight]。
  final double? viewportHeight;

  final String Function(NoteRecord record, NoteFieldDef field) displayValue;
  final ValueChanged<NoteRecord> onRemoveRecord;

  @override
  Widget build(BuildContext context) {
    final field = groupField;
    if (records.isEmpty) {
      return _empty(context, '还没有记录，点击“添加记录”');
    }
    if (field == null) {
      return _empty(
        context,
        AppLocalizations.of(context)?.dbKanbanNeedsSelect ??
            '看板需要至少一个“选项”字段，请先添加 select 字段',
      );
    }
    final buckets = <String, List<NoteRecord>>{};
    for (final r in records) {
      final v = r.cell(field.id)?.toString() ?? '';
      buckets.putIfAbsent(v, () => []).add(r);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in buckets.entries) ...[
            _column(context, e.key, e.value),
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Text(
        message,
        style: AppleType.controlStyle(
          Theme.of(context).colorScheme.outline,
        ).copyWith(fontWeight: FontWeight.w400),
      ),
    );
  }

  Widget _column(BuildContext context, String value, List<NoteRecord> records) {
    final scheme = Theme.of(context).colorScheme;
    final isLarge = records.length > largeRecordThreshold;
    final vp = viewportHeight ?? maxViewportHeight;
    final list = ListView.builder(
      itemCount: records.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _card(context, records[i]),
      ),
    );
    final body = isLarge
        ? Expanded(child: list)
        : Column(
            children: [
              for (final r in records) ...[
                _card(context, r),
                const SizedBox(height: 8),
              ],
            ],
          );
    // 大列：整列限高（含列头），列表吃剩余空间——虚拟化卡片。
    return SizedBox(
      width: 230,
      height: isLarge ? vp : null,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: AppleColor.panelOf(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppleRadius.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value.isEmpty
                          ? AppLocalizations.of(context)?.dbUngrouped ?? '未分组'
                          : value,
                      style: DefaultTextStyle.of(
                        context,
                      ).style.copyWith(fontWeight: AppleType.semibold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DatabaseCountPill(count: records.length),
                ],
              ),
              const SizedBox(height: 8),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, NoteRecord record) {
    final scheme = Theme.of(context).colorScheme;
    final t = titleField;
    final title = t != null ? displayValue(record, t) : '';
    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemoveRecord(record),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 12),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.isEmpty
                  ? AppLocalizations.of(context)?.dbNoTitleRecord ?? '无标题记录'
                  : title,
              // 14/600/1.29 正好命中梯子里的 {typography.caption-strong}。
              // 会折行到 2 行，原先没有行高（走 Flutter 默认）。
              style: AppleTypeScale.of(AppleTypeScale.captionStrong, null),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            for (final f in fields.take(3))
              if (f.id != t?.id && displayValue(record, f).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${f.name}: ${displayValue(record, f)}',
                    style: AppleType.captionStyle(scheme.outline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
