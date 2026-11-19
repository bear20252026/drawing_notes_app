// P2 架构收口（2026-11-18）：笔记模式笔画平移专属路由回归（三轮 M-3）。
//
// M-9 守卫堵死 input 拖拽分支后，笔记套索笔画无任何平移路径（选区栏无
// 平移控件、_nudgeSelected 只动混排对象）。本组钉：
// ① 笔记模式选区栏渲染四向微调按钮，点按平移笔画且单条撤销；
// ② 独立模式不渲染按钮组（走指针拖拽，防双路由）；
// ③ 微调走 selectionSession 窄命令事务，不进 MixedDragSession（不双记）。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/drawing/presentation/selection_bar.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_page_editor_session.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke strokeAt(double y) => Stroke(
  points: <StrokePoint>[StrokePoint(10, y, 1), StrokePoint(60, y, 1)],
  color: const Color(0xFF111111),
  width: 2,
  type: BrushType.pen,
);

DrawingDocument docWithStroke() => DrawingDocument(
  id: 'nudge-doc',
  title: '笔画微调',
  width: 400,
  height: 400,
  layers: <Layer>[
    Layer(id: 'l1', name: '图层 1', strokes: <Stroke>[strokeAt(20)]),
  ],
);

Future<DrawingController> pumpLassoSelected(
  WidgetTester tester,
  DrawingDocument doc, {
  bool notebookMode = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: notebookMode
            ? EditorPage(
                session: NotebookPageEditorSession(
                  NotebookPage(id: 'p1', title: '页', document: doc),
                ),
              )
            : EditorPage(document: doc),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  final bar = tester.widget<SelectionBar>(find.byType(SelectionBar));
  final controller = bar.controller;
  // 套索选中笔画（矩形框选不满足 hasSelection 多边形条件，条子不渲染）。
  controller.selectionTool = SelectionTool.lasso;
  controller.beginSelection(const Offset(5, 0));
  controller.extendSelection(const Offset(80, 0));
  controller.extendSelection(const Offset(80, 40));
  controller.extendSelection(const Offset(5, 40));
  controller.endSelection();
  await tester.pumpAndSettle();
  expect(controller.hasSelectedStrokes, isTrue);
  return controller;
}

void main() {
  testWidgets('笔记模式：四向微调按钮渲染，点按平移+单条撤销', (tester) async {
    final doc = docWithStroke();
    final controller = await pumpLassoSelected(tester, doc);
    final before = doc.layers.first.strokes.first.points.first.offset;

    final rightBtn = find.byTooltip('右移选中笔画');
    expect(rightBtn, findsOneWidget, reason: '笔记模式笔画选中必须渲染平移按钮');
    expect(find.byTooltip('左移选中笔画'), findsOneWidget);
    expect(find.byTooltip('上移选中笔画'), findsOneWidget);
    expect(find.byTooltip('下移选中笔画'), findsOneWidget);

    await tester.tap(rightBtn);
    await tester.pumpAndSettle();
    final after = doc.layers.first.strokes.first.points.first.offset;
    expect(after.dx, before.dx + 4, reason: '点按右移 4px 画布坐标');
    expect(controller.canUndo, isTrue, reason: '每按一次成对提交一条窄命令');

    controller.undo();
    expect(
      doc.layers.first.strokes.first.points.first.offset,
      before,
      reason: '微调撤得回（M-3 修复核心）',
    );
  });

  testWidgets('连续微调 = 多条独立撤销（LIFO）', (tester) async {
    final doc = docWithStroke();
    final controller = await pumpLassoSelected(tester, doc);
    final before = doc.layers.first.strokes.first.points.first.offset;

    await tester.tap(find.byTooltip('右移选中笔画'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下移选中笔画'));
    await tester.pumpAndSettle();
    final moved = doc.layers.first.strokes.first.points.first.offset;
    expect(moved.dx, before.dx + 4);
    expect(moved.dy, before.dy + 4);

    controller.undo();
    expect(doc.layers.first.strokes.first.points.first.offset.dy, before.dy);
    expect(doc.layers.first.strokes.first.points.first.offset.dx, before.dx + 4);
    controller.undo();
    expect(doc.layers.first.strokes.first.points.first.offset, before);
  });

  testWidgets('独立模式：不渲染平移按钮组（走指针拖拽防双路由）', (tester) async {
    final doc = docWithStroke();
    await pumpLassoSelected(tester, doc, notebookMode: false);
    expect(find.byTooltip('右移选中笔画'), findsNothing);
    expect(find.byTooltip('左移选中笔画'), findsNothing);
  });

  testWidgets('微调不进混排会话：无混排历史条目（不双记）', (tester) async {
    final doc = docWithStroke();
    final controller = await pumpLassoSelected(tester, doc);
    final entriesBefore = controller.historyService.entryCount;
    await tester.tap(find.byTooltip('右移选中笔画'));
    await tester.pumpAndSettle();
    expect(
      controller.historyService.entryCount,
      entriesBefore + 1,
      reason: '一次微调恰好一条历史（窄命令），无混排事务叠加',
    );
  });
}
