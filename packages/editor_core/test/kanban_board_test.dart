import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——KanbanBoard 看板视图测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('KanbanCard：copyWith 不可变', () {
    const card = KanbanCard(id: 'c1', title: 'Task 1');
    final updated = card.copyWith(title: 'Task 1 Updated', color: '#FFCDD2');
    expect(card.title, 'Task 1'); // 原实例不变。
    expect(updated.title, 'Task 1 Updated');
    expect(updated.color, '#FFCDD2');
  });

  test('KanbanColumn：addCard/removeCard', () {
    const col = KanbanColumn(id: 'todo', title: 'Todo');
    final withCard = col.addCard(const KanbanCard(id: 'c1', title: 'Task'));
    expect(withCard.cards.length, 1);
    final removed = withCard.removeCard('c1');
    expect(removed.cards.length, 0);
  });

  test('KanbanBoard：addColumn/removeColumn/updateColumn', () {
    const board = KanbanBoard(id: 'kb1', title: 'Project');
    final withCol = board.addColumn(const KanbanColumn(id: 'todo', title: 'Todo'));
    expect(withCol.columns.length, 1);
    final removed = withCol.removeColumn('todo');
    expect(removed.columns.length, 0);
  });

  test('KanbanBoard：moveCard 跨列移动', () {
    final board = KanbanBoard(id: 'kb1', title: 'Project', columns: [
      const KanbanColumn(id: 'todo', title: 'Todo', cards: [
        KanbanCard(id: 'c1', title: 'Task 1'),
      ]),
      const KanbanColumn(id: 'doing', title: 'Doing'),
    ]);
    final moved = board.moveCard('c1', 'todo', 'doing');
    expect(moved.columns.first.cards.length, 0); // 源列清空。
    expect(moved.columns.last.cards.length, 1);  // 目标列有卡片。
    expect(moved.columns.last.cards.first.title, 'Task 1');
  });

  test('KanbanBoard：moveCard 带 toIndex（插入位置）', () {
    final board = KanbanBoard(id: 'kb1', title: 'Project', columns: [
      const KanbanColumn(id: 'todo', title: 'Todo', cards: [
        KanbanCard(id: 'c1', title: 'Task 1'),
      ]),
      const KanbanColumn(id: 'doing', title: 'Doing', cards: [
        KanbanCard(id: 'c2', title: 'Task 2'),
        KanbanCard(id: 'c3', title: 'Task 3'),
      ]),
    ]);
    final moved = board.moveCard('c1', 'todo', 'doing', toIndex: 1);
    expect(moved.columns.last.cards.length, 3);
    expect(moved.columns.last.cards[1].id, 'c1'); // 插入位置。
  });

  test('KanbanBoard：相等性', () {
    const a = KanbanBoard(id: 'kb1', title: 'Project');
    const b = KanbanBoard(id: 'kb1', title: 'Project');
    expect(a, b);
  });

  test('KanbanBoard：copyWith 不可变', () {
    const board = KanbanBoard(id: 'kb1', title: 'Project');
    final renamed = board.copyWith(title: 'New Project');
    expect(board.title, 'Project'); // 原实例不变。
    expect(renamed.title, 'New Project');
  });
}
