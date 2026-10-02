/// 数据库块 — 表视图（P3-2 拆分的展示型子组件）。
///
/// 纯展示：接收已排序/过滤的 [records] 与字段定义，把「点击」通过回调抛给协调者。
/// 不含状态、不写回，与持久化解耦。
///
/// #16 完整虚拟化（2026-09-29）：表头与数据行分离——行用
/// [ListView.builder] 行级虚拟化；记录数超过 [largeRecordThreshold] 时限高
/// 内部滚动（与 list 视图同一交互语义）。此前 DataTable 一次性布局全部
/// DataRow，限高只做视口裁剪、并未真正虚拟化。
library;

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/features/doc/domain/note_database.dart';
import '../../../../core/theme/apple_design.dart';

/// 表视图。
class DatabaseTableView extends StatelessWidget {
  const DatabaseTableView({
    super.key,
    required this.fields,
    required this.records,
    required this.sortFieldId,
    required this.sortAscending,
    this.viewportHeight,
    required this.displayValue,
    required this.onSort,
    required this.onEditCell,
    required this.onToggleCheckbox,
    required this.onPickSelect,
    required this.onRemoveField,
    required this.onRemoveRecord,
  });

  /// 审计 2026-09-26 #16：超过该记录数时限高内部滚动——与
  /// [DatabaseListView.largeRecordThreshold] 同值（语义耦合）。
  static const int largeRecordThreshold = 50;

  /// 大数据集的视口上限（与 list 视图一致，约一屏高）。
  static const double maxViewportHeight = 480;

  /// 数据行基准高度（触控 44 下限 + 垂直内边距，对齐原 DataTable 行高）。
  static const double rowHeight = 48;

  final List<NoteFieldDef> fields;
  final List<NoteRecord> records;
  final String? sortFieldId;
  final bool sortAscending;

  /// 大数据集限高视口；null 用默认 [maxViewportHeight]。
  /// 协调层在有界父容器里按剩余高度压低，避免「表头+视口」溢出外层 Column。
  final double? viewportHeight;

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
      return _empty(
        context,
        AppLocalizations.of(context)?.dbNoFieldsYet ?? '还没有字段，点击“添加字段”开始建表',
      );
    }
    if (records.isEmpty) {
      return _empty(context, '还没有记录，点击“添加记录”');
    }

    final header = _header(context);
    // 行级虚拟化：builder 只 build 视口内（+ cacheExtent）可见行。
    final body = ListView.builder(
      itemCount: records.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, i) => _dataRow(context, records[i]),
    );

    // 大数据集：限高内部滚动 + 行级虚拟化。交互语义与 list 视图一致：
    // 大表在约一屏高内滚动，不再把文档页无限撑长。
    // 有界父级传入 viewportHeight 时，SizedBox 会被父级（Expanded）紧约束，
    // 高度自动取剩余空间——无需在此再减 chrome。
    if (records.length > largeRecordThreshold) {
      final vp = viewportHeight ?? maxViewportHeight;
      return SizedBox(
        height: vp,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const Divider(height: 1, thickness: 0.5),
            Expanded(child: body),
          ],
        ),
      );
    }
    // 小数据集：自然高度嵌入文档滚动；仍走 builder（行为零变化）。
    // 注意：Column 在文档滚动里高度无界，不能包 Flexible/Expanded。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Divider(height: 1, thickness: 0.5),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: records.length,
          padding: EdgeInsets.zero,
          itemBuilder: (context, i) => _dataRow(context, records[i]),
        ),
      ],
    );
  }

  double _columnWidth(NoteFieldDef field) {
    switch (field.type) {
      case NoteFieldType.checkbox:
        return 72;
      case NoteFieldType.number:
        return 100;
      case NoteFieldType.select:
        return 140;
      case NoteFieldType.date:
      case NoteFieldType.text:
        return 160;
    }
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

  Widget _header(BuildContext context) {
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in fields)
              SizedBox(
                width: _columnWidth(f),
                child: Align(
                  alignment: f.type == NoteFieldType.number
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: _sortableHeader(context, f),
                ),
              ),
            // D-12（审计 2026-09-27）：28 离档 → AppleSpacing.xl（就近归档，
            // 同 sweep「仅数值归档不改布局结构」）。删除列固定宽——表头占位与
            // 行内按钮**必须同值**，否则表头与数据列错位。
            const SizedBox(width: AppleSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _dataRow(BuildContext context, NoteRecord record) {
    return SizedBox(
      height: rowHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in fields)
              SizedBox(
                width: _columnWidth(f),
                child: Align(
                  alignment: f.type == NoteFieldType.number
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: _cell(context, record, f),
                ),
              ),
            // D-12：删除列宽与表头占位同步归一（见表头侧注释）。
            SizedBox(
              width: AppleSpacing.xl,
              child: _deleteRowIcon(context, record),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sortableHeader(BuildContext context, NoteFieldDef field) {
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
              style: DefaultTextStyle.of(
                context,
              ).style.copyWith(fontWeight: AppleType.semibold),
            ),
          ),
          const SizedBox(width: 4),
          arrow,
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: AppLocalizations.of(context)?.dbFieldActions ?? '字段操作',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 60),
            onSelected: (v) {
              if (v == 'remove') onRemoveField(field);
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'remove',
                child: Text(
                  AppLocalizations.of(context)?.dbDeleteField ?? '删除字段',
                ),
              ),
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
        // U4a：触控目标 ≥44（20px 图标居中在 44×44 热区内）；
        // R6：读屏语义（checked 状态 + button）。
        return Semantics(
          label: AppLocalizations.of(context)?.dbToggleCheck ?? '切换勾选',
          checked: value,
          button: true,
          child: SizedBox(
            width: 44,
            height: 44,
            child: InkWell(
              onTap: () => onToggleCheckbox(record, field),
              child: Center(
                child: Icon(
                  value ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: value
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
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
              borderRadius: BorderRadius.circular(AppleRadius.xs),
            ),
            child: Text(
              current?.toString() ?? '未选择',
              style: AppleType.controlStyle(
                current == null
                    ? Theme.of(context).colorScheme.outline
                    : Theme.of(context).colorScheme.onSurface,
              ).copyWith(fontWeight: FontWeight.w400),
            ),
          ),
        );
      case NoteFieldType.number:
        return InkWell(
          onTap: () => onEditCell(record, field),
          child: Text(
            displayValue(record, field),
            style: AppleType.controlStyle(
              Theme.of(context).colorScheme.onSurface,
            ).copyWith(fontWeight: FontWeight.w400),
            textAlign: TextAlign.right,
          ),
        );
      case NoteFieldType.date:
      case NoteFieldType.text:
        return InkWell(
          onTap: () => onEditCell(record, field),
          child: Text(
            displayValue(record, field),
            // 14/400/1.43 = 梯子里的 {typography.caption}；会折行到 2 行。
            style: AppleTypeScale.of(AppleTypeScale.caption, null),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
    }
  }

  Widget _deleteRowIcon(BuildContext context, NoteRecord record) {
    return IconButton(
      tooltip: AppLocalizations.of(context)?.dbDeleteRecord ?? '删除记录',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.close, size: 16),
      onPressed: () => onRemoveRecord(record),
    );
  }
}
