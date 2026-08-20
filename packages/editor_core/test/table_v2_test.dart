import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——TableV2 数据库表格测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('TableCellV2：copyWith 不可变', () {
    const cell = TableCellV2(id: 'c1', content: 'hello');
    final updated = cell.copyWith(content: 'world');
    expect(cell.content, 'hello'); // 原实例不变。
    expect(updated.content, 'world');
  });

  test('TableRowV2：cellAt 获取单元格', () {
    const row = TableRowV2(id: 'r1', cells: [
      TableCellV2(id: 'c1', content: 'A'),
      TableCellV2(id: 'c2', content: 'B'),
    ]);
    expect(row.cellAt(0)!.content, 'A');
    expect(row.cellAt(1)!.content, 'B');
    expect(row.cellAt(5), isNull); // 越界返回 null。
  });

  test('TableV2：addRow/removeRow/updateRow', () {
    const table = TableV2(id: 't1', headers: ['Name', 'Age']);
    final withRow = table.addRow(const TableRowV2(id: 'r1', cells: [
      TableCellV2(id: 'c1', content: 'Alice'),
      TableCellV2(id: 'c2', content: '30'),
    ]));
    expect(withRow.rows.length, 1);
    expect(withRow.rows.first.cellAt(0)!.content, 'Alice');

    final removed = withRow.removeRow('r1');
    expect(removed.rows.length, 0);

    final updated = withRow.updateRow(const TableRowV2(id: 'r1', cells: [
      TableCellV2(id: 'c1', content: 'Bob'),
      TableCellV2(id: 'c2', content: '25'),
    ]));
    expect(updated.rows.first.cellAt(0)!.content, 'Bob');
  });

  test('TableV2：updateCell 更新单元格（不可变）', () {
    final table = TableV2(id: 't1', headers: ['Name'], rows: [
      const TableRowV2(id: 'r1', cells: [TableCellV2(id: 'c1', content: 'A')]),
    ]);
    final updated = table.updateCell('r1', 0, 'B');
    expect(updated.rows.first.cellAt(0)!.content, 'B');
    expect(table.rows.first.cellAt(0)!.content, 'A'); // 原表不变。
  });

  test('TableV2：相等性基于字段', () {
    const a = TableV2(id: 't1', headers: ['Name']);
    const b = TableV2(id: 't1', headers: ['Name']);
    const c = TableV2(id: 't2', headers: ['Name']);
    expect(a, b);
    expect(a == c, isFalse);
  });

  test('CreateTableCommand：创建表格到图层 + 撤销', () {
    const doc = DocumentV2(id: 'doc1', pageCount: 1, layers: [
      LayerV2(id: 'l1', name: 'Layer 1'),
    ]);
    final reducer = DocumentReducer(doc);
    final table = TableV2(id: 't1', headers: ['Name'], rows: [
      const TableRowV2(id: 'r1', cells: [TableCellV2(id: 'c1', content: 'A')]),
    ]);

    final newState = reducer.execute(
      CreateTableCommand(layerId: 'l1', table: table),
    );
    expect(newState.layers.first.tables.length, 1);
    expect(newState.layers.first.tables.first.headers, ['Name']);

    final undone = reducer.undo();
    expect(undone!.layers.first.tables.length, 0);
  });
}
