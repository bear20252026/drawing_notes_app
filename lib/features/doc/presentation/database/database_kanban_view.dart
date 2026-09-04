/// 数据库块 — 看板视图（P3-2 拆分的展示型子组件）。
///
/// 按指定 select 字段（[groupField]）把已排序记录分列成卡片墙。
/// 纯展示，把「删除」通过 [onRemoveRecord] 抛给协调者。
library;

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/doc/domain/note_database.dart';
import 'package:drawing_notes_app/features/doc/presentation/database/database_cell_editor.dart';
import '../../../../core/theme/apple_design.dart';

/// 看板视图。
class DatabaseKanbanView extends StatelessWidget {
  const DatabaseKanbanView({
    super.key,
    required this.fields,
    required this.records,
    required this.groupField,
    required this.titleField,
    required this.displayValue,
    required this.onRemoveRecord,
  });

  final List<NoteFieldDef> fields;
  final List<NoteRecord> records;

  /// 分列依据的 select 字段（null 时由调用方给出空态）。
  final NoteFieldDef? groupField;
  final NoteFieldDef? titleField;

  final String Function(NoteRecord record, NoteFieldDef field) displayValue;
  final ValueChanged<NoteRecord> onRemoveRecord;

  @override
  Widget build(BuildContext context) {
    final field = groupField;
    if (records.isEmpty) {
      return _empty(context, '还没有记录，点击“添加记录”');
    }
    if (field == null) {
      return _empty(context, '看板需要至少一个“选项”字段，请先添加 select 字段');
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
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _column(BuildContext context, String value, List<NoteRecord> records) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 230,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: AppleColor.panelOf(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppleRadius.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value.isEmpty ? '未分组' : value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DatabaseCountPill(count: records.length),
                ],
              ),
              const SizedBox(height: 8),
              for (final r in records) ...[
                _card(context, r),
                const SizedBox(height: 6),
              ],
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
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.isEmpty ? '无标题记录' : title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
                    style: TextStyle(fontSize: 12, color: scheme.outline),
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
