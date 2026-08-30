import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/note_editor_page.dart';

void main() {
  final now = DateTime(2026, 8, 28);

  NoteBlockDoc makeDoc({
    required String id,
    String title = '',
    List<NoteBlock> body = const [],
  }) =>
      NoteBlockDoc(
        id: id,
        title: title,
        body: body,
        createdAt: now,
        updatedAt: now,
      );

  group('NoteEditorPage 渲染', () {
    testWidgets('初始渲染包含一个可编辑的文本块', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 标题栏 + 空段落 = 2 个 TextField
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('标题字段位于正文顶部（AFFiNE 式）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoteEditorPage()),
      );
      await tester.pumpAndSettle();

      // 正文第一个 TextField 即标题（AppBar 不再含标题输入）。
      expect(find.widgetWithText(TextField, ''), findsWidgets);
    });
  });

  group('NoteEditorPage 文档绑定', () {
    testWidgets('接收 document 时标题显示在正文顶部', (tester) async {
      final doc = makeDoc(id: 'doc-1', title: 'My Document');

      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextField, 'My Document'),
        findsOneWidget,
      );
    });

    testWidgets('接收多块文档后显示所有块', (tester) async {
      final doc = makeDoc(
        id: 'doc-multi',
        title: 'Multi',
        body: [
          NoteBlock.textBlock('t1', text: 'Block One'),
          NoteBlock.textBlock('t2', text: 'Block Two'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // 标题栏 + 2 个内容块 = 3 个 TextField
      expect(find.byType(TextField), findsNWidgets(3));
    });
  });

  group('NoteEditorPage onSave 回调', () {
    testWidgets('dispose 时若提供 onSave 则传出 NoteBlockDoc',
        (tester) async {
      NoteBlockDoc? savedDoc;
      final doc = makeDoc(
        id: 'doc-save',
        title: 'Save Me',
        body: [NoteBlock.textBlock('t1', text: 'Content')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(
            document: doc,
            onSave: (d) => savedDoc = d,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 触发 dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(savedDoc, isNotNull);
      expect(savedDoc!.id, 'doc-save');
      expect(savedDoc!.title, 'Save Me');
      expect(savedDoc!.body.length, 1);
    });

    testWidgets('无 onSave 时 dispose 不崩溃', (tester) async {
      final doc = makeDoc(id: 'doc-nosave', title: 'No Save');

      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // 触发 dispose —— 不应抛异常
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    });
  });

  group('NoteEditorPage 块手柄拖拽', () {
    testWidgets('每个块行左侧显示拖拽手柄 (drag_handle 图标)',
        (tester) async {
      final doc = makeDoc(
        id: 'doc-handle',
        title: 'Handle',
        body: [
          NoteBlock.textBlock('t1', text: 'Block One'),
          NoteBlock.textBlock('t2', text: 'Block Two'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // 每个块行都有一个 drag_handle 图标
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    });

    testWidgets('点击拖拽手柄选中整块（聚焦）', (tester) async {
      final doc = makeDoc(
        id: 'doc-select',
        title: 'Select',
        body: [
          NoteBlock.textBlock('t1', text: 'Block One'),
          NoteBlock.textBlock('t2', text: 'Block Two'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // 找到第一个拖拽手柄并点击
      final handle = find.byIcon(Icons.drag_handle).first;
      await tester.tap(handle);
      await tester.pumpAndSettle();

      // 点击后至少有一个 EditableText 获得焦点
      final editableTexts = find.byType(EditableText);
      final hasFocus = editableTexts.evaluate().any((element) {
        final editable = element.widget as EditableText;
        return editable.focusNode.hasFocus;
      });
      expect(hasFocus, isTrue);
    });

    testWidgets('拖拽手柄将块移动到目标位置', (tester) async {
      final doc = makeDoc(
        id: 'doc-drag',
        title: 'Drag',
        body: [
          NoteBlock.textBlock('t1', text: 'First'),
          NoteBlock.textBlock('t2', text: 'Second'),
          NoteBlock.textBlock('t3', text: 'Third'),
        ],
      );

      NoteBlockDoc? savedDoc;
      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(
            document: doc,
            onSave: (d) => savedDoc = d,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 找到所有拖拽手柄
      final handles = find.byIcon(Icons.drag_handle);
      expect(handles, findsNWidgets(3));

      // 拖拽第一个块（t1）到第三个块位置
      final firstHandle = handles.at(0);
      final thirdHandle = handles.at(2);

      // 开始拖拽
      final gesture =
          await tester.startGesture(tester.getCenter(firstHandle));
      await tester.pump(const Duration(milliseconds: 100));

      // 移动到第三个块位置
      await gesture.moveTo(tester.getCenter(thirdHandle));
      await tester.pump(const Duration(milliseconds: 100));

      // 释放
      await gesture.up();
      await tester.pumpAndSettle();

      // 验证：dispose 时传出保存结果
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(savedDoc, isNotNull);
      // 拖拽后块顺序应改变：First 从位置 0 移动到位置 2 附近
      final texts = savedDoc!.body.map((b) => b.text).toList();
      // 验证仍然有 3 个块
      expect(texts.length, 3);
      // 验证 First 不再在第一位（拖拽成功改变了顺序）
      expect(texts.first != 'First' || texts.last == 'First', isTrue);
    });
  });

  group('NoteEditorPage 撤销重做与键盘导航', () {
    // 找到当前文本为 [text] 的可编辑字段（内容块），避免依赖 EditableText 顺序。
    EditableText editableOf(String text, WidgetTester tester) {
      return tester
          .widgetList<EditableText>(find.byType(EditableText))
          .firstWhere((e) => e.controller.text == text);
    }

    testWidgets('Ctrl+Z 撤销文本编辑', (tester) async {
      final doc = makeDoc(
        id: 'doc-undo',
        title: 'U',
        body: [NoteBlock.textBlock('t1', text: 'Hello')],
      );
      await tester.pumpWidget(
        MaterialApp(home: NoteEditorPage(document: doc)),
      );
      await tester.pumpAndSettle();

      final block = editableOf('Hello', tester);
      await tester.showKeyboard(find.byWidget(block));
      await tester.enterText(find.byWidget(block), 'Changed');
      await tester.pumpAndSettle();

      // Ctrl+Z 撤销
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(
        editableOf('Hello', tester).controller.text,
        'Hello',
      );
    });

    testWidgets('Ctrl+Shift+Z 重做文本编辑', (tester) async {
      final doc = makeDoc(
        id: 'doc-redo',
        title: 'R',
        body: [NoteBlock.textBlock('t1', text: 'Hello')],
      );
      await tester.pumpWidget(
        MaterialApp(home: NoteEditorPage(document: doc)),
      );
      await tester.pumpAndSettle();

      final block = editableOf('Hello', tester);
      await tester.showKeyboard(find.byWidget(block));
      await tester.enterText(find.byWidget(block), 'Changed');
      await tester.pumpAndSettle();

      // 撤销
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // 重做：Ctrl+Shift+Z
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(
        editableOf('Changed', tester).controller.text,
        'Changed',
      );
    });

    testWidgets('向下方向键导航到下一块', (tester) async {
      final doc = makeDoc(
        id: 'doc-nav',
        title: 'N',
        body: [
          NoteBlock.textBlock('t1', text: 'One'),
          NoteBlock.textBlock('t2', text: 'Two'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: NoteEditorPage(document: doc)),
      );
      await tester.pumpAndSettle();

      final first = editableOf('One', tester);
      await tester.showKeyboard(find.byWidget(first));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final second = editableOf('Two', tester);
      expect(second.focusNode.hasFocus, isTrue);
    });

    testWidgets('向上方向键导航到上一块，边界忽略', (tester) async {
      final doc = makeDoc(
        id: 'doc-nav2',
        title: 'N2',
        body: [
          NoteBlock.textBlock('t1', text: 'One'),
          NoteBlock.textBlock('t2', text: 'Two'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: NoteEditorPage(document: doc)),
      );
      await tester.pumpAndSettle();

      final first = editableOf('One', tester);
      await tester.showKeyboard(find.byWidget(first));
      await tester.pumpAndSettle();

      // 首块按上箭头 -> 边界忽略，焦点仍在首块
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(editableOf('One', tester).focusNode.hasFocus, isTrue);
    });
  });

  group('NoteEditorPage 块缩进与嵌套', () {
    EditableText editableOf(String text, WidgetTester tester) {
      return tester
          .widgetList<EditableText>(find.byType(EditableText))
          .firstWhere((e) => e.controller.text == text);
    }

    testWidgets('Tab 将块缩进到上一兄弟下（形成嵌套）', (tester) async {
      NoteBlockDoc? saved;
      final doc = makeDoc(
        id: 'doc-indent',
        title: 'I',
        body: [
          NoteBlock.textBlock('t1', text: 'One'),
          NoteBlock.textBlock('t2', text: 'Two'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(document: doc, onSave: (d) => saved = d),
        ),
      );
      await tester.pumpAndSettle();

      // 聚焦第二个块并按 Tab 缩进
      final second = editableOf('Two', tester);
      await tester.showKeyboard(find.byWidget(second));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      // 触发 dispose → onSave 快照
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.body.length, 1);
      expect(saved!.body[0].id, 't1');
      expect(saved!.body[0].children.single.id, 't2');
      expect(saved!.body[0].children.single.text, 'Two');
    });

    testWidgets('Shift+Tab 将嵌套块移出父级（取消嵌套）', (tester) async {
      NoteBlockDoc? saved;
      final doc = makeDoc(
        id: 'doc-outdent',
        title: 'O',
        body: [
          NoteBlock(
            id: 't1',
            type: NoteBlockType.text,
            text: 'One',
            children: [NoteBlock.textBlock('t2', text: 'Two')],
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(document: doc, onSave: (d) => saved = d),
        ),
      );
      await tester.pumpAndSettle();

      final nested = editableOf('Two', tester);
      await tester.showKeyboard(find.byWidget(nested));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.body.length, 2);
      expect(saved!.body[0].id, 't1');
      expect(saved!.body[1].id, 't2');
      expect(saved!.body[1].text, 'Two');
    });
  });
}
