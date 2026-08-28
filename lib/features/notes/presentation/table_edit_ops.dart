/// 表格编辑纯逻辑操作。
///
/// 提供表格行列增删的纯函数操作，便于单测。
/// 所有操作返回新的行列数与单元格文本列表，不修改输入。
library;

/// 表格编辑操作工具类。
///
/// 单元格按行优先顺序存储：cellIndex = rowIndex * cols + colIndex。
class TableEditOps {
  const TableEditOps._();

  /// 在指定行索引后插入新行（该行空白）。
  ///
  /// 返回 (newRows, newCellTexts)。
  static (int, List<String>) insertRow(
    int rows,
    int cols,
    List<String> cellTexts, {
    int atRow = -1,
  }) {
    final insertAt = atRow < 0 ? rows : (atRow + 1).clamp(0, rows);
    final newTexts = List<String>.from(cellTexts);
    // 在插入位置添加 cols 个空白单元格
    newTexts.insertAll(insertAt * cols, List<String>.filled(cols, ''));
    return (rows + 1, newTexts);
  }

  /// 删除指定行。
  ///
  /// 若 atRow 为 -1 删除最后一行；若删除后行数 < 1，保持 1 行。
  /// 返回 (newRows, newCellTexts)。
  static (int, List<String>) deleteRow(
    int rows,
    int cols,
    List<String> cellTexts, {
    int atRow = -1,
  }) {
    if (rows <= 1) return (rows, cellTexts);
    final removeAt = atRow < 0 ? rows - 1 : atRow.clamp(0, rows - 1);
    final newTexts = List<String>.from(cellTexts);
    newTexts.removeRange(removeAt * cols, (removeAt + 1) * cols);
    return (rows - 1, newTexts);
  }

  /// 在指定列索引后插入新列（该列空白）。
  ///
  /// 返回 (newCols, newCellTexts)。
  static (int, List<String>) insertCol(
    int rows,
    int cols,
    List<String> cellTexts, {
    int atCol = -1,
  }) {
    // insertAfterCol: 在该列索引之后插入新列。-1 表示追加到末尾。
    final insertAfterCol = atCol < 0 ? cols - 1 : atCol.clamp(0, cols - 1);
    final newTexts = <String>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final srcIndex = r * cols + c;
        newTexts.add(srcIndex < cellTexts.length ? cellTexts[srcIndex] : '');
        if (c == insertAfterCol) {
          newTexts.add(''); // 在该列后插入空白列
        }
      }
    }
    return (cols + 1, newTexts);
  }

  /// 删除指定列。
  ///
  /// 若删除后列数 < 1，保持 1 列。返回 (newCols, newCellTexts)。
  static (int, List<String>) deleteCol(
    int rows,
    int cols,
    List<String> cellTexts, {
    int atCol = -1,
  }) {
    if (cols <= 1) return (cols, cellTexts);
    final removeAt = atCol < 0 ? cols - 1 : atCol.clamp(0, cols - 1);
    final newTexts = <String>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (c == removeAt) continue;
        final srcIndex = r * cols + c;
        newTexts.add(srcIndex < cellTexts.length ? cellTexts[srcIndex] : '');
      }
    }
    return (cols - 1, newTexts);
  }

  /// 更新指定单元格的文本。
  static List<String> updateCellText(
    int cols,
    List<String> cellTexts, {
    required int rowIndex,
    required int colIndex,
    required String text,
  }) {
    final index = rowIndex * cols + colIndex;
    final newTexts = List<String>.from(cellTexts);
    // 确保列表足够长
    while (newTexts.length <= index) {
      newTexts.add('');
    }
    newTexts[index] = text;
    return newTexts;
  }
}
