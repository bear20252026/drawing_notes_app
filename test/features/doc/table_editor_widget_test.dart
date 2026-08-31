import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/presentation/table_editor_widget.dart';

void main() {
  group('TableEditorWidget', () {
    NoteBlock makeTableBlock({
      int rows = 2,
      int cols = 2,
      List<String>? cellTexts,
    }) {
      final children = <NoteBlock>[];
      final texts = cellTexts ?? List<String>.filled(rows * cols, '');
      for (int i = 0; i < texts.length; i++) {
        children.add(NoteBlock.textBlock('cell_$i', text: texts[i]));
      }
      return NoteBlock(
        id: 'table_1',
        type: NoteBlockType.table,
        props: {'rows': rows, 'cols': cols},
        children: children,
      );
    }

    testWidgets('渲染表格编辑器', (tester) async {
      final block = makeTableBlock(
        rows: 2,
        cols: 2,
        cellTexts: ['a', 'b', 'c', 'd'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableEditorWidget(
              block: block,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 应显示表格维度
      expect(find.text('表格 2×2'), findsOneWidget);
      // 应显示单元格文本
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);
      expect(find.text('d'), findsOneWidget);
    });

    testWidgets('添加行按钮触发 onChanged', (tester) async {
      final block = makeTableBlock(rows: 2, cols: 2);

      NoteBlock? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableEditorWidget(
              block: block,
              onChanged: (b) => saved = b,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 找到"添加行"按钮（tooltip 匹配）
      final addRowBtn = find.byTooltip('添加行');
      expect(addRowBtn, findsOneWidget);
      await tester.tap(addRowBtn);
      await tester.pumpAndSettle();

      // onChanged 应被调用
      expect(saved, isNotNull);
      expect(saved!.props['rows'] as int?, 3);
    });

    testWidgets('删除行按钮减少行数', (tester) async {
      final block = makeTableBlock(rows: 3, cols: 2);

      NoteBlock? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableEditorWidget(
              block: block,
              onChanged: (b) => saved = b,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final delRowBtn = find.byTooltip('删除行');
      expect(delRowBtn, findsOneWidget);
      await tester.tap(delRowBtn);
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.props['rows'] as int?, 2);
    });

    testWidgets('添加列按钮增加列数', (tester) async {
      final block = makeTableBlock(rows: 2, cols: 3);

      NoteBlock? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableEditorWidget(
              block: block,
              onChanged: (b) => saved = b,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final addColBtn = find.byTooltip('添加列');
      expect(addColBtn, findsOneWidget);
      await tester.tap(addColBtn);
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.props['cols'] as int?, 4);
    });
  });
}
