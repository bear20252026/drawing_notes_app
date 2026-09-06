// 回归测试：画板就地编辑期间快捷键不得劫持按键。
//
// 根因（2026-09-01）：editor_page_shortcuts 的 _onShortcutKey 原先
// 不判断「正在文字输入中」，数字键 1-9 被工具切换吞掉（打不进文本框、
// 中文输入法选字被劫持），编辑已有文字块时退格触发删除选区把正在
// 编辑的块删掉。修复：就地编辑聚焦时所有单键快捷键直接放行
// （对齐 Excalidraw 的 isEditingText 提前返回）。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_left_toolbar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 进入文字工具 + 点击画布进入就地编辑。
  ///
  /// 审计三-1（2026-09-06）：工具条改为画布内浮动玻璃岛（短画布上岛内
  /// 可滚动），先滚到「文字 (T)」可见再点击。
  Future<void> startInlineEditing(WidgetTester tester) async {
    final textTool = find.byTooltip('文字 (T)');
    await tester.ensureVisible(textTool);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(textTool);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(420, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  String currentText(WidgetTester tester) {
    final tf = tester.widget<TextField>(find.byType(TextField).first);
    return tf.controller?.text ?? '';
  }

  testWidgets('就地编辑聚焦时：数字键快捷键被闸门放行，不切换工具', (tester) async {
    final document = DrawingDocument(id: 'p1', title: '探针');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditorPage(document: document)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await startInlineEditing(tester);

    await tester.enterText(find.byType(TextField).first, 'ab');
    await tester.pump();
    expect(currentText(tester), 'ab');

    // 物理按 6（快捷键=矩形形状工具）：修复前会真的切到形状工具
    // （工具栏 activeShape=rect），修复后按键被放行给输入框
    // （测试环境不产生字符），工具状态不变。
    await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // 输入框仍在、内容未被按键破坏。
    expect(find.byType(TextField), findsOneWidget);
    expect(currentText(tester), 'ab');
    // 工具栏状态：形状工具未被激活（修复前为 ShapeType.rect）。
    final toolbar = tester.widget<EditorLeftToolbar>(
      find.byType(EditorLeftToolbar),
    );
    expect(toolbar.activeShape, isNull);

    // 提交文字。
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(document.textItems.map((t) => t.text), contains('ab'));

    // 提交后快捷键恢复：焦点交还键盘监听节点（真机上提交后点击画布
    // 即回到该节点），再按 6 应正常切到形状工具。
    tester
        .widget<KeyboardListener>(find.byType(KeyboardListener))
        .focusNode
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final toolbarAfter = tester.widget<EditorLeftToolbar>(
      find.byType(EditorLeftToolbar),
    );
    expect(toolbarAfter.activeShape, ShapeType.rect);
  });

  testWidgets('就地编辑聚焦时：退格删除字符而不删除选中元素', (tester) async {
    final document = DrawingDocument(id: 'p2', title: '探针');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditorPage(document: document)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await startInlineEditing(tester);

    await tester.enterText(find.byType(TextField).first, 'ab');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // 修复前：若该块处于选中态会触发 deleteSelection 整块删除；
    // 修复后：正常删除一个字符。
    expect(currentText(tester), 'a');
  });

  testWidgets('提交文字后：数字键快捷键恢复正常工作', (tester) async {
    final document = DrawingDocument(id: 'p3', title: '探针');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditorPage(document: document)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await startInlineEditing(tester);

    await tester.enterText(find.byType(TextField).first, '你好');
    await tester.pump();
    // 回车（done 动作）提交就地编辑。
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(document.textItems.map((t) => t.text), contains('你好'));

    // 提交后快捷键恢复：按 1 应切换回画笔工具而不是输入字符
    // （就地编辑框已消失，无 TextField 可接收输入）。
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(TextField), findsNothing);
  });
}
