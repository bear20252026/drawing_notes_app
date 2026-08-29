// 由 Claude 团队生成 | Drawing Notes App
// 数据库块领域模型（P3-1）：表/看板/列表视图 + 字段/记录/排序/筛选。
// 纯 Dart，无 flutter/io/外部依赖；不可变输入 → 确定性输出。

/// 字段类型。
enum NoteFieldType {
  text,
  number,
  select,
  checkbox,
  date,
}

/// 数据库视图类型。
enum DatabaseViewType {
  table,
  kanban,
  list,
}

/// 字段定义。
class NoteFieldDef {
  const NoteFieldDef({
    required this.id,
    required this.name,
    required this.type,
    this.options = const [],
  });

  final String id;
  final String name;
  final NoteFieldType type;
  final List<String> options;

  NoteFieldDef copyWith({
    String? id,
    String? name,
    NoteFieldType? type,
    List<String>? options,
  }) =>
      NoteFieldDef(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        options: options ?? this.options,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'options': List<String>.from(options),
      };

  factory NoteFieldDef.fromJson(Map<String, dynamic> json) => NoteFieldDef(
        id: json['id'] as String,
        name: json['name'] as String,
        type: NoteFieldType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => NoteFieldType.text,
        ),
        options: (json['options'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteFieldDef &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          _listEquals(options, other.options);

  @override
  int get hashCode => Object.hash(id, name, type, Object.hashAll(options));

  @override
  String toString() =>
      'NoteFieldDef(id: $id, name: $name, type: $type, options: $options)';
}

/// 一条记录（cells: fieldId → value）。
class NoteRecord {
  const NoteRecord({
    required this.id,
    this.cells = const {},
  });

  final String id;
  final Map<String, Object?> cells;

  Object? cell(String fieldId) => cells[fieldId];

  NoteRecord copyWith({
    String? id,
    Map<String, Object?>? cells,
  }) =>
      NoteRecord(
        id: id ?? this.id,
        cells: cells ?? this.cells,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'cells': Map<String, Object?>.from(cells),
      };

  factory NoteRecord.fromJson(Map<String, dynamic> json) => NoteRecord(
        id: json['id'] as String,
        cells: (json['cells'] as Map? ?? const {}).map(
          (k, v) => MapEntry(k as String, v),
        ),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          _mapEquals(cells, other.cells);

  @override
  int get hashCode => Object.hash(id, _mapHashCode(cells));

  @override
  String toString() => 'NoteRecord(id: $id, cells: $cells)';
}

/// 数据库块：字段定义 + 记录 + 视图/排序配置。
class NoteDatabase {
  const NoteDatabase({
    this.fields = const [],
    this.records = const [],
    this.viewType = DatabaseViewType.table,
    this.sortFieldId,
    this.sortAscending = true,
    this.title = '',
  });

  factory NoteDatabase.empty({String title = ''}) => NoteDatabase(title: title);

  final List<NoteFieldDef> fields;
  final List<NoteRecord> records;
  final DatabaseViewType viewType;
  final String? sortFieldId;
  final bool sortAscending;
  final String title;

  /// 区分"未传参"与"传 null"（clearSort 需把 sortFieldId 置 null）。
  static const Object _sentinel = Object();

  NoteDatabase copyWith({
    List<NoteFieldDef>? fields,
    List<NoteRecord>? records,
    DatabaseViewType? viewType,
    Object? sortFieldId = _sentinel,
    bool? sortAscending,
    String? title,
  }) =>
      NoteDatabase(
        fields: fields ?? this.fields,
        records: records ?? this.records,
        viewType: viewType ?? this.viewType,
        sortFieldId:
            identical(sortFieldId, _sentinel) ? this.sortFieldId : sortFieldId as String?,
        sortAscending: sortAscending ?? this.sortAscending,
        title: title ?? this.title,
      );

  // ── 字段 CRUD ──────────────────────────────────────────────

  NoteDatabase addField(NoteFieldDef field) => copyWith(
        fields: [...fields, field],
      );

  NoteDatabase removeField(String fieldId) {
    final newFields = fields.where((f) => f.id != fieldId).toList();
    final newRecords = records
        .map((r) {
          if (!r.cells.containsKey(fieldId)) return r;
          final newCells = Map<String, Object?>.from(r.cells)..remove(fieldId);
          return r.copyWith(cells: newCells);
        })
        .toList();
    // 若删除的是排序字段，清除排序
    final newSortFieldId = sortFieldId == fieldId ? null : sortFieldId;
    return copyWith(
      fields: newFields,
      records: newRecords,
      sortFieldId: newSortFieldId,
    );
  }

  NoteDatabase renameField(String fieldId, String name) =>
      _mapField(fieldId, (f) => f.copyWith(name: name));

  NoteDatabase updateFieldOptions(String fieldId, List<String> options) =>
      _mapField(fieldId, (f) => f.copyWith(options: options));

  NoteDatabase _mapField(
      String fieldId, NoteFieldDef Function(NoteFieldDef) transform) {
    var changed = false;
    final newFields = fields.map((f) {
      if (f.id != fieldId) return f;
      changed = true;
      return transform(f);
    }).toList();
    if (!changed) return this;
    return copyWith(fields: newFields);
  }

  // ── 记录 CRUD ──────────────────────────────────────────────

  NoteDatabase addRecord(NoteRecord record) => copyWith(
        records: [...records, record],
      );

  NoteDatabase removeRecord(String recordId) {
    final newRecords = records.where((r) => r.id != recordId).toList();
    if (newRecords.length == records.length) return this;
    return copyWith(records: newRecords);
  }

  NoteDatabase updateCell(String recordId, String fieldId, Object? value) {
    var changed = false;
    final newRecords = records.map((r) {
      if (r.id != recordId) return r;
      changed = true;
      final newCells = Map<String, Object?>.from(r.cells);
      if (value == null) {
        newCells.remove(fieldId);
      } else {
        newCells[fieldId] = value;
      }
      return r.copyWith(cells: newCells);
    }).toList();
    if (!changed) return this;
    return copyWith(records: newRecords);
  }

  NoteDatabase insertRecordAt(int index, NoteRecord record) {
    final clamped = index.clamp(0, records.length);
    final newRecords = List<NoteRecord>.from(records)
      ..insert(clamped, record);
    return copyWith(records: newRecords);
  }

  // ── 视图与排序 ─────────────────────────────────────────────

  NoteDatabase setViewType(DatabaseViewType viewType) =>
      copyWith(viewType: viewType);

  NoteDatabase setSort(String fieldId, {bool ascending = true}) =>
      copyWith(sortFieldId: fieldId, sortAscending: ascending);

  NoteDatabase clearSort() => copyWith(sortFieldId: null, sortAscending: true);

  NoteFieldDef? fieldById(String fieldId) {
    for (final f in fields) {
      if (f.id == fieldId) return f;
    }
    return null;
  }

  NoteRecord? recordById(String recordId) {
    for (final r in records) {
      if (r.id == recordId) return r;
    }
    return null;
  }

  /// 排序后记录：sortFieldId 为 null 返回原序；否则按字段稳定排序。
  /// 数字字段按数值比较，其余按 String.compareTo。
  List<NoteRecord> get sortedRecords {
    if (sortFieldId == null) return List<NoteRecord>.from(records);
    final field = fieldById(sortFieldId!);
    final isNumber = field?.type == NoteFieldType.number;
    final sorted = List<NoteRecord>.from(records);
    sorted.sort((a, b) {
      final av = a.cell(sortFieldId!);
      final bv = b.cell(sortFieldId!);
      int cmp;
      if (isNumber) {
        final an = _toNum(av);
        final bn = _toNum(bv);
        if (an != null && bn != null) {
          cmp = an.compareTo(bn);
        } else {
          cmp = av.toString().compareTo(bv.toString());
        }
      } else {
        cmp = av.toString().compareTo(bv.toString());
      }
      if (cmp != 0) return sortAscending ? cmp : -cmp;
      return 0; // 稳定：相等保持原序
    });
    return sorted;
  }

  /// 筛选：空 query 返回全部；否则任意字段值 toString 含 query（忽略大小写）。
  List<NoteRecord> filterRecords({String? query}) {
    if (query == null || query.trim().isEmpty) {
      return List<NoteRecord>.from(records);
    }
    final q = query.toLowerCase();
    return records.where((r) {
      for (final entry in r.cells.entries) {
        if (entry.value.toString().toLowerCase().contains(q)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  /// 字段显示字符串。
  String displayValue(NoteRecord record, NoteFieldDef field) {
    final value = record.cell(field.id);
    if (value == null) return '';
    switch (field.type) {
      case NoteFieldType.checkbox:
        return value == true ? '✓' : '';
      case NoteFieldType.text:
      case NoteFieldType.number:
      case NoteFieldType.select:
      case NoteFieldType.date:
        return value.toString();
    }
  }

  // ── 序列化 ─────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'title': title,
        'viewType': viewType.name,
        'sortFieldId': sortFieldId,
        'sortAscending': sortAscending,
        'fields': fields.map((f) => f.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
      };

  factory NoteDatabase.fromJson(Map<String, dynamic> json) => NoteDatabase(
        title: json['title'] as String? ?? '',
        viewType: DatabaseViewType.values.firstWhere(
          (e) => e.name == json['viewType'],
          orElse: () => DatabaseViewType.table,
        ),
        sortFieldId: json['sortFieldId'] as String?,
        sortAscending: json['sortAscending'] as bool? ?? true,
        fields: (json['fields'] as List? ?? const [])
            .map((e) => NoteFieldDef.fromJson(e as Map<String, dynamic>))
            .toList(),
        records: (json['records'] as List? ?? const [])
            .map((e) => NoteRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteDatabase &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          viewType == other.viewType &&
          sortFieldId == other.sortFieldId &&
          sortAscending == other.sortAscending &&
          _listEquals(fields, other.fields) &&
          _listEquals(records, other.records);

  @override
  int get hashCode => Object.hash(
        title,
        viewType,
        sortFieldId,
        sortAscending,
        Object.hashAll(fields),
        Object.hashAll(records),
      );

  @override
  String toString() =>
      'NoteDatabase(title: $title, fields: ${fields.length}, records: ${records.length})';
}

// ── 辅助函数 ─────────────────────────────────────────────────

double? _toNum(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }
  return true;
}

int _mapHashCode<K, V>(Map<K, V> m) {
  var hash = 0;
  for (final entry in m.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
