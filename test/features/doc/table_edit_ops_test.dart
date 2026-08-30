import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/presentation/table_edit_ops.dart';

void main() {
  group('TableEditOps 纯逻辑', () {
    test('insertRow 在底部插入新行', () {
      final (newRows, newTexts) =
          TableEditOps.insertRow(2, 3, ['a', 'b', 'c', 'd', 'e', 'f']);
      expect(newRows, 3);
      expect(newTexts, ['a', 'b', 'c', 'd', 'e', 'f', '', '', '']);
    });

    test('insertRow 在指定行后插入', () {
      final (newRows, newTexts) =
          TableEditOps.insertRow(2, 2, ['a', 'b', 'c', 'd'], atRow: 0);
      expect(newRows, 3);
      expect(newTexts, ['a', 'b', '', '', 'c', 'd']);
    });

    test('deleteRow 删除最后一行（默认 atRow=-1）', () {
      final (newRows, newTexts) =
          TableEditOps.deleteRow(3, 2, ['a', 'b', 'c', 'd', 'e', 'f']);
      // 3 行 (a,b | c,d | e,f) → 删除第 2 行 → 2 行 (a,b | c,d)
      expect(newRows, 2);
      expect(newTexts, ['a', 'b', 'c', 'd']);
    });

    test('deleteRow 删除指定行', () {
      final (newRows, newTexts) =
          TableEditOps.deleteRow(3, 2, ['a', 'b', 'c', 'd', 'e', 'f'], atRow: 1);
      // 删除第 1 行 (c,d) → (a,b | e,f)
      expect(newRows, 2);
      expect(newTexts, ['a', 'b', 'e', 'f']);
    });

    test('deleteRow 保留至少 1 行', () {
      final (newRows, newTexts) = TableEditOps.deleteRow(1, 2, ['a', 'b']);
      expect(newRows, 1);
      expect(newTexts, ['a', 'b']);
    });

    test('insertCol 在底部插入新列', () {
      final (newCols, newTexts) =
          TableEditOps.insertCol(2, 2, ['a', 'b', 'c', 'd']);
      expect(newCols, 3);
      expect(newTexts, ['a', 'b', '', 'c', 'd', '']);
    });

    test('insertCol 在指定列后插入', () {
      final (newCols, newTexts) =
          TableEditOps.insertCol(2, 2, ['a', 'b', 'c', 'd'], atCol: 0);
      expect(newCols, 3);
      expect(newTexts, ['a', '', 'b', 'c', '', 'd']);
    });

    test('deleteCol 删除最后一列（默认 atCol=-1）', () {
      final (newCols, newTexts) =
          TableEditOps.deleteCol(2, 3, ['a', 'b', 'c', 'd', 'e', 'f']);
      // 3 列 (a,b,c | d,e,f) → 删除第 2 列 (c,f) → (a,b | d,e)
      expect(newCols, 2);
      expect(newTexts, ['a', 'b', 'd', 'e']);
    });

    test('deleteCol 删除指定列', () {
      final (newCols, newTexts) =
          TableEditOps.deleteCol(2, 3, ['a', 'b', 'c', 'd', 'e', 'f'], atCol: 0);
      // 删除第 0 列 (a,d) → (b,c | e,f)
      expect(newCols, 2);
      expect(newTexts, ['b', 'c', 'e', 'f']);
    });

    test('deleteCol 保留至少 1 列', () {
      final (newCols, newTexts) = TableEditOps.deleteCol(2, 1, ['a', 'b']);
      expect(newCols, 1);
      expect(newTexts, ['a', 'b']);
    });

    test('updateCellText 更新指定单元格', () {
      final result =
          TableEditOps.updateCellText(3, ['a', 'b', 'c', 'd', 'e', 'f'],
              rowIndex: 1, colIndex: 1, text: 'NEW');
      expect(result, ['a', 'b', 'c', 'd', 'NEW', 'f']);
    });
  });
}
