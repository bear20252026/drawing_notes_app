// TableViewWidget——数据库表格视图（AFFiNE 借鉴——2026-08-24）。
//
// 基于 TableV2 领域模型——支持：
// - 可编辑单元格
// - 添加/删除行和列
// - 列类型（文本/数字/日期/选择）
//
// 版权：AFFiNE（BSL 1.1）——仅概念借鉴——NOTICE 已记录。
library;

import 'package:flutter/material.dart';

import 'package:editor_core/editor_core.dart';

/// 列类型（AFFiNE database view 借鉴）。
enum ColumnType {
  text,
  number,
  date,
  select,
}

/// 表格视图 Widget（AFFiNE database view 借鉴）。
///
/// 受控组件：table 来自父组件，onChanged 回调变更。
class TableViewWidget extends StatefulWidget {
  const TableViewWidget({
    super.key,
    required this.table,
    required this.onChanged,
  });

  /// 表格数据（来自父组件——受控模式）。
  final TableV2 table;

  /// 表格变更回调。
  final ValueChanged<TableV2> onChanged;

  @override
  State<TableViewWidget> createState() => _TableViewWidgetState();
}

class _TableViewWidgetState extends State<TableViewWidget> {
  late List<List<TextEditingController>> _cellControllers;

  @override
  void initState() {
    super.initState();
    _rebuildControllers();
  }

  @override
  void didUpdateWidget(TableViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.table.rows.length != oldWidget.table.rows.length ||
        widget.table.headers.length != oldWidget.table.headers.length) {
      _rebuildControllers();
    }
  }

  void _rebuildControllers() {
    // 释放旧控制器
    for (final row in _cellControllers) {
      for (final c in row) {
        c.dispose();
      }
    }

    // 创建新控制器
    _cellControllers = [];
    for (final row in widget.table.rows) {
      final rowControllers = <TextEditingController>[];
      for (var i = 0; i < widget.table.headers.length; i++) {
        final cell = row.cellAt(i);
        rowControllers.add(TextEditingController(text: cell?.content ?? ''));
      }
      _cellControllers.add(rowControllers);
    }
  }

  @override
  void dispose() {
    for (final row in _cellControllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  /// 更新单元格。
  void _updateCell(int rowIndex, int colIndex, String content) {
    if (rowIndex >= widget.table.rows.length) return;
    final row = widget.table.rows[rowIndex];
    widget.onChanged(widget.table.updateCell(row.id, colIndex, content));
  }

  /// 添加行。
  void _addRow() {
    final newRowId = 'row_${DateTime.now().millisecondsSinceEpoch}';
    final cells = List.generate(
      widget.table.headers.length,
      (i) => TableCellV2(id: 'cell_${newRowId}_$i', content: ''),
    );
    widget.onChanged(widget.table.addRow(
      TableRowV2(id: newRowId, cells: cells),
    ));
  }

  /// 删除行。
  void _deleteRow(String rowId) {
    widget.onChanged(widget.table.removeRow(rowId));
  }

  /// 添加列。
  void _addColumn() {
    final newHeaders = [...widget.table.headers, '新列'];
    final newRows = widget.table.rows.map((row) {
      final newCells = [
        ...row.cells,
        TableCellV2(
          id: 'cell_${row.id}_${row.cells.length}',
          content: '',
        ),
      ];
      return row.copyWith(cells: newCells);
    }).toList();
    widget.onChanged(widget.table.copyWith(
      headers: newHeaders,
      rows: newRows,
    ));
  }

  /// 删除列。
  void _deleteColumn(int colIndex) {
    if (widget.table.headers.length <= 1) return; // 至少保留一列
    final newHeaders = List<String>.from(widget.table.headers)
      ..removeAt(colIndex);
    final newRows = widget.table.rows.map((row) {
      final newCells = List<TableCellV2>.from(row.cells)
        ..removeAt(colIndex);
      return row.copyWith(cells: newCells);
    }).toList();
    widget.onChanged(widget.table.copyWith(
      headers: newHeaders,
      rows: newRows,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final table = widget.table;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 表格标题行
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              // 行号列
              SizedBox(width: 40),
              // 列头
              ...List.generate(table.headers.length, (colIndex) {
                return Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            table.headers[colIndex],
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 删除列按钮
                        if (table.headers.length > 1)
                          GestureDetector(
                            onTap: () => _deleteColumn(colIndex),
                            child: Icon(Icons.close, size: 14,
                                color: theme.colorScheme.outline),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              // 添加列按钮
              GestureDetector(
                onTap: _addColumn,
                child: Container(
                  width: 40,
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.add, size: 16,
                      color: theme.colorScheme.primary),
                ),
              ),
            ],
          ),
        ),

        // 数据行
        ...List.generate(table.rows.length, (rowIndex) {
          final row = table.rows[rowIndex];
          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                // 行号
                Container(
                  width: 40,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    '${rowIndex + 1}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                // 单元格
                ...List.generate(table.headers.length, (colIndex) {
                  if (rowIndex >= _cellControllers.length ||
                      colIndex >= _cellControllers[rowIndex].length) {
                    return Expanded(child: SizedBox.shrink());
                  }
                  final controller = _cellControllers[rowIndex][colIndex];
                  return Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        style: theme.textTheme.bodyMedium,
                        onChanged: (text) =>
                            _updateCell(rowIndex, colIndex, text),
                      ),
                    ),
                  );
                }),
                // 删除行按钮
                GestureDetector(
                  onTap: () => _deleteRow(row.id),
                  child: Container(
                    width: 40,
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.remove, size: 14,
                        color: theme.colorScheme.outline),
                  ),
                ),
              ],
            ),
          );
        }),

        // 添加行按钮
        GestureDetector(
          onTap: _addRow,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
                SizedBox(width: 4),
                Text(
                  '添加行',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
