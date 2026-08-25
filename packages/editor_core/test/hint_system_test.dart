import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——HintSystem 提示帮助系统测试（纯逻辑——不搞崩）。
void main() {
  test('Hint：默认值 + hasShortcut + isForTool', () {
    const hint = Hint(id: 'h1', message: 'Press Delete to remove', shortcut: 'Delete', tool: 'select');
    expect(hint.hasShortcut, true);
    expect(hint.isForTool('select'), true);
    expect(hint.isForTool('draw'), false); // 指定工具时不匹配其他工具。
    expect(hint.priority, 0);
    expect(hint.duration, 0);

    const general = Hint(id: 'h2', message: 'Click to select', tool: '');
    expect(general.isForTool('select'), true); // 空工具匹配所有。
    expect(general.isForTool('draw'), true);
  });

  test('Hint：copyWith 不可变', () {
    const hint = Hint(id: 'h1', message: 'Click');
    final updated = hint.copyWith(message: 'Double click', priority: 10);
    expect(hint.message, 'Click'); // 原实例不变。
    expect(updated.message, 'Double click');
    expect(updated.priority, 10);
  });

  test('HintSystem：add/remove', () {
    const system = HintSystem();
    final withHint = system.add(const Hint(id: 'h1', message: 'Press Delete'));
    expect(withHint.count, 1);
    final removed = withHint.remove('h1');
    expect(removed.count, 0);
  });

  test('HintSystem：hintsForTool（按工具过滤）', () {
    final system = HintSystem().add(
      const Hint(id: 'h1', message: 'Drag to draw', tool: 'draw'),
    ).add(
      const Hint(id: 'h2', message: 'Click to select', tool: 'select'),
    ).add(
      const Hint(id: 'h3', message: 'Press Esc to cancel', tool: ''), // 通用。
    );
    expect(system.hintsForTool('draw').length, 2); // h1 + h3（通用）。
    expect(system.hintsForTool('select').length, 2); // h2 + h3（通用）。
    expect(system.hintsForTool('unknown').length, 1); // 只有 h3（通用）。
  });

  test('HintSystem：hintsByType（按类型过滤）', () {
    final system = HintSystem().add(
      const Hint(id: 'h1', message: 'Click', type: HintType.tooltip),
    ).add(
      const Hint(id: 'h2', message: 'Ctrl+Z', type: HintType.shortcut),
    ).add(
      const Hint(id: 'h3', message: 'Drag', type: HintType.context),
    );
    expect(system.hintsByType(HintType.tooltip).length, 1);
    expect(system.hintsByType(HintType.shortcut).length, 1);
    expect(system.hintsByType(HintType.context).length, 1);
  });

  test('HintSystem：sortedByPriority（优先级排序）', () {
    final system = HintSystem().add(
      const Hint(id: 'h1', message: 'Low', priority: 1),
    ).add(
      const Hint(id: 'h2', message: 'High', priority: 10),
    ).add(
      const Hint(id: 'h3', message: 'Medium', priority: 5),
    );
    final sorted = system.sortedByPriority();
    expect(sorted.first.message, 'High');
    expect(sorted.last.message, 'Low');
  });

  test('HintSystem：helpPanel（带快捷键的提示）', () {
    final system = HintSystem().add(
      const Hint(id: 'h1', message: 'Undo', shortcut: 'Ctrl+Z'),
    ).add(
      const Hint(id: 'h2', message: 'Click'), // 无快捷键。
    );
    expect(system.helpPanel().length, 1);
    expect(system.helpPanel().first.shortcut, 'Ctrl+Z');
  });

  test('HintSystem：search（模糊搜索）', () {
    final system = HintSystem().add(
      const Hint(id: 'h1', message: 'Press Delete to remove element'),
    ).add(
      const Hint(id: 'h2', message: 'Drag to draw'),
    );
    expect(system.search('delete').length, 1);
    expect(system.search('draw').length, 1);
    expect(system.search('').length, 2);
  });

  test('HintType 枚举', () {
    expect(HintType.values.length, 4);
  });
}
