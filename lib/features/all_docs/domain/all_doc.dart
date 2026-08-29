// 由 Claude 团队生成 | Drawing Notes App
// AllDoc：AFFiNE「全部文档」统一领域模型 + 分组纯函数。
// 纯 Dart，无 flutter/io/controller/存储依赖。

/// 统一文档种类。
enum AllDocKind {
  /// 画布文档（drawing）。
  canvas,

  /// 笔记页（属于某个 notebook）。
  note,

  /// 块文档（blockdoc）。
  blockdoc,
}

/// 全部文档的时间分组（仿 AFFiNE 分组语义）。
enum AllDocGroup {
  /// 今天内更新。
  today,

  /// 本周内（非今天）更新。
  thisWeek,

  /// 7 天前或更早更新。
  earlier,

  /// 从未更新（updatedAt == createdAt 且 createdAt 早于今天）。
  neverUpdated,
}

/// 分组后的文档区段。
class AllDocSection {
  const AllDocSection({
    required this.group,
    required this.label,
    required this.docs,
  });

  /// 分组标识。
  final AllDocGroup group;

  /// 展示用分组标签。
  final String label;

  /// 该分组下的文档列表（已排序）。
  final List<AllDoc> docs;

  /// 该分组是否无文档。
  bool get isEmpty => docs.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AllDocSection &&
          runtimeType == other.runtimeType &&
          group == other.group &&
          label == other.label &&
          _listEquals(docs, other.docs);

  @override
  int get hashCode => Object.hash(group, label, Object.hashAll(docs));

  @override
  String toString() =>
      'AllDocSection($group, $label, ${docs.length} docs)';
}

/// 统一文档条目：把画布、笔记页、块文档统一成一种视图模型。
///
/// 不可变；所有修改通过 [copyWith] 返回新实例。
class AllDoc {
  const AllDoc({
    required this.id,
    required this.title,
    required this.kind,
    required this.folder,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.isFavorite = false,
    this.notebookId,
    this.pageId,
    this.drawingId,
  });

  /// 文档唯一标识。
  final String id;

  /// 展示标题。
  final String title;

  /// 文档种类。
  final AllDocKind kind;

  /// 所属文件夹路径（空串表示根目录）。
  final String folder;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后修改时间。
  final DateTime updatedAt;

  /// 摘要/描述（可选，用于展示副标题）。
  final String description;

  /// 是否收藏。
  final bool isFavorite;

  /// 笔记页所属的 notebook id（kind==note 时有效）。
  final String? notebookId;

  /// 笔记页自身的 page id（kind==note 时有效）。
  final String? pageId;

  /// 画布文档 id（kind==canvas 时有效，通常同 [id]）。
  final String? drawingId;

  /// 用于去重的稳定键：'$kind:$id'。
  String get dedupKey => '${kind.name}:$id';

  /// 不可变 copyWith。
  AllDoc copyWith({
    String? id,
    String? title,
    AllDocKind? kind,
    String? folder,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? description,
    bool? isFavorite,
    String? notebookId,
    String? pageId,
    String? drawingId,
  }) {
    return AllDoc(
      id: id ?? this.id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      folder: folder ?? this.folder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: description ?? this.description,
      isFavorite: isFavorite ?? this.isFavorite,
      notebookId: notebookId ?? this.notebookId,
      pageId: pageId ?? this.pageId,
      drawingId: drawingId ?? this.drawingId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AllDoc &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          kind == other.kind &&
          folder == other.folder &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          description == other.description &&
          isFavorite == other.isFavorite &&
          notebookId == other.notebookId &&
          pageId == other.pageId &&
          drawingId == other.drawingId;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        kind,
        folder,
        createdAt,
        updatedAt,
        description,
        isFavorite,
        notebookId,
        pageId,
        drawingId,
      );

  @override
  String toString() => 'AllDoc(${kind.name}:$id, $title)';
}

/// 判断两个 DateTime 是否为同一天（按本地日期）。
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 计算两个 DateTime 相差的天数（按本地日期，忽略时刻）。
int _daysBetween(DateTime a, DateTime b) {
  final da = DateTime(a.year, a.month, a.day);
  final db = DateTime(b.year, b.month, b.day);
  return db.difference(da).inDays;
}

/// 分组纯函数：根据文档的 updatedAt 与 now 的关系判定分组。
///
/// 规则（确定性）：
/// - [AllDocGroup.today]：updatedAt 与 now 同一天。/// - [AllDocGroup.thisWeek]：updatedAt 在本周内（非今天，7 天内）。/// - [AllDocGroup.earlier]：updatedAt 在 7 天前或更早。/// - [AllDocGroup.neverUpdated]：updatedAt == createdAt 且 createdAt 早于今天///   （从未编辑过）。
AllDocGroup groupOf(AllDoc doc, {required DateTime now}) {
  // 从未更新：创建后从未编辑过（updatedAt == createdAt 且早于今天）。
  if (_sameDay(doc.createdAt, doc.updatedAt) &&
      !_sameDay(doc.createdAt, now)) {
    return AllDocGroup.neverUpdated;
  }

  if (_sameDay(doc.updatedAt, now)) {
    return AllDocGroup.today;
  }

  final days = _daysBetween(doc.updatedAt, now);
  if (days >= 1 && days < 7) {
    return AllDocGroup.thisWeek;
  }

  return AllDocGroup.earlier;
}

/// 分组展示标签。
String labelForGroup(AllDocGroup group) {
  switch (group) {
    case AllDocGroup.today:
      return '今天';
    case AllDocGroup.thisWeek:
      return '本周';
    case AllDocGroup.earlier:
      return '更早';
    case AllDocGroup.neverUpdated:
      return '从未更新';
  }
}

/// 分组排序权重（越小越靠前）。
int orderOfGroup(AllDocGroup group) {
  switch (group) {
    case AllDocGroup.today:
      return 0;
    case AllDocGroup.thisWeek:
      return 1;
    case AllDocGroup.earlier:
      return 2;
    case AllDocGroup.neverUpdated:
      return 3;
  }
}

// ---- 内部工具 ----

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
