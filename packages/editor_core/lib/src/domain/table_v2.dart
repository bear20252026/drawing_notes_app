// editor_core——TableV2 数据库表格（AFFiNE 借鉴——2026-08-21）。
//
// AFFiNE 数据库/表格（database view——多视图数据表）本地化——
// 纯 Dart 不可变模型（可独立测试——R-02 禁 Flutter/dart:io）。
library;

/// 单元格（不可变）。
class TableCellV2 {
  const TableCellV2({required this.id, required this.content});

  final String id;
  final String content;

  TableCellV2 copyWith({String? content}) {
    return TableCellV2(id: id, content: content ?? this.content);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TableCellV2 && id == other.id && content == other.content;

  @override
  int get hashCode => Object.hash(id, content);

  /// 序列化为 JSON 映射。
  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
      };

  /// 从 JSON 映射反序列化。
  static TableCellV2 fromJson(Map<String, dynamic> json) => TableCellV2(
        id: json['id'] as String,
        content: json['content'] as String,
      );
}

/// 行（不可变——列头对齐的单元格列表）。
class TableRowV2 {
  const TableRowV2({required this.id, required this.cells});

  final String id;
  final List<TableCellV2> cells;

  TableRowV2 copyWith({List<TableCellV2>? cells}) {
    return TableRowV2(id: id, cells: cells ?? this.cells);
  }

  /// 获取指定列单元格。
  TableCellV2? cellAt(int index) =>
      index >= 0 && index < cells.length ? cells[index] : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TableRowV2 && id == other.id && _listEquals(cells, other.cells);

  @override
  int get hashCode => Object.hash(id, cells);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 序列化为 JSON 映射。
  Map<String, dynamic> toJson() => {
        'id': id,
        'cells': cells.map((c) => c.toJson()).toList(),
      };

  /// 从 JSON 映射反序列化。
  static TableRowV2 fromJson(Map<String, dynamic> json) => TableRowV2(
        id: json['id'] as String,
        cells: (json['cells'] as List<dynamic>)
            .map((e) => TableCellV2.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 数据库表格（AFFiNE database view 本地化——不可变）。
class TableV2 {
  const TableV2({
    required this.id,
    required this.headers,
    this.rows = const [],
  });

  final String id;
  final List<String> headers;
  final List<TableRowV2> rows;

  TableV2 copyWith({List<String>? headers, List<TableRowV2>? rows}) {
    return TableV2(
      id: id,
      headers: headers ?? this.headers,
      rows: rows ?? this.rows,
    );
  }

  /// 添加行。
  TableV2 addRow(TableRowV2 row) =>
      TableV2(id: id, headers: headers, rows: [...rows, row]);

  /// 移除行。
  TableV2 removeRow(String rowId) =>
      TableV2(id: id, headers: headers, rows: rows.where((r) => r.id != rowId).toList());

  /// 更新行。
  TableV2 updateRow(TableRowV2 row) => TableV2(
        id: id,
        headers: headers,
        rows: rows.map((r) => r.id == row.id ? row : r).toList(),
      );

  /// 更新单元格（rowId + cellIndex）。
  TableV2 updateCell(String rowId, int cellIndex, String content) {
    return TableV2(
      id: id,
      headers: headers,
      rows: rows.map((r) {
        if (r.id != rowId) return r;
        final cells = List<TableCellV2>.from(r.cells);
        if (cellIndex >= 0 && cellIndex < cells.length) {
          cells[cellIndex] = cells[cellIndex].copyWith(content: content);
        }
        return r.copyWith(cells: cells);
      }).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TableV2 &&
          id == other.id &&
          _listEquals(headers, other.headers) &&
          _listEquals(rows, other.rows);

  @override
  int get hashCode => Object.hash(id, headers, rows);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 序列化为 JSON 映射。
  Map<String, dynamic> toJson() => {
        'id': id,
        'headers': headers,
        'rows': rows.map((r) => r.toJson()).toList(),
      };

  /// 从 JSON 映射反序列化。
  static TableV2 fromJson(Map<String, dynamic> json) => TableV2(
        id: json['id'] as String,
        headers: (json['headers'] as List<dynamic>).cast<String>(),
        rows: (json['rows'] as List<dynamic>)
            .map((e) => TableRowV2.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
