import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/documents/note_block.dart';
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
            body: TableEditorWidget(block: block, onChanged: (_) {}),
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
            body: TableEditorWidget(block: block, onChanged: (b) => saved = b),
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
            body: TableEditorWidget(block: block, onChanged: (b) => saved = b),
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
            body: TableEditorWidget(block: block, onChanged: (b) => saved = b),
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

  // FDC-02：读侧 clamp 与写侧增删现在共用 `note_block.dart` 的同一对常量。
  // 这里只盯 UI 侧的两件事：①边界处按钮是**禁用态**（不是「能点但没反应」），
  // ②越界点击**连变更都不发**——`_emitChange` 会给每个格子换一批新 id 的
  // children，「点了没反应却把文档标脏」是同一类缺陷的另一半。
  group('TableEditorWidget 行列上限', () {
    NoteBlock table({
      required int rows,
      required int cols,
      required List<String> texts,
    }) {
      final children = <NoteBlock>[
        for (int i = 0; i < texts.length; i++)
          NoteBlock.textBlock('cell_$i', text: texts[i]),
      ];
      return NoteBlock(
        id: 'table_1',
        type: NoteBlockType.table,
        props: {'rows': rows, 'cols': cols},
        children: children,
      );
    }

    // 50 行的表格在默认 800×600 测试视口里会纵向溢出（编辑器只在横向包了
    // SingleChildScrollView）——用例只关心按钮与格子落点，把画布拉高即可。
    void useTallSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> mount(
      WidgetTester tester,
      NoteBlock block,
      ValueChanged<NoteBlock> onChanged, {
      String key = 't',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableEditorWidget(
              key: ValueKey(key),
              block: block,
              onChanged: onChanged,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    IconButton btn(WidgetTester tester, String tip) =>
        tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(tip),
            matching: find.byType(IconButton),
          ),
        );

    testWidgets('列到上限后「添加列」是禁用态，且点击不发任何变更', (tester) async {
      useTallSurface(tester);
      final cols = kNoteTableMaxCols;
      NoteBlock? saved;
      await mount(
        tester,
        table(rows: 1, cols: cols, texts: List.generate(cols, (i) => 'c$i')),
        (b) => saved = b,
      );

      expect(
        btn(tester, '添加列').onPressed,
        isNull,
        reason: '上限处必须是禁用态——「能点但什么也不做」骗人',
      );
      await tester.tap(find.byTooltip('添加列'));
      await tester.pumpAndSettle();
      expect(
        saved,
        isNull,
        reason: '越界点击必须连一次 onChanged 都不发：发了就重建 children、置脏、落盘',
      );
      // 反面对照：未到达的边界仍可用，防止「全部禁用」这种假绿。
      expect(btn(tester, '删除列').onPressed, isNotNull);
    });

    testWidgets('行到上限后「添加行」是禁用态，且点击不发任何变更', (tester) async {
      useTallSurface(tester);
      const rows = kNoteTableMaxRows;
      NoteBlock? saved;
      await mount(
        tester,
        table(rows: rows, cols: 1, texts: List.generate(rows, (i) => 'r$i')),
        (b) => saved = b,
      );

      expect(find.text('表格 $rows×1'), findsOneWidget);
      expect(btn(tester, '添加行').onPressed, isNull);
      await tester.tap(find.byTooltip('添加行'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(btn(tester, '删除行').onPressed, isNotNull);
    });

    testWidgets('只剩 1 行/1 列时删除按钮禁用（此前是可点但空响）', (tester) async {
      useTallSurface(tester);
      NoteBlock? saved;
      await mount(
        tester,
        table(rows: 1, cols: 1, texts: const ['x']),
        (b) => saved = b,
      );

      expect(btn(tester, '删除行').onPressed, isNull);
      expect(btn(tester, '删除列').onPressed, isNull);
      await tester.tap(find.byTooltip('删除行'));
      await tester.tap(find.byTooltip('删除列'));
      await tester.pumpAndSettle();
      expect(saved, isNull, reason: '下限处的两次点击都不该产生变更');
    });

    testWidgets('连点 12 次「添加列」后落盘不越界，重开后内容不整体错一格', (tester) async {
      useTallSurface(tester);
      NoteBlock? saved;
      await mount(
        tester,
        table(rows: 2, cols: 2, texts: const ['a', 'b', 'c', 'd']),
        (b) => saved = b,
      );

      for (int i = 0; i < 12; i++) {
        await tester.tap(find.byTooltip('添加列'));
        await tester.pumpAndSettle();
      }

      expect(saved, isNotNull);
      expect(
        saved!.props['cols'] as int?,
        kNoteTableMaxCols,
        reason: '写侧若不认这条线会落盘 cols=14（2+12），读侧按 10 重排即错位',
      );
      final rows = saved!.props['rows'] as int?;
      expect(saved!.children.length, rows! * kNoteTableMaxCols);

      // 重开（新 State 从 props 读回）——这才是「存进去的东西回得来」的判据。
      NoteBlock? reopenSaved;
      await mount(tester, saved!, (b) => reopenSaved = b, key: 'reopen');
      expect(find.text('表格 2×$kNoteTableMaxCols'), findsOneWidget);
      final a = tester.getTopLeft(find.widgetWithText(TextField, 'a'));
      final c = tester.getTopLeft(find.widgetWithText(TextField, 'c'));
      expect(
        c.dx,
        closeTo(a.dx, 1),
        reason: '第二行首格必须仍在第 0 列；右移一格就是行主序数组被另一种宽度重排了',
      );
      expect(c.dy, greaterThan(a.dy));
      expect(reopenSaved, isNull, reason: '仅重开不该产生变更');
    });

    testWidgets('遗留越界文档（cols=11）按上限打开，且「添加行」不再制造新错位', (tester) async {
      useTallSurface(tester);
      // 老版本写侧无上限时留下的文档：props 说 11 列，children 22 格。
      NoteBlock? saved;
      await mount(
        tester,
        table(rows: 2, cols: 11, texts: List.generate(22, (i) => 't$i')),
        (b) => saved = b,
      );

      expect(find.text('表格 2×$kNoteTableMaxCols'), findsOneWidget);
      await tester.tap(find.byTooltip('添加行'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.props['cols'] as int?, kNoteTableMaxCols);
      // 可见区仍是「每行 10 格、行主序」：t0 在第 0 列，t10（原第 11 格）
      // 落在第二行第 0 列——遗留的越界格子不会被这次操作挪进可见区。
      final t0 = tester.getTopLeft(find.widgetWithText(TextField, 't0'));
      final t10 = tester.getTopLeft(find.widgetWithText(TextField, 't10'));
      expect(t10.dx, closeTo(t0.dx, 1));
    });
  });
}
