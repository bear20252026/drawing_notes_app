// 由 Claude 团队生成 | Drawing Notes App
// block_slash_menu.dart 单元测试。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/presentation/block_slash_menu.dart';

void main() {
  group('BlockSlashMenu', () {
    test('options 包含所有常用块类型', () {
      final types = BlockSlashMenu.options.map((o) => o.type).toSet();
      expect(types.contains(NoteBlockType.text), isTrue);
      expect(types.contains(NoteBlockType.heading), isTrue);
      expect(types.contains(NoteBlockType.todo), isTrue);
      expect(types.contains(NoteBlockType.bullet), isTrue);
      expect(types.contains(NoteBlockType.ordered), isTrue);
      expect(types.contains(NoteBlockType.quote), isTrue);
      expect(types.contains(NoteBlockType.code), isTrue);
      expect(types.contains(NoteBlockType.divider), isTrue);
      expect(types.contains(NoteBlockType.callout), isTrue);
      expect(types.contains(NoteBlockType.table), isTrue);
    });

    test('每个 option 都有 label 和 icon', () {
      for (final option in BlockSlashMenu.options) {
        expect(option.label, isNotEmpty);
        expect(option.icon, isNotNull);
      }
    });

    testWidgets('菜单渲染并显示选项', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BlockSlashMenu(
            onSelected: (_) {},
            onDismiss: () {},
          ),
        ),
      ));

      // 验证至少显示了"段落"选项
      expect(find.text('段落'), findsOneWidget);
      expect(find.text('待办事项'), findsOneWidget);
    });

    testWidgets('点击选项触发 onSelected', (tester) async {
      NoteBlockType? selected;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BlockSlashMenu(
            onSelected: (type) => selected = type,
            onDismiss: () {},
          ),
        ),
      ));

      await tester.tap(find.text('段落'));
      await tester.pump();

      expect(selected, NoteBlockType.text);
    });
  });
}
