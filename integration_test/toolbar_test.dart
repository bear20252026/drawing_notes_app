import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_page_editor_session.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用户视角核心回归：工具栏所有工具必须可用（画笔/橡皮擦/吸管/选区）。
///
/// 这是用户报告的"工具栏里一个都用不了"的重现测试：
/// 真实构建编辑器 → 依次点击各工具按钮 → 断言按钮选中态（isSelected）
/// 实际切换，证明 onPressed 生效、页面没有崩溃。
void main() {
  Future<void> pumpEditor(WidgetTester tester) async {
    final doc = DrawingDocument(
      id: 'tool_test_doc',
      title: '工具测试',
      width: 1000,
      height: 1400,
    );
    final page = NotebookPage(
      id: 'tool_test_pg',
      title: '工具测试页',
      document: doc,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: EditorPage(
            session: NotebookPageEditorSession(page),
            storage: NotebookStorage(
              directoryProvider: () async => throw UnimplementedError(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 页面不应崩溃。
    expect(tester.takeException(), isNull, reason: '编辑器页面不应有构建异常');
  }

  /// 通过 tooltip 找到对应工具按钮并判断是否处于选中态。
  ///
  /// 选中编码 = `Tooltip(child: Container(decoration:
  /// BoxDecoration(color: AppleColor.actionBlue), child: IconButton(...)))`，
  /// 未选中时 Tooltip 直接挂 IconButton
  /// （editor_left_toolbar.dart:221-238）。原先读 `IconButton.isSelected`，
  /// 但 `_tool` 从不传该参数（恒 null→`?? false`），`isTrue` 断言其实没有
  /// 过裁决力——现改读真正的选中编码（仍是「工具是否被选中」同一命题）。
  bool isToolSelected(WidgetTester tester, String tooltip) {
    final child = tester.widget<Tooltip>(find.byTooltip(tooltip)).child;
    if (child is! Container) return false;
    final decoration = child.decoration;
    return decoration is BoxDecoration &&
        decoration.color == AppleColor.actionBlue;
  }

  testWidgets('工具栏可用：点击"橡皮擦"后橡皮擦进入选中态、画笔退出', (tester) async {
    await pumpEditor(tester);

    expect(find.byTooltip('橡皮擦 (E)'), findsOneWidget);
    expect(find.byTooltip('画笔 (P)'), findsOneWidget);

    // 初始：画笔选中。
    expect(isToolSelected(tester, '画笔 (P)'), isTrue, reason: '初始应为画笔工具');
    expect(isToolSelected(tester, '橡皮擦 (E)'), isFalse);

    // 点击橡皮擦。
    await tester.tap(find.byTooltip('橡皮擦 (E)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '点击橡皮擦不应抛异常');
    expect(isToolSelected(tester, '橡皮擦 (E)'), isTrue, reason: '点击后橡皮擦应进入选中态');
    expect(isToolSelected(tester, '画笔 (P)'), isFalse);
  });

  testWidgets('工具栏可用：点击"画笔"后画笔重新选中', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('橡皮擦 (E)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('画笔 (P)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(isToolSelected(tester, '画笔 (P)'), isTrue);
    expect(isToolSelected(tester, '橡皮擦 (E)'), isFalse);
  });

  testWidgets('工具栏可用：点击"吸管取色"进入取色态，可切回画笔', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('吸管工具'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '吸管按钮不应抛异常');
    expect(isToolSelected(tester, '吸管工具'), isTrue);

    await tester.tap(find.byTooltip('画笔 (P)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('工具栏可用：点击"矩形选区"后选区工具切换', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('矩形选区 (R)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(isToolSelected(tester, '矩形选区 (R)'), isTrue, reason: '点击后矩形选区应进入选中态');
  });

  testWidgets('工具栏可用：点击"文字工具"进入文字模式、可切回画笔', (tester) async {
    await pumpEditor(tester);

    // 文字工具按钮（EditorLeftToolbar；字面量 '文字 (T)'
    // editor_left_toolbar.dart:150，非 arb——旧横栏的长文案已删）。
    final textBtn = find.byTooltip('文字 (T)');
    expect(textBtn, findsOneWidget, reason: '工具栏应有文字工具按钮');
    await tester.tap(textBtn);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '点击文字工具不应抛异常');

    // 切回画笔，验证工具栏仍可交互。
    await tester.tap(find.byTooltip('画笔 (P)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(isToolSelected(tester, '画笔 (P)'), isTrue);
  });

  testWidgets('工具栏可用：图片工具按钮存在且可点击', (tester) async {
    await pumpEditor(tester);

    // 无法文案修复——该入口已不存在：'插入图片' tooltip 来自旧横栏
    // editor_toolbar.dart:162（随 247f3b1 整文件删除）。现 `_insertImage`
    // （editor_page_editing.dart:247）只被赋给 EditorToolbarActions.insertImage
    // （editor_page_toolbar_actions.dart:83），全 lib 无读取方 → 编辑器无图片
    // 按钮。本用例真机必红，属产品缺口（AGENTS.md §7 删入口需同意），交宿主
    // 裁决「补入口」还是「授权改用例」，不在文案修复范围内擅改。
    final imgBtn = find.byTooltip('插入图片');
    expect(imgBtn, findsOneWidget, reason: '工具栏应有插入图片按钮');
    // 点击触发文件选择器（测试环境会取消），不应抛异常。
    await tester.tap(imgBtn);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '点击图片工具不应抛异常');
  });

  testWidgets('画布可用：点击画布开始绘制不崩溃', (tester) async {
    await pumpEditor(tester);

    final canvas = find.byType(CustomPaint).first;
    await tester.tapAt(tester.getCenter(canvas));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '画布交互不应抛异常');
  });
}
