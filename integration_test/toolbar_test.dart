import 'dart:io';

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

import '../test/helpers/temp_dir_cleanup.dart';

/// 用户视角核心回归：工具栏所有工具必须可用（画笔/橡皮擦/吸管/选区）。
///
/// 这是用户报告的"工具栏里一个都用不了"的重现测试：
/// 真实构建编辑器 → 依次点击各工具按钮 → 断言按钮选中态（isSelected）
/// 实际切换，证明 onPressed 生效、页面没有崩溃。
void main() {
  Future<void> pumpEditor(WidgetTester tester) async {
    // 与 feature_test.dart 同一条修正（AW6）：目录注入原先是
    // `throw UnimplementedError()`，任何真走到存储层的动作都会当场炸，
    // 等于「改动会不会触发保存」这条腿在本文件里根本不存在。
    final tempDir = await Directory.systemTemp.createTemp('toolbar_test_');
    addTearDown(() => deleteTempDirWithRetry(tempDir));
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
              directoryProvider: () async => tempDir,
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
  /// 选中编码有**两份**，本函数要求两份同时成立：
  /// ① 视觉：这一工具的子树里存在 `Container(decoration:
  ///    BoxDecoration(color: AppleColor.actionBlue))`——用户看得到的那块蓝底
  ///    （`editor_left_toolbar.dart` 的 `_tool`）；
  /// ② 语义：包住它的那个 `Semantics(selected: true)`——P1-9 为读屏用户加的同一命题。
  ///
  /// 遍历**不假定嵌套深度**。上一版按「公开 Tooltip 的**直接子节点**是不是
  /// `Container`」判；2026-10-09 给工具按钮补触觉时在 `Tooltip` 与蓝底之间插了一层
  /// `GestureDetector`（外面还多一层 `Semantics`），于是真机上 5 条用例从
  /// 「初始应为画笔工具」这一步就当场红——而 CI 从不跑 `integration_test`，
  /// 红了五天没人看见（本文件一度是这条编码**唯一**的守卫，`test/` 里没有第二个
  /// 用例读它）。教训：断言要钉「同一命题的语义」，不能钉实现的中转层数。
  ///
  /// 保留的历史坑（AU 2026-10-05）：`find.byTooltip` 命中的是框架**内部**的
  /// `RawTooltip`，不是公开的 `Tooltip`；`tester.widget<Tooltip>(find.byTooltip(...))`
  /// 是运行时强转，真机上必抛 `_TypeError`——`flutter analyze` 抓不到（静态类型是
  /// Widget，强转在运行时才判）。所以下面一律走 `find.ancestor` + 显式判空。
  bool isToolSelected(WidgetTester tester, String tooltip) {
    final marked = find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.selected == true,
      ),
    );
    if (marked.evaluate().isEmpty) return false;
    // 蓝底必须落在**这一个工具**的子树里，不能是别的工具留下的。
    return find
        .descendant(
          of: marked,
          matching: find.byWidgetPredicate((w) {
            if (w is! Container) return false;
            final d = w.decoration;
            return d is BoxDecoration && d.color == AppleColor.actionBlue;
          }),
        )
        .evaluate()
        .isNotEmpty;
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

    // AR-1（审计 2026-10-05）入口已补回：'插入图片' tooltip 原来自旧横栏
    // editor_toolbar.dart:162（随 247f3b1 整文件删除），此后 `_insertImage`
    // 只被赋给 EditorToolbarActions.insertImage、全 lib 无读取方 → 本用例
    // 真机必红。现按动作项挂在左工具条末端
    // （editor_left_toolbar.dart `_tool(Icons.image_outlined, edInsertImage)`，
    // 经 editor_page_body.dart 的 `onInsertImage: _insertImage` 接线），
    // 文案走新 arb 键 edInsertImage（zh「插入图片」/ en "Insert image"）。
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
