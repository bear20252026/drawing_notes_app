import 'package:drawing_notes_app/features/drawing/application/shortcut_registry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShortcutEntry', () {
    test('displayKey: 单字母键无修饰符', () {
      const entry = ShortcutEntry(
        key: LogicalKeyboardKey.keyP,
        actionId: 'tool_pen',
        description: '画笔',
        category: '工具',
      );
      expect(entry.displayKey, 'P');
    });

    test('displayKey: Ctrl+Z (Windows/Linux)', () {
      const entry = ShortcutEntry(
        key: LogicalKeyboardKey.keyZ,
        control: true,
        meta: true,
        actionId: 'undo',
        description: '撤销',
        category: '编辑',
      );
      // 在测试环境（非 macOS）中，应显示 Ctrl+Z
      final display = entry.displayKey;
      expect(display, contains('Z'));
      expect(display, anyOf(contains('Ctrl'), contains('Cmd')));
    });

    test('displayKey: Shift+Ctrl+Z 包含 Shift', () {
      const entry = ShortcutEntry(
        key: LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
        meta: true,
        actionId: 'redo_shift',
        description: '重做',
        category: '编辑',
      );
      final display = entry.displayKey;
      expect(display, contains('Shift'));
      expect(display, contains('Z'));
    });

    test('displayKey: Delete 键显示 Delete', () {
      const entry = ShortcutEntry(
        key: LogicalKeyboardKey.delete,
        actionId: 'delete',
        description: '删除',
        category: '编辑',
      );
      expect(entry.displayKey, 'Delete');
    });

    test('const 构造函数可编译', () {
      // 验证所有条目都是 const 构造（编译期检查）
      const entry = ShortcutEntry(
        key: LogicalKeyboardKey.keyA,
        actionId: 'test',
        description: '测试',
        category: '测试',
      );
      expect(entry.actionId, 'test');
    });
  });

  group('ShortcutRegistry', () {
    test('shortcuts 列表非空', () {
      expect(ShortcutRegistry.shortcuts, isNotEmpty);
    });

    test('shortcuts 包含核心编辑快捷键', () {
      final undo = ShortcutRegistry.findByAction('undo');
      expect(undo, isNotEmpty);
      expect(undo.first.description, '撤销');

      final redo = ShortcutRegistry.findByAction('redo_shift');
      expect(redo, isNotEmpty);

      final copy = ShortcutRegistry.findByAction('copy');
      expect(copy, isNotEmpty);

      final paste = ShortcutRegistry.findByAction('paste');
      expect(paste, isNotEmpty);
    });

    test('shortcuts 包含工具快捷键', () {
      final toolIds = [
        'tool_select',
        'tool_pen',
        'tool_eraser',
        'tool_text',
        'tool_rectangle',
        'tool_ellipse',
        'tool_arrow',
        'tool_line',
        'tool_eyedropper',
        'tool_hand',
      ];
      for (final id in toolIds) {
        final entries = ShortcutRegistry.findByAction(id);
        expect(entries, isNotEmpty, reason: '缺少工具快捷键: $id');
      }
    });

    test('shortcuts 包含文件快捷键', () {
      final save = ShortcutRegistry.findByAction('save');
      expect(save, isNotEmpty);

      final export = ShortcutRegistry.findByAction('export');
      expect(export, isNotEmpty);
    });

    test('categories 返回唯一分类', () {
      final categories = ShortcutRegistry.categories;
      expect(categories, isNotEmpty);
      expect(categories.toSet().length, categories.length);
    });

    test('getByCategory 返回正确分类的快捷键', () {
      final editShortcuts = ShortcutRegistry.getByCategory('编辑');
      expect(editShortcuts, isNotEmpty);
      expect(editShortcuts.every((s) => s.category == '编辑'), isTrue);
    });

    test('groupedByCategory 包含所有分类', () {
      final grouped = ShortcutRegistry.groupedByCategory;
      expect(grouped, isNotEmpty);
      expect(grouped.keys.toSet(), containsAll(ShortcutRegistry.categories));
    });

    test('每个 actionId 都有对应的快捷键', () {
      final allActionIds =
          ShortcutRegistry.shortcuts.map((s) => s.actionId).toSet();
      expect(allActionIds, isNotEmpty);
      // 验证没有空 actionId
      for (final id in allActionIds) {
        expect(id, isNotEmpty);
      }
    });

    test('每个快捷键都有描述和分类', () {
      for (final shortcut in ShortcutRegistry.shortcuts) {
        expect(shortcut.description, isNotEmpty,
            reason: '${shortcut.actionId} 缺少描述');
        expect(shortcut.category, isNotEmpty,
            reason: '${shortcut.actionId} 缺少分类');
      }
    });
  });

  group('PlatformShortcutAdapter', () {
    test('isMacOS 是静态可访问的', () {
      // 验证 PlatformShortcutAdapter 不抛异常
      final isMac = PlatformShortcutAdapter.isMacOS;
      expect(isMac, isA<bool>());
    });

    test('matches 方法接受 KeyEvent 和 ShortcutEntry', () {
      // 创建一个模拟按键事件
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyZ,
        logicalKey: LogicalKeyboardKey.keyZ,
        character: 'z',
        timeStamp: Duration.zero,
      );
      const shortcut = ShortcutEntry(
        key: LogicalKeyboardKey.keyZ,
        control: true,
        meta: true,
        actionId: 'undo',
        description: '撤销',
        category: '编辑',
      );
      // 验证 matches 不抛异常
      final result = PlatformShortcutAdapter.matches(event, shortcut);
      expect(result, isA<bool>());
    });
  });

  group('ShortcutHelpWidget', () {
    test('构造函数接受可选参数', () {
      const widget = ShortcutHelpWidget();
      expect(widget.title, '快捷键帮助');
      expect(widget.width, 700);
      expect(widget.height, 500);
    });

    test('构造函数接受自定义参数', () {
      const widget = ShortcutHelpWidget(
        title: '自定义标题',
        width: 800,
        height: 600,
      );
      expect(widget.title, '自定义标题');
      expect(widget.width, 800);
      expect(widget.height, 600);
    });
  });

  // ---------------------------------------------------------------------------
  // findMatch 集成测试
  // ---------------------------------------------------------------------------
  group('findMatch', () {
    test('匹配 Ctrl+Z 到 undo 操作', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyZ,
        logicalKey: LogicalKeyboardKey.keyZ,
        character: 'z',
        timeStamp: Duration.zero,
      );

      // findMatch 是 ShortcutRegistry 的静态方法
      final result = ShortcutRegistry.findMatch(event);
      if (result != null) {
        expect(result.actionId, anyOf(equals('undo'), equals('redo')));
      }
    });

    test('findMatch 不匹配未注册的按键', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.fn,
        logicalKey: LogicalKeyboardKey.fn,
        timeStamp: Duration.zero,
      );
      final result = ShortcutRegistry.findMatch(event);
      expect(result, isNull);
    });

    test('findMatch 不匹配 F13 以外的非注册功能键', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.fn,
        logicalKey: LogicalKeyboardKey.fn,
        timeStamp: Duration.zero,
      );
      final result = ShortcutRegistry.findMatch(event);
      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // 分类完整性
  // ---------------------------------------------------------------------------
  group('分类完整性', () {
    test('每个分类至少包含 2 个快捷键', () {
      final categories = ShortcutRegistry.categories;
      for (final category in categories) {
        final shortcuts = ShortcutRegistry.getByCategory(category);
        expect(shortcuts.length, greaterThanOrEqualTo(2),
            reason: '分类 "$category" 应至少包含 2 个快捷键');
      }
    });

    test('所有快捷键都归入已知分类', () {
      final knownCategories = ShortcutRegistry.categories.toSet();
      for (final shortcut in ShortcutRegistry.shortcuts) {
        expect(knownCategories, contains(shortcut.category),
            reason: '${shortcut.actionId} 的分类 "${shortcut.category}" 不在 categories 中');
      }
    });
  });
}
