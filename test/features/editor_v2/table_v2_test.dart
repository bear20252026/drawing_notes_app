// TableV2 数据模型测试（AFFiNE 借鉴——2026-08-24）。
import 'package:flutter_test/flutter_test.dart';

import 'package:editor_core/editor_core.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // TableCellV2
  // ═══════════════════════════════════════════════════════════
  group('TableCellV2', () {
    test('创建单元格', () {
      const cell = TableCellV2(id: 'c1', content: 'Hello');
      expect(cell.id, 'c1');
      expect(cell.content, 'Hello');
    });

    test('copyWith 保留不变字段', () {
      const cell = TableCellV2(id: 'c1', content: 'Old');
      final updated = cell.copyWith(content: 'New');
      expect(updated.id, 'c1');
      expect(updated.content, 'New');
    });

    test('copyWith 默认保留原内容', () {
      const cell = TableCellV2(id: 'c1', content: 'Keep');
      final same = cell.copyWith();
      expect(same.content, 'Keep');
    });

    test('相等性', () {
      const a = TableCellV2(id: 'c1', content: 'X');
      const b = TableCellV2(id: 'c1', content: 'X');
      const c = TableCellV2(id: 'c2', content: 'X');
      expect(a, b);
      expect(a == c, false);
    });

    test('hashCode 一致', () {
      const a = TableCellV2(id: 'c1', content: 'X');
      const b = TableCellV2(id: 'c1', content: 'X');
      expect(a.hashCode, b.hashCode);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // TableRowV2
  // ═══════════════════════════════════════════════════════════
  group('TableRowV2', () {
    test('创建行', () {
      final row = TableRowV2(
        id: 'r1',
        cells: [const TableCellV2(id: 'c1', content: 'A')],
      );
      expect(row.id, 'r1');
      expect(row.cells.length, 1);
    });

    test('cellAt 边界', () {
      final row = TableRowV2(
        id: 'r1',
        cells: [
          const TableCellV2(id: 'c1', content: 'A'),
          const TableCellV2(id: 'c2', content: 'B'),
        ],
      );
      expect(row.cellAt(0)?.content, 'A');
      expect(row.cellAt(1)?.content, 'B');
      expect(row.cellAt(-1), null);
      expect(row.cellAt(2), null);
    });

    test('copyWith 保留不变字段', () {
      final row = TableRowV2(
        id: 'r1',
        cells: [const TableCellV2(id: 'c1', content: 'A')],
      );
      final newRow = row.copyWith(cells: [const TableCellV2(id: 'c2', content: 'B')]);
      expect(newRow.id, 'r1');
      expect(newRow.cells.first.content, 'B');
    });

    test('相等性', () {
      final a = TableRowV2(id: 'r1', cells: [const TableCellV2(id: 'c1', content: 'X')]);
      final b = TableRowV2(id: 'r1', cells: [const TableCellV2(id: 'c1', content: 'X')]);
      final c = TableRowV2(id: 'r2', cells: [const TableCellV2(id: 'c1', content: 'X')]);
      expect(a, b);
      expect(a == c, false);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // TableV2
  // ═══════════════════════════════════════════════════════════
  group('TableV2', () {
    test('创建空表', () {
      const table = TableV2(id: 't1', headers: ['A', 'B']);
      expect(table.id, 't1');
      expect(table.headers, ['A', 'B']);
      expect(table.rows, isEmpty);
    });

    test('addRow', () {
      const table = TableV2(id: 't1', headers: ['X']);
      final row = TableRowV2(
        id: 'r1',
        cells: [const TableCellV2(id: 'c1', content: 'Data')],
      );
      final newTable = table.addRow(row);
      expect(newTable.rows.length, 1);
      expect(newTable.rows.first.cells.first.content, 'Data');
    });

    test('removeRow', () {
      const table = TableV2(
        id: 't1',
        headers: ['X'],
        rows: [
          TableRowV2(id: 'r1', cells: [TableCellV2(id: 'c1', content: 'A')]),
          TableRowV2(id: 'r2', cells: [TableCellV2(id: 'c2', content: 'B')]),
        ],
      );
      final newTable = table.removeRow('r1');
      expect(newTable.rows.length, 1);
      expect(newTable.rows.first.id, 'r2');
    });

    test('updateCell', () {
      const table = TableV2(
        id: 't1',
        headers: ['Name'],
        rows: [
          TableRowV2(id: 'r1', cells: [TableCellV2(id: 'c1', content: 'Old')]),
        ],
      );
      final updated = table.updateCell('r1', 0, 'New');
      expect(updated.rows.first.cells.first.content, 'New');
    });

    test('updateCell 边界——无效行/列', () {
      const table = TableV2(
        id: 't1',
        headers: ['Name'],
        rows: [
          TableRowV2(id: 'r1', cells: [TableCellV2(id: 'c1', content: 'X')]),
        ],
      );
      final updated = table.updateCell('nonexistent', 0, 'Y');
      expect(updated.rows.first.cells.first.content, 'X'); // 未改变

      final updated2 = table.updateCell('r1', 99, 'Y');
      expect(updated2.rows.first.cells.first.content, 'X'); // 列越界
    });

    test('updateRow', () {
      const table = TableV2(
        id: 't1',
        headers: ['Name'],
        rows: [
          TableRowV2(id: 'r1', cells: [TableCellV2(id: 'c1', content: 'A')]),
        ],
      );
      const newRow = TableRowV2(id: 'r1', cells: [TableCellV2(id: 'c1', content: 'B')]);
      final updated = table.updateRow(newRow);
      expect(updated.rows.first.cells.first.content, 'B');
    });

    test('copyWith', () {
      const table = TableV2(id: 't1', headers: ['A']);
      final newTable = table.copyWith(headers: ['A', 'B', 'C']);
      expect(newTable.headers, ['A', 'B', 'C']);
      expect(newTable.id, 't1');
    });

    test('相等性', () {
      const a = TableV2(id: 't1', headers: ['A', 'B']);
      const b = TableV2(id: 't1', headers: ['A', 'B']);
      const c = TableV2(id: 't1', headers: ['A']);
      expect(a, b);
      expect(a == c, false);
    });

    test('hashCode 一致', () {
      const a = TableV2(id: 't1', headers: ['A']);
      const b = TableV2(id: 't1', headers: ['A']);
      expect(a.hashCode, b.hashCode);
    });
  });
}
