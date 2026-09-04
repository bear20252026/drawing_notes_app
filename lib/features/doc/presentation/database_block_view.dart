/// 数据库块真视图（P3-2）。
///
/// 调度者（协调者）：持有 [NoteDatabase] 状态并把编辑写回块。
/// 三种视图（表 / 看板 / 列表）与单元格编辑器被拆到 `database/` 子目录，
/// 本文件只负责编排——字段/记录 CRUD、排序、视图切换、写回 props['database']。
///
/// 架构：仅依赖 notes.domain（NoteDatabase/NoteFieldDef/...），与 drawing/chart 解耦。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_database.dart';
import 'package:drawing_notes_app/features/doc/presentation/database/database_cell_editor.dart';
import 'package:drawing_notes_app/features/doc/presentation/database/database_kanban_view.dart';
import 'package:drawing_notes_app/features/doc/presentation/database/database_list_view.dart';
import 'package:drawing_notes_app/features/doc/presentation/database/database_table_view.dart';
import '../../../core/theme/apple_design.dart';

/// 数据库块真视图。
class DatabaseBlockView extends StatefulWidget {
  const DatabaseBlockView({super.key, required this.block, this.onChanged});

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
  final _filterController = TextEditingController();
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _db = DatabaseBlockView.decodeDatabase(widget.block);
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
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
            DatabaseCountPill(count: _visible.length),
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
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: TextField(
            controller: _filterController,
            decoration: InputDecoration(
              hintText: '搜索记录',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _filterQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _filterController.clear();
                        setState(() => _filterQuery = '');
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppleRadius.sm),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 8,
              ),
            ),
            onChanged: (v) => setState(() => _filterQuery = v),
          ),
        ),
      ],
    );
  }

  /// 展示记录：无筛选时按当前排序，有筛选时按字段值匹配。
  List<NoteRecord> get _visible {
    final q = _filterQuery.trim();
    if (q.isEmpty) return _db.sortedRecords;
    return _db.filterRecords(query: q);
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
    _apply(
      (d) => d.addField(
        NoteFieldDef(
          id: 'f${d.fields.length + 1}',
          name: '字段${d.fields.length + 1}',
          type: NoteFieldType.text,
        ),
      ),
    );
  }

  void _addRecord() {
    _apply(
      (d) => d.addRecord(
        NoteRecord(id: 'r${DateTime.now().microsecondsSinceEpoch}'),
      ),
    );
  }

  void _removeField(NoteFieldDef field) =>
      _apply((d) => d.removeField(field.id));

  void _removeRecord(NoteRecord record) =>
      _apply((d) => d.removeRecord(record.id));

  // ── 单元格编辑（转发到 database/ 工具） ─────────────────────

  void _editCell(NoteRecord record, NoteFieldDef field) {
    showTextCellEditor(
      context,
      fieldName: field.name,
      initial: _db.displayValue(record, field),
      numeric: field.type == NoteFieldType.number,
      onSave: (value) =>
          _apply((d) => d.updateCell(record.id, field.id, value)),
    );
  }

  void _toggleCheckbox(NoteRecord record, NoteFieldDef field) {
    final value = record.cell(field.id) == true;
    _apply((d) => d.updateCell(record.id, field.id, !value));
  }

  void _pickSelect(NoteRecord record, NoteFieldDef field) {
    showSelectPicker(
      context,
      options: field.options,
      onPick: (value) =>
          _apply((d) => d.updateCell(record.id, field.id, value)),
    );
  }

  // ── 字段选择辅助（看板分列 / 列表主字段） ──────────────────

  NoteFieldDef? _selectField() {
    for (final f in _db.fields) {
      if (f.type == NoteFieldType.select) return f;
    }
    return null;
  }

  NoteFieldDef? _primaryTextField() {
    for (final f in _db.fields) {
      if (f.type == NoteFieldType.text) return f;
    }
    return _db.fields.isEmpty ? null : _db.fields.first;
  }

  // ── build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final records = _visible;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppleRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 8),
          switch (_db.viewType) {
            DatabaseViewType.table => DatabaseTableView(
              fields: _db.fields,
              records: records,
              sortFieldId: _db.sortFieldId,
              sortAscending: _db.sortAscending,
              displayValue: _db.displayValue,
              onSort: (f) => _apply(
                (d) => d.setSort(
                  f.id,
                  ascending: d.sortFieldId == f.id ? !d.sortAscending : true,
                ),
              ),
              onEditCell: _editCell,
              onToggleCheckbox: _toggleCheckbox,
              onPickSelect: _pickSelect,
              onRemoveField: _removeField,
              onRemoveRecord: _removeRecord,
            ),
            DatabaseViewType.kanban => DatabaseKanbanView(
              fields: _db.fields,
              records: records,
              groupField: _selectField(),
              titleField: _primaryTextField(),
              displayValue: _db.displayValue,
              onRemoveRecord: _removeRecord,
            ),
            DatabaseViewType.list => DatabaseListView(
              fields: _db.fields,
              records: records,
              titleField: _primaryTextField(),
              displayValue: _db.displayValue,
              onRemoveRecord: _removeRecord,
            ),
          },
        ],
      ),
    );
  }
}
