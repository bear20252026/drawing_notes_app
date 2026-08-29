/// 数据库块真视图（P3-2）。
///
/// 用领域模型 [NoteDatabase]（P3-1）替换原先只 dump JSON 的占位渲染：
/// - 表视图：可排序表头 + 可编辑单元格
/// - 看板视图：按 select 字段分列的卡片墙
/// - 列表视图：纵向卡片列表
///
/// 架构：本文件仅依赖 notes.domain（NoteDatabase/NoteFieldDef/...），与 drawing/chart 解耦。
/// 编辑通过 [onChanged] 把新 [NoteBlock] 写回（数据的 JSON 存于 props['database']）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_database.dart';

/// 数据库块真视图。
class DatabaseBlockView extends StatefulWidget {
  const DatabaseBlockView({
    super.key,
    required this.block,
    this.onChanged,
  });

  /// 数据库块（props['database'] 存 NoteDatabase.toJson() 的 JSON 字符串）。
  final NoteBlock block;

  /// 编辑回调（写回新的 NoteBlock）。
  final ValueChanged<NoteBlock>? onChanged;

  /// 从块 props 解析 NoteDatabase；失败/缺失时返回空库。
  static NoteDatabase decodeDatabase(NoteBlock block) {
    final raw = block.props['database'];
    if (raw is! String || raw.isEmpty) return NoteDatabase.empty();
    try {
      final obj = jsonDecode(raw);
      if (obj is Map<String, dynamic>) return NoteDatabase.fromJson(obj);
    } catch (_) {
      // ignore: fallback
    }
    return NoteDatabase.empty();
  }

  /// 把 NoteDatabase 编码成块 props。
  static Map<String, dynamic> encodeProps(NoteDatabase db) => {
        'database': jsonEncode(db.toJson()),
      };

  @override
  State<DatabaseBlockView> createState() => _DatabaseBlockViewState();
}

class _DatabaseBlockViewState extends State<DatabaseBlockView> {
  late NoteDatabase _db;

  @override
  void initState() {
    super.initState();
    _db = DatabaseBlockView.decodeDatabase(widget.block);
  }

