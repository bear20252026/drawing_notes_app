/// 内嵌表格编辑器部件。
///
/// 自包含的表格编辑器，提供增删行列、编辑格子文本功能。
/// 编辑结果通过 [onChanged] 回调写回 NoteBlock。
library;

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/presentation/table_edit_ops.dart';

/// 内嵌表格编辑器。
///
/// 展示一个可编辑的表格，支持增删行列和编辑单元格文本。
/// 每次编辑通过 [onChanged] 回调传出更新后的 NoteBlock。
class TableEditorWidget extends StatefulWidget {
  const TableEditorWidget({
    super.key,
    required this.block,
    required this.onChanged,
  });

  /// 要编辑的表格块。
  final NoteBlock block;

  /// 编辑后的回调：传出更新后的 NoteBlock。
  final ValueChanged<NoteBlock> onChanged;

  @override
  State<TableEditorWidget> createState() => _TableEditorWidgetState();
}

class _TableEditorWidgetState extends State<TableEditorWidget> {
  late int _rows;
  late int _cols;
  late List<String> _cellTexts;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _rows = (widget.block.props['rows'] as int? ?? 1).clamp(1, 50);
    _cols = (widget.block.props['cols'] as int? ?? 1).clamp(1, 10);

    // 从 children 中提取单元格文本
    _cellTexts = <String>[];
    for (final child in widget.block.children) {
      _cellTexts.add(child.text);
    }
    // 确保足够
    while (_cellTexts.length < _rows * _cols) {
      _cellTexts.add('');
    }

    // 为每个单元格创建控制器
    for (int i = 0; i < _cellTexts.length; i++) {
      _controllers['$i'] = TextEditingController(text: _cellTexts[i]);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _emitChange() {
    // 从控制器收集最新文本
    for (int i = 0; i < _cellTexts.length; i++) {
      final controller = _controllers['$i'];
      if (controller != null) {
        _cellTexts[i] = controller.text;
      }
    }

    // 构建新的 children（text 块列表）
    final children = <NoteBlock>[];
    for (int i = 0; i < _cellTexts.length; i++) {
      children.add(NoteBlock.textBlock(
        'cell_${i}_${DateTime.now().microsecondsSinceEpoch}',
        text: _cellTexts[i],
      ));
    }

    widget.onChanged(
      widget.block.copyWith(
        props: {
          ...widget.block.props,
          'rows': _rows,
          'cols': _cols,
        },
        children: children,
      ),
    );
  }

  void _insertRow(int atRow) {
    setState(() {
      final result = TableEditOps.insertRow(_rows, _cols, _cellTexts, atRow: atRow);
      _rows = result.$1;
      _cellTexts = result.$2;
      // 为新行添加控制器
      for (int i = 0; i < _cellTexts.length; i++) {
        _controllers.putIfAbsent(
          '$i',
          () => TextEditingController(text: _cellTexts[i]),
        );
      }
    });
    _emitChange();
  }

  void _deleteRow(int atRow) {
    if (_rows <= 1) return;
    setState(() {
      final result = TableEditOps.deleteRow(_rows, _cols, _cellTexts, atRow: atRow);
      _rows = result.$1;
      _cellTexts = result.$2;
    });
    _emitChange();
  }

  void _insertCol(int atCol) {
    setState(() {
      final result = TableEditOps.insertCol(_rows, _cols, _cellTexts, atCol: atCol);
      _cols = result.$1;
      _cellTexts = result.$2;
      for (int i = 0; i < _cellTexts.length; i++) {
        _controllers.putIfAbsent(
          '$i',
          () => TextEditingController(text: _cellTexts[i]),
        );
      }
    });
    _emitChange();
  }

  void _deleteCol(int atCol) {
    if (_cols <= 1) return;
    setState(() {
      final result = TableEditOps.deleteCol(_rows, _cols, _cellTexts, atCol: atCol);
      _cols = result.$1;
      _cellTexts = result.$2;
    });
    _emitChange();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 工具栏
          Row(
            children: [
              Text('表格 $_rows×$_cols',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: scheme.primary)),
              const Spacer(),
              // 列操作
              _ToolButton(
                icon: Icons.add,
                tooltip: '添加列',
                onPressed: () => _insertCol(_cols - 1),
              ),
              _ToolButton(
                icon: Icons.remove,
                tooltip: '删除列',
                onPressed: () => _deleteCol(_cols - 1),
              ),
              const SizedBox(width: 4),
              // 行操作
              _ToolButton(
                icon: Icons.exposure_plus_1,
                tooltip: '添加行',
                onPressed: () => _insertRow(_rows - 1),
              ),
              _ToolButton(
                icon: Icons.exposure_minus_1,
                tooltip: '删除行',
                onPressed: () => _deleteRow(_rows - 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 可编辑表格
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder.all(
                color: scheme.outlineVariant,
                width: 1,
              ),
              defaultColumnWidth: const FixedColumnWidth(100),
              children: List.generate(_rows, (rowIndex) {
                return TableRow(
                  children: List.generate(_cols, (colIndex) {
                    final cellIndex = rowIndex * _cols + colIndex;
                    return Padding(
                      padding: const EdgeInsets.all(4),
                      child: TextField(
                        controller: _controllers['$cellIndex'],
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        style: const TextStyle(fontSize: 13),
                        maxLines: 2,
                        onChanged: (value) {
                          _cellTexts[cellIndex] = value;
                          _emitChange();
                        },
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
