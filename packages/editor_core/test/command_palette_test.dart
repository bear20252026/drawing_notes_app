import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——CommandPalette 命令面板测试（纯逻辑——不搞崩）。
void main() {
  test('CommandEntry：matches 模糊搜索', () {
    const entry = CommandEntry(
      id: 'undo', label: 'Undo', action: 'undo',
      shortcut: 'Ctrl+Z', category: 'Edit', keywords: ['撤销', '回退'],
    );
    expect(entry.matches('undo'), true);
    expect(entry.matches('Undo'), true);
    expect(entry.matches('edit'), true); // category 匹配。
    expect(entry.matches('撤销'), true); // keyword 匹配。
    expect(entry.matches('xyz'), false);
    expect(entry.matches(''), true); // 空查询返回全部。
  });

  test('CommandEntry：hasShortcut', () {
    const withShortcut = CommandEntry(id: 'c1', label: 'C1', action: 'a1', shortcut: 'Ctrl+S');
    const without = CommandEntry(id: 'c2', label: 'C2', action: 'a2');
    expect(withShortcut.hasShortcut, true);
    expect(without.hasShortcut, false);
  });

  test('CommandPalette：add/remove/get', () {
    const palette = CommandPalette();
    final withCmd = palette.add(const CommandEntry(id: 'undo', label: 'Undo', action: 'undo'));
    expect(withCmd.count, 1);
    expect(withCmd.get('undo')!.label, 'Undo');
    final removed = withCmd.remove('undo');
    expect(removed.count, 0);
    expect(removed.get('undo'), isNull);
  });

  test('CommandPalette：getByShortcut（快捷键查找）', () {
    final palette = const CommandPalette().add(
      const CommandEntry(id: 'undo', label: 'Undo', action: 'undo', shortcut: 'Ctrl+Z'),
    ).add(
      const CommandEntry(id: 'redo', label: 'Redo', action: 'redo', shortcut: 'Ctrl+Y'),
    );
    expect(palette.getByShortcut('Ctrl+Z')!.id, 'undo');
    expect(palette.getByShortcut('Ctrl+Y')!.id, 'redo');
    expect(palette.getByShortcut('Ctrl+S'), isNull);
  });

  test('CommandPalette：search 模糊搜索', () {
    final palette = const CommandPalette().add(
      const CommandEntry(id: 'undo', label: 'Undo', action: 'undo', category: 'Edit'),
    ).add(
      const CommandEntry(id: 'export', label: 'Export', action: 'export', category: 'File'),
    );
    expect(palette.search('undo').length, 1);
    expect(palette.search('edit').length, 1);
    expect(palette.search('').length, 2);
  });

  test('CommandPalette：byCategory / sortedByPriority', () {
    final palette = const CommandPalette().add(
      const CommandEntry(id: 'c1', label: 'C1', action: 'a1', category: 'Edit', priority: CommandPriority.high),
    ).add(
      const CommandEntry(id: 'c2', label: 'C2', action: 'a2', category: 'File', priority: CommandPriority.low),
    ).add(
      const CommandEntry(id: 'c3', label: 'C3', action: 'a3', category: 'Edit'),
    );
    expect(palette.byCategory('Edit').length, 2);
    final sorted = palette.sortedByPriority();
    expect(sorted.first.priority, CommandPriority.high);
    expect(sorted.last.priority, CommandPriority.low);
  });

  test('CommandPriority 枚举', () {
    expect(CommandPriority.values.length, 3);
  });
}