  @override
  void didUpdateWidget(covariant DatabaseBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block) {
      _db = DatabaseBlockView.decodeDatabase(widget.block);
    }
  }

  /// 应用一次领域变更：更新本地状态并写回块。
  void _apply(NoteDatabase Function(NoteDatabase) transform) {
    final next = transform(_db);
    setState(() => _db = next);
    widget.onChanged?.call(
      widget.block.copyWith(props: DatabaseBlockView.encodeProps(next)),
    );
  }

  // ── 头部 ──────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.table_chart_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                _db.title.isEmpty ? '数据库' : _db.title,
                style: text.bodyLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _CountPill(count: _db.records.length),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _buildViewTypeSwitch(),
            const Spacer(),
            IconButton(
              tooltip: '添加字段',
              icon: const Icon(Icons.playlist_add, size: 18),
              onPressed: _addField,
            ),
            IconButton(
              tooltip: '添加记录',
              icon: const Icon(Icons.add, size: 20),
              onPressed: _addRecord,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildViewTypeSwitch() {
    return SegmentedButton<DatabaseViewType>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
      ),
      segments: const [
        ButtonSegment(
          value: DatabaseViewType.table,
          icon: Icon(Icons.table_chart_outlined, size: 16),
          tooltip: '表',
        ),
        ButtonSegment(
          value: DatabaseViewType.kanban,
          icon: Icon(Icons.view_kanban_outlined, size: 16),
          tooltip: '看板',
        ),
        ButtonSegment(
          value: DatabaseViewType.list,
          icon: Icon(Icons.view_list_outlined, size: 16),
          tooltip: '列表',
        ),
      ],
      selected: {_db.viewType},
      onSelectionChanged: (set) {
        if (set.isEmpty) return;
        _apply((d) => d.setViewType(set.first));
      },
    );
  }

  void _addField() {
    final n = _db.fields.length + 1;
    _apply((d) => d.addField(NoteFieldDef(
          id: 'f$n',
          name: '字段${_db.fields.length + 1}',
          type: NoteFieldType.text,
        )));
  }

  void _addRecord() {
    _apply((d) => d.addRecord(NoteRecord(id: 'r${DateTime.now().microsecondsSinceEpoch}')));
  }

  void _removeField(NoteFieldDef field) {
    _apply((d) => d.removeField(field.id));
  }

  void _removeRecord(NoteRecord record) {
    _apply((d) => d.removeRecord(record.id));
  }

  // ── 表视图 ────────────────────────────────────────────────

  Widget _buildTable(BuildContext context) {
    final words = _db.sortedRecords;
    if (_db.fields.isEmpty) {
      return _buildEmptyBody(context, '还没有字段，点击“添加字段”开始建表');
    }
    if (words.isEmpty) {
      return _buildEmptyBody(context, '还没有记录，点击“添加记录”');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 44,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 56,
        columns: [
          for (final f in _db.fields)
            DataColumn(
              label: _buildSortableHeaderCell(f),
              numeric: f.type == NoteFieldType.number,
            ),
          const DataColumn(label: SizedBox(width: 28)),
        ],
        rows: [
          for (final r in words)
            DataRow(
              cells: [
                for (final f in _db.fields)
                  DataCell(_buildCell(context, r, f)),
                DataCell(_buildDeleteRowIcon(r)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSortableHeaderCell(NoteFieldDef field) {
    final isSorted = _db.sortFieldId == field.id;
    final icon = isSorted
        ? Icon(_db.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14)
        : const Icon(Icons.arrow_upward, size: 14, color: Colors.transparent);
    return InkWell(
      onTap: () {
        // 点击同列切换方向，点其他列换列并默认升序
        _apply((d) => d.setSort(field.id,
            ascending: d.sortFieldId == field.id ? !d.sortAscending : true));
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(field.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          icon,
          const SizedBox(width: 8),
          _buildDropForHeader(field),
        ],
      ),
    );
  }

  Widget _buildDropForHeader(NoteFieldDef field) {
    return PopupMenuButton<String>(
      tooltip: '字段操作',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 60),
      onSelected: (v) {
        if (v == 'remove') _removeField(field);
      },
      itemBuilder: (context) => [
        if (field.type == NoteFieldType.select)
          PopupMenuItem<String>(value: 'rename', child: const Text('重命名')),
        const PopupMenuItem<String>(value: 'remove', child: Text('删除字段')),
      ],
    );
  }

  Widget _buildCell(BuildContext context, NoteRecord record, NoteFieldDef field) {
    switch (field.type) {
      case NoteFieldType.checkbox:
        final value = record.cell(field.id) == true;
        return InkWell(
          onTap: () => _apply((d) => d.updateCell(record.id, field.id, !value)),
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
          onTap: () => _pickSelect(record, field),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3),
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
          onTap: () => _editTextCell(record, field, numeric: true),
          child: Text(
            _db.displayValue(record, field),
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.right,
          ),
        );
      case NoteFieldType.date:
        return InkWell(
          onTap: () => _editTextCell(record, field),
          child: Text(
            _db.displayValue(record, field),
            style: const TextStyle(fontSize: 14),
          ),
        );
      case NoteFieldType.text:
        return InkWell(
          onTap: () => _editTextCell(record, field),
          child: Text(
            _db.displayValue(record, field),
            style: const TextStyle(fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
    }
  }

  Widget _buildDeleteRowIcon(NoteRecord record) {
    return IconButton(
      tooltip: '删除记录',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.close, size: 16),
      onPressed: () => _removeRecord(record),
    );
  }

  // ── 看板 ──────────────────────────────────────────────────

  NoteFieldDef? _selectField() {
    for (final f in _db.fields) {
      if (f.type == NoteFieldType.select) return f;
    }
    return null;
  }

  Widget _buildKanban(BuildContext context) {
    final groupField = _selectField();
    if (_db.records.isEmpty) {
      return _buildEmptyBody(context, '还没有记录，点击“添加记录”');
    }
    if (groupField == null) {
      return _buildEmptyBody(context, '看板需要至少一个“选项”字段，请先添加 select 字段');
    }
    final buckets = <String, List<NoteRecord>>{};
    for (final r in _db.sortedRecords) {
      final v = r.cell(groupField.id)?.toString() ?? '';
      buckets.putIfAbsent(v, () => []).add(r);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in buckets.entries) ...[
            _buildKanbanColumn(context, e.key, e.value),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildKanbanColumn(
    BuildContext context,
    String value,
    List<NoteRecord> records,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 230,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
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
                  _CountPill(count: records.length),
                ],
              ),
              const SizedBox(height: 8),
              for (final r in records) ...[
                _buildKanbanCard(context, r),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKanbanCard(BuildContext context, NoteRecord record) {
    final title = _primaryTextField();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title == null || _db.displayValue(record, title).isEmpty
                ? '无标题记录'
                : _db.displayValue(record, title),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          for (final f in _db.fields.take(3))
            if (f.id != title?.id && _db.displayValue(record, f).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${f.name}: ${_db.displayValue(record, f)}',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
      ),
    );
  }

  NoteFieldDef? _primaryTextField() {
    for (final f in _db.fields) {
      if (f.type == NoteFieldType.text) return f;
    }
    return _db.fields.isEmpty ? null : _db.fields.first;
  }

  // ── 列表视图 ──────────────────────────────────────────────

  Widget _buildList(BuildContext context) {
    if (_db.records.isEmpty) {
      return _buildEmptyBody(context, '还没有记录，点击“添加记录”');
    }
    return Column(
      children: [
        for (final r in _db.sortedRecords) _buildListTile(context, r),
      ],
    );
  }

  Widget _buildListTile(BuildContext context, NoteRecord record) {
    final title = _primaryTextField();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      child: ListTile(
        leading: Icon(Icons.article_outlined, color: scheme.primary),
        title: Text(
          title == null || _db.displayValue(record, title).isEmpty
              ? '无标题记录'
              : _db.displayValue(record, title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _db.fields
              .where((f) => f.id != title?.id && _db.displayValue(record, f).isNotEmpty)
              .map((f) => '${f.name}: ${_db.displayValue(record, f)}')
              .join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: '删除记录',
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => _removeRecord(record),
        ),
      ),
    );
  }

  // ── 单元格编辑 ────────────────────────────────────────────

  Future<void> _editTextCell(NoteRecord record, NoteFieldDef field,
      {bool numeric = false}) async {
    final controller = TextEditingController(
      text: _db.displayValue(record, field),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑${field.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: const InputDecoration(hintText: '输入值'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final String raw = result.trim();
    Object? value;
    if (raw.isEmpty) {
      value = null;
    } else if (raw case final s when numeric) {
      value = num.tryParse(s) ?? s;
    } else {
      value = raw;
    }
    _apply((d) => d.updateCell(record.id, field.id, value));
  }

  void _pickSelect(NoteRecord record, NoteFieldDef field) {
    final options = <String>['未选择', ...field.options];
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in options)
              ListTile(
                title: Text(o == '未选择' ? '未选择' : o),
                onTap: () =>
                    Navigator.pop(ctx, o == '未选择' ? null : o),
              ),
          ],
        ),
      ),
    ).then((value) {
      if (value == null) return;
      // 用户在底部弹层里点了“未选择”也算取消？这里把“未选择”翻译成清空（null）。
      _apply((d) => d.updateCell(record.id, field.id, value));
    }).catchError((_) {
      // ignored
    });
  }

  // ── 空态 ──────────────────────────────────────────────────

  Widget _buildEmptyBody(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Text(
        message,
        style: TextStyle(color: scheme.outline, fontSize: 13),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 8),
          switch (_db.viewType) {
            DatabaseViewType.table => _buildTable(context),
            DatabaseViewType.kanban => _buildKanban(context),
            DatabaseViewType.list => _buildList(context),
          },
        ],
      ),
    );
  }
}

/// 记录数量胶囊。
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count 条记录',
        style: TextStyle(fontSize: 12, color: scheme.primary),
      ),
    );
  }
}
