import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/presentation/note_editor_page.dart';

void main() {
  group('NoteEditorPage 渲染', () {
    testWidgets('初始渲染包含一个可编辑的文本块', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 应有一个 TextField
      expect(find.byType(TextField), findsOneWidget);
      // 工具栏应显示块类型按钮
      expect(find.byType(InkWell), findsWidgets);
    });

    testWidgets('AppBar 标题为块式笔记', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('块式笔记'), findsOneWidget);
    });
  });

  group('NoteEditorPage Enter 分块', () {
    testWidgets('在块中输入文本后按 Enter 应分成两个块', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 输入文本
      await tester.enterText(find.byType(TextField), 'Hello World');
      await tester.pumpAndSettle();

      // 将光标移到中间
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      controller.selection = const TextSelection.collapsed(offset: 5);

      // 模拟 Enter 键
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // 应有两个 TextField
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });

  group('NoteEditorPage Backspace 空块合并', () {
    testWidgets('在空块上按 Backspace 应删除该块', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 先分块：输入文本后按 Enter
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // 现在有两个块
      expect(find.byType(TextField), findsNWidgets(2));

      // 聚焦第二个块（空块）
      await tester.tap(find.byType(TextField).at(1));
      await tester.pumpAndSettle();

      // 在空块上按 Backspace
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      // 应合并回一个块
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('NoteEditorPage 工具栏切换块类型', () {
    testWidgets('点击工具栏按钮应切换块类型', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 聚焦第一个块
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // 找到工具栏中的 heading 按钮（通过 tooltip）
      final headingButton = find.byTooltip('标题');
      expect(headingButton, findsOneWidget);

      await tester.tap(headingButton);
      await tester.pumpAndSettle();

      // 切换后 TextField 应仍然存在
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('NoteEditorPage 块类型前缀', () {
    testWidgets('bullet 块应显示 • 前缀', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 切换到 bullet 类型
      await tester.tap(find.byTooltip('无序列表'));
      await tester.pumpAndSettle();

      // 应显示 bullet 符号
      expect(find.text('•'), findsOneWidget);
    });

    testWidgets('todo 块应显示复选框图标', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 切换到 todo 类型
      await tester.tap(find.byTooltip('待办'));
      await tester.pumpAndSettle();

      // 应显示复选框图标
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    });

    testWidgets('divider 块应显示分隔线而非 TextField', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 切换到 divider 类型
      await tester.tap(find.byTooltip('分隔线'));
      await tester.pumpAndSettle();

      // divider 块不显示 TextField，显示 Divider（工具栏分隔线 + 块分隔线）
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Divider), findsAtLeastNWidgets(1));
    });
  });
}
