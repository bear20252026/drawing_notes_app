import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter/material.dart';
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
    final notebook = Notebook(id: 'tool_test_nb', title: '测试本')
      ..pages.add(page);
    await tester.pumpWidget(MaterialApp(
      home: EditorPage(
        notebook: notebook,
        page: page,
        storage: NotebookStorage(
          directoryProvider: () async => throw UnimplementedError(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 页面不应崩溃。
    expect(tester.takeException(), isNull, reason: '编辑器页面不应有构建异常');
  }

  /// 通过 tooltip 找到对应 IconButton 并读取 isSelected。
  bool isToolSelected(WidgetTester tester, String tooltip) {
    final btn = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ).first,
    );
    return btn.isSelected ?? false;
  }

  testWidgets('工具栏可用：点击"橡皮擦"后橡皮擦进入选中态、画笔退出', (tester) async {
    await pumpEditor(tester);

    expect(find.byTooltip('橡皮擦（透明擦除）'), findsOneWidget);
    expect(find.byTooltip('画笔'), findsOneWidget);

    // 初始：画笔选中。
    expect(isToolSelected(tester, '画笔'), isTrue, reason: '初始应为画笔工具');
    expect(isToolSelected(tester, '橡皮擦（透明擦除）'), isFalse);

    // 点击橡皮擦。
    await tester.tap(find.byTooltip('橡皮擦（透明擦除）'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '点击橡皮擦不应抛异常');
    expect(isToolSelected(tester, '橡皮擦（透明擦除）'), isTrue,
        reason: '点击后橡皮擦应进入选中态');
    expect(isToolSelected(tester, '画笔'), isFalse);
  });

  testWidgets('工具栏可用：点击"画笔"后画笔重新选中', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('橡皮擦（透明擦除）'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('画笔'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(isToolSelected(tester, '画笔'), isTrue);
    expect(isToolSelected(tester, '橡皮擦（透明擦除）'), isFalse);
  });

  testWidgets('工具栏可用：点击"吸管取色"进入取色态，可切回画笔', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('吸管取色'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '吸管按钮不应抛异常');
    expect(isToolSelected(tester, '吸管取色'), isTrue);

    await tester.tap(find.byTooltip('画笔'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('工具栏可用：点击"矩形选区"后选区工具切换', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('矩形选区'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(isToolSelected(tester, '矩形选区'), isTrue,
        reason: '点击后矩形选区应进入选中态');
  });

  testWidgets('工具栏可用：点击"文字工具"进入文字模式、可切回画笔', (tester) async {
    await pumpEditor(tester);

    // 文字工具按钮（笔记本模式工具栏内）。
    final textBtn = find.byTooltip('文字工具：点击画布直接输入文字');
    expect(textBtn, findsOneWidget, reason: '笔记本模式应有文字工具按钮');
    await tester.tap(textBtn);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '点击文字工具不应抛异常');

    // 切回画笔，验证工具栏仍可交互。
    await tester.tap(find.byTooltip('画笔'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(isToolSelected(tester, '画笔'), isTrue);
  });

  testWidgets('工具栏可用：图片工具按钮存在且可点击', (tester) async {
    await pumpEditor(tester);

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
