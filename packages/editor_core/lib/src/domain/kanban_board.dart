// editor_core——KanbanBoard 看板视图（AFFiNE 多视图数据库借鉴——2026-08-21）。
//
// AFFiNE database view（表格/Kanban/Airtable）本地化——Kanban 看板视图。
// 基于 TableV2 扩展——每列是一组卡片（按状态分组——Todo/Doing/Done）。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
library;

/// 看板卡片（不可变——AFFiNE Kanban 借鉴）。
class KanbanCard {
  const KanbanCard({
    required this.id,
    required this.title,
    this.description = '',
    this.color = '#FFFFFF',
  });

  final String id;
  final String title;
  final String description;
  final String color;

  KanbanCard copyWith({String? title, String? description, String? color}) {
    return KanbanCard(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      color: color ?? this.color,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KanbanCard && id == other.id && title == other.title;

  @override
  int get hashCode => Object.hash(id, title);
}

/// 看板列（不可变——一组卡片——Todo/Doing/Done 等状态列）。
class KanbanColumn {
  const KanbanColumn({
    required this.id,
    required this.title,
    this.cards = const [],
  });

  final String id;
  final String title;
  final List<KanbanCard> cards;

  KanbanColumn copyWith({String? title, List<KanbanCard>? cards}) {
    return KanbanColumn(
      id: id,
      title: title ?? this.title,
      cards: cards ?? this.cards,
    );
  }

  /// 添加卡片。
  KanbanColumn addCard(KanbanCard card) =>
      KanbanColumn(id: id, title: title, cards: [...cards, card]);

  /// 移除卡片。
  KanbanColumn removeCard(String cardId) =>
      KanbanColumn(id: id, title: title, cards: cards.where((c) => c.id != cardId).toList());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KanbanColumn && id == other.id && title == other.title && _listEquals(cards, other.cards);

  @override
  int get hashCode => Object.hash(id, title, cards);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 看板视图（AFFiNE Kanban 多视图数据库借鉴——不可变）。
///
/// 基于 TableV2 扩展——每列是一组卡片（按状态分组）。
/// 与 TableV2（表格视图）是同一数据的不同视图。
class KanbanBoard {
  const KanbanBoard({
    required this.id,
    required this.title,
    this.columns = const [],
  });

  final String id;
  final String title;
  final List<KanbanColumn> columns;

  KanbanBoard copyWith({String? title, List<KanbanColumn>? columns}) {
    return KanbanBoard(
      id: id,
      title: title ?? this.title,
      columns: columns ?? this.columns,
    );
  }

  /// 添加列。
  KanbanBoard addColumn(KanbanColumn column) =>
      KanbanBoard(id: id, title: title, columns: [...columns, column]);

  /// 移除列。
  KanbanBoard removeColumn(String columnId) =>
      KanbanBoard(id: id, title: title, columns: columns.where((c) => c.id != columnId).toList());

  /// 更新列。
  KanbanBoard updateColumn(KanbanColumn column) => KanbanBoard(
        id: id,
        title: title,
        columns: columns.map((c) => c.id == column.id ? column : c).toList(),
      );

  /// 移动卡片（跨列）。
  KanbanBoard moveCard(String cardId, String fromColumnId, String toColumnId, {int? toIndex}) {
    // 从源列移除。
    final fromCol = columns.firstWhere((c) => c.id == fromColumnId);
    final card = fromCol.cards.firstWhere((c) => c.id == cardId);
    final updatedFrom = fromCol.removeCard(cardId);

    // 添加到目标列。
    final toCol = columns.firstWhere((c) => c.id == toColumnId);
    final cards = List<KanbanCard>.from(toCol.cards);
    if (toIndex != null && toIndex >= 0 && toIndex <= cards.length) {
      cards.insert(toIndex, card);
    } else {
      cards.add(card);
    }
    final updatedTo = toCol.copyWith(cards: cards);

    // 更新两列。
    return KanbanBoard(
      id: id,
      title: title,
      columns: columns.map((c) {
        if (c.id == fromColumnId) return updatedFrom;
        if (c.id == toColumnId) return updatedTo;
        return c;
      }).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KanbanBoard && id == other.id && title == other.title && _listEquals(columns, other.columns);

  @override
  int get hashCode => Object.hash(id, title, columns);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
