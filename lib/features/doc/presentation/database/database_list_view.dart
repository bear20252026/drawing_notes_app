/// 数据库块 — 列表视图（P3-2 拆分的展示型子组件）。
///
/// 纵向卡片列表，每项展示主字段 + 其余非空字段摘要。
/// 纯展示，把「删除」通过 [onRemoveRecord] 抛给协调者。
library;

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/doc/domain/note_database.dart';

/// 列表视图。
class DatabaseListView extends StatelessWidget {
  const DatabaseListView({
    super.key,
    required this.fields,
    required this.records,
    required this.titleField,
    required this.displayValue,
    required this.onRemoveRecord,
  });

  final List<NoteFieldDef> fields;
  final List<NoteRecord> records;
  final NoteFieldDef? titleField;
  final String Function(NoteRecord record, NoteFieldDef field) displayValue;
  final ValueChanged<NoteRecord> onRemoveRecord;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        child: Text(
          '还没有记录，点击“添加记录”',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    return Column(children: [for (final r in records) _tile(context, r)]);
  }

  Widget _tile(BuildContext context, NoteRecord record) {
    final scheme = Theme.of(context).colorScheme;
    final t = titleField;
    final title = t != null ? displayValue(record, t) : '';
    final summary = fields
        .where((f) => f.id != t?.id && displayValue(record, f).isNotEmpty)
        .map((f) => '${f.name}: ${displayValue(record, f)}')
        .join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      child: ListTile(
        leading: Icon(Icons.article_outlined, color: scheme.primary),
        title: Text(
          title.isEmpty ? '无标题记录' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: '删除记录',
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => onRemoveRecord(record),
        ),
      ),
    );
  }
}
