import 'package:drawing_notes_app/features/drawing/application/command_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandRegistry', () {
    test(
      'only exposes and executes commands available in the current context',
      () {
        var canEdit = false;
        var executions = 0;
        final registry = CommandRegistry()
          ..register(
            EditorCommand(
              id: 'delete',
              label: '删除选中对象',
              keywords: const ['remove', 'delete'],
              isAvailable: () => canEdit,
              run: () => executions++,
            ),
          )
          ..register(
            const EditorCommand(
              id: 'fit',
              label: '适应画布',
              category: EditorCommandCategory.view,
              keywords: ['zoom', 'fit'],
            ),
          );

        expect(registry.availableCommands.map((item) => item.id), ['fit']);
        expect(registry.run('delete'), isFalse);
        expect(executions, 0);

        canEdit = true;
        expect(registry.search('remove').map((item) => item.id), ['delete']);
        expect(registry.run('delete'), isTrue);
        expect(executions, 1);
      },
    );

    test('overwriting a command preserves a stable command order', () {
      final registry = CommandRegistry()
        ..register(const EditorCommand(id: 'undo', label: '撤销'))
        ..register(const EditorCommand(id: 'redo', label: '重做'))
        ..register(
          const EditorCommand(
            id: 'undo',
            label: '撤销上一步',
            shortcut: 'Ctrl/Cmd+Z',
          ),
        );

      expect(registry.commands.map((item) => item.id), ['undo', 'redo']);
      expect(registry.find('undo')?.label, '撤销上一步');
      expect(registry.find('undo')?.shortcut, 'Ctrl/Cmd+Z');
    });

    test(
      'search includes labels categories and keywords without hidden commands',
      () {
        final registry = CommandRegistry()
          ..register(
            const EditorCommand(
              id: 'png',
              label: '导出 PNG',
              category: EditorCommandCategory.export,
              keywords: ['image', 'export'],
            ),
          )
          ..register(
            EditorCommand(
              id: 'hidden',
              label: '仅选中时显示',
              isAvailable: () => false,
            ),
          );

        expect(registry.search('export').map((item) => item.id), ['png']);
        expect(registry.search('导出').map((item) => item.id), ['png']);
        expect(registry.search('编辑'), isEmpty);
      },
    );
  });
}
