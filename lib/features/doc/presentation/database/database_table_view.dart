/// 数据库块 — 表视图（P3-2 拆分的展示型子组件）。
///
/// 纯展示：接收已排序/过滤的 [records] 与字段定义，把「点击」通过回调抛给协调者。
/// 不含状态、不写回，与持久化解耦。
library;

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/doc/domain/note_database.dart';

/// 表视图。
class DatabaseTableView extends StatelessWidget {
  const DatabaseTableView({
    super.key,
    required this.fields,
    required this.records,
    required this.sortFieldId,
    required this.sortAscending,
    required this.displayValue,
    required this.onSort,
    required this.onEditCell,
    required this.onToggleCheckbox,
    required this.onPickSelect,
    required this.onRemoveField,
    required this.onRemoveRecord,
  });

  final List<NoteFieldDef> fields;
  final List<NoteRecord> records;
  final String? sortFieldId;
  final bool sortAscending;

  /// 单元格显示文本（如 '✓'、数字串等）。
  final String Function(NoteRecord record, NoteFieldDef field) displayValue;

  final ValueChanged<NoteFieldDef> onSort;
  final void Function(NoteRecord record, NoteFieldDef field) onEditCell;
  final void Function(NoteRecord record, NoteFieldDef field) onToggleCheckbox;
  final void Function(NoteRecord record, NoteFieldDef field) onPickSelect;
  final ValueChanged<NoteFieldDef> onRemoveField;
  final ValueChanged<NoteRecord> onRemoveRecord;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return _empty(context, '还没有字段，点击“添加字段”开始建表');
    }
    if (records.isEmpty) {
      return _empty(context, '还没有记录，点击“添加记录”');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 44,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 56,
        columns: [
          for (final f in fields)
            DataColumn(
              label: _sortableHeader(f),
              numeric: f.type == NoteFieldType.number,
            ),
          const DataColumn(label: SizedBox(width: 28)),
        ],
        rows: [
          for (final r in records)
            DataRow(
              cells: [
                for (final f in fields) DataCell(_cell(context, r, f)),
                DataCell(_deleteRowIcon(r)),
              ],
            ),
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

  Widget _sortableHeader(NoteFieldDef field) {
    final isSorted = sortFieldId == field.id;
    final arrow = isSorted
        ? Icon(
            sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
          )
        : const Icon(Icons.arrow_upward, size: 14, color: Colors.transparent);
    return InkWell(
      onTap: () => onSort(field),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              field.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          arrow,
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: '字段操作',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 60),
            onSelected: (v) {
              if (v == 'remove') onRemoveField(field);
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(value: 'remove', child: Text('删除字段')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, NoteRecord record, NoteFieldDef field) {
    switch (field.type) {
      case NoteFieldType.checkbox:
        final value = record.cell(field.id) == true;
        return InkWell(
          onTap: () => onToggleCheckbox(record, field),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: value
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        );
      case NoteFieldType.select:
        final current = record.cell(field.id);
        return InkWell(
          onTap: () => onPickSelect(record, field),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              current?.toString() ?? '未选择',
              style: TextStyle(
                fontSize: 13,
                color: current == null
                    ? Theme.of(context).colorScheme.outline
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        );
      case NoteFieldType.number:
        return InkWell(
          onTap: () => onEditCell(record, field),
          child: Text(
            displayValue(record, field),
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.right,
          ),
        );
      case NoteFieldType.date:
      case NoteFieldType.text:
        return InkWell(
          onTap: () => onEditCell(record, field),
          child: Text(
            displayValue(record, field),
            style: const TextStyle(fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
    }
  }

  Widget _deleteRowIcon(NoteRecord record) {
    return IconButton(
      tooltip: '删除记录',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.close, size: 16),
      onPressed: () => onRemoveRecord(record),
    );
  }
}
