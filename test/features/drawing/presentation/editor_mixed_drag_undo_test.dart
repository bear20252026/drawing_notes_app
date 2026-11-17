// 拖拽撤销专项（2026-11-17）：真手势链路 → Ctrl+Z 的端到端回归。
//
// 事务语义单测在 mixed_object_drag_recorder_test.dart；本文件钉的是
// **overlay 手势真的接上了事务**：笔记模式形状移动/旋转/缩放、文字移动、
// 图表移动（死手势修复）、独立模式单图片指针拖拽（pointerUp 缺口修复）。
//
// 装配照抄 editor_object_delete_undo_test / editor_text_width_handle_test：
// ProviderScope > MaterialApp(locale:zh) > EditorPage；视口钉 scale=1。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_selection_geometry.dart';
import 'package:drawing_notes_app/features/drawing/presentation/resize_handles.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_page_editor_session.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpSession(WidgetTester tester, NotebookPage page) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        home: EditorPage(session: NotebookPageEditorSession(page)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> pumpDoc(WidgetTester tester, DrawingDocument doc) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        home: EditorPage(document: doc),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 视口钉成 scale=1 / offset=0（选中之后做，照宽度柄测试口径）。
Future<void> pinView(WidgetTester tester, DrawingDocument doc) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(EditorPage)),
    listen: false,
  );
  final controller = container.read(drawingControllerProvider(doc));
  controller.viewScale = 1;
  controller.viewOffset = Offset.zero;
  controller.tickFrame();
  await tester.pump();
}

Future<void> ctrlZ(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> ctrlY(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Finder overlay(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && (w.properties.label?.contains(label) ?? false),
  skipOffstage: false,
);

/// 选中对象（tap overlay）并钉视口。
Future<void> selectAndPin(
  WidgetTester tester,
  String label,
  DrawingDocument doc,
) async {
  await tester.tap(overlay(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await pinView(tester, doc);
}

/// 拖拽：第一次 moveBy 喂过 kPanSlop（手势被 pan 收纳，该次增量不派发），
/// 第二次 moveBy 才是真实增量（与宽度柄测试「前两次只用于收纳」同口径，
/// 但那是针对已聚焦手柄；overlay GestureDetector 首次 move 即收纳）。
Future<void> dragBy(WidgetTester tester, Finder target, Offset delta) async {
  final gesture = await tester.startGesture(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveBy(const Offset(40, 40)); // 喂 slop，不产生对象位移
  await tester.pump();
  await gesture.moveBy(delta); // 真实增量
  await tester.pump();
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 300));
}

NotebookPage pageWith({
  List<PageTextItem>? texts,
  List<PageImageItem>? images,
  List<PageShapeItem>? shapes,
  List<PageChartItem>? charts,
}) {
  final doc = DrawingDocument(
    id: 'drag_page',
    title: '拖拽撤销',
    width: 2480,
    height: 3508,
  );
  return NotebookPage(
    id: 'p1',
    title: '页',
    document: doc,
    textItems: texts,
    imageItems: images,
    shapes: shapes,
    charts: charts,
  );
}

void main() {
  testWidgets('笔记形状移动 → Ctrl+Z 回到起点，Ctrl+Y 再到终点', (tester) async {
    final shape = PageShapeItem(
      id: 's1',
      shapeType: ShapeType.rect,
      x: 300,
      y: 300,
      width: 120,
      height: 80,
    );
    final page = pageWith(shapes: [shape]);
    await pumpSession(tester, page);
    await selectAndPin(tester, '画布对象：形状', page.document);

    final before = Offset(shape.x, shape.y);
    await dragBy(tester, overlay('画布对象：形状'), const Offset(60, 40));
    expect(shape.x, before.dx + 60, reason: '前置：拖拽确实移动了形状');
    expect(shape.y, before.dy + 40);

    await ctrlZ(tester);
    expect(shape.x, before.dx, reason: '移动必须撤得回（整域缺口修复）');
    expect(shape.y, before.dy);

    await ctrlY(tester);
    expect(shape.x, before.dx + 60);
    expect(shape.y, before.dy + 40);
  });

  testWidgets('笔记形状旋转 → Ctrl+Z 角度还原', (tester) async {
    final shape = PageShapeItem(
      id: 's1',
      shapeType: ShapeType.rect,
      x: 300,
      y: 300,
      width: 120,
      height: 80,
    );
    final page = pageWith(shapes: [shape]);
    await pumpSession(tester, page);
    await selectAndPin(tester, '画布对象：形状', page.document);

    final handle = overlay('旋转手柄');
    expect(handle, findsOneWidget, reason: '选中非线性形状必须有旋转手柄');
    // 旋转手柄在形状 overlay 的 Stack 内，真指针手势被父级移动
    // recognizer 竞争截走（探针实测）；照 resize_handles_test 先例
    // 直调回调钉「旋转事务真的接上了」。localPosition 是手柄内坐标。
    final gd = tester.widget<GestureDetector>(
      find.descendant(of: handle, matching: find.byType(GestureDetector)),
    );
    gd.onPanStart!(DragStartDetails(globalPosition: Offset.zero));
    gd.onPanUpdate!(DragUpdateDetails(
      globalPosition: const Offset(102, 82),
      localPosition: const Offset(102, 82),
      delta: const Offset(80, 60),
    ));
    await tester.pump();
    expect(shape.rotation, isNot(0), reason: '前置：旋转确实改了角度');
    final rotated = shape.rotation;
    gd.onPanEnd!(DragEndDetails());
    await tester.pump(const Duration(milliseconds: 300));

    await ctrlZ(tester);
    expect(shape.rotation, 0, reason: '旋转必须撤得回');
    await ctrlY(tester);
    expect(shape.rotation, closeTo(rotated, 0.0001));
  });

  testWidgets('笔记形状缩放手柄 → Ctrl+Z 尺寸还原', (tester) async {
    final shape = PageShapeItem(
      id: 's1',
      shapeType: ShapeType.rect,
      x: 300,
      y: 300,
      width: 120,
      height: 80,
    );
    final page = pageWith(shapes: [shape]);
    await pumpSession(tester, page);
    await selectAndPin(tester, '画布对象：形状', page.document);

    // 缩放手柄同在 overlay Stack 内（指针竞争同旋转）；直调
    // ResizeHandles 组件回调钉事务接线（照 resize_handles_test 先例）。
    final rh = tester.widget<ResizeHandles>(find.byType(ResizeHandles));
    final beforeW = shape.width;
    final beforeH = shape.height;
    rh.onDragStart?.call();
    rh.onResize(EditorShapeResizeHandle.bottomRight, const Offset(30, 25));
    rh.onChanged();
    await tester.pump();
    expect(shape.width, isNot(beforeW), reason: '前置：缩放确实改了尺寸');
    rh.onDragEnd?.call();
    await tester.pump(const Duration(milliseconds: 300));

    await ctrlZ(tester);
    expect(shape.width, beforeW, reason: '缩放必须撤得回');
    expect(shape.height, beforeH);
  });

  testWidgets('笔记文字移动 → Ctrl+Z 回到起点', (tester) async {
    final text = PageTextItem(id: 't1', x: 300, y: 300, text: '拖我');
    final page = pageWith(texts: [text]);
    await pumpSession(tester, page);
    await selectAndPin(tester, '画布对象：文字', page.document);

    await dragBy(tester, overlay('画布对象：文字'), const Offset(50, 30));
    expect(text.x, isNot(300), reason: '前置：文字确实移动了');
    final movedX = text.x;

    await ctrlZ(tester);
    expect(text.x, 300, reason: '文字移动必须撤得回');
    expect(text.y, 300);
    await ctrlY(tester);
    expect(text.x, movedX);
  });

  testWidgets('笔记图表移动（死手势修复）→ 动得了且撤得回', (tester) async {
    final chart = PageChartItem(
      id: 'c1',
      chartType: ChartType.bar,
      data: const [1, 2, 3],
      x: 300,
      y: 300,
    );
    final page = pageWith(charts: [chart]);
    await pumpSession(tester, page);
    await selectAndPin(tester, '画布对象：图表', page.document);

    await dragBy(tester, overlay('画布对象：图表'), const Offset(45, 25));
    expect(chart.x, 345, reason: '图表此前是死手势（回调空转），现在必须动');
    expect(chart.y, 325);

    await ctrlZ(tester);
    expect(chart.x, 300);
    expect(chart.y, 300);
  });

  testWidgets('笔记图片移动 → Ctrl+Z 回到起点', (tester) async {
    final image = PageImageItem(id: 'i1', x: 300, y: 300, filePath: '');
    final page = pageWith(images: [image]);
    await pumpSession(tester, page);
    await selectAndPin(tester, '画布对象：图片', page.document);

    await dragBy(tester, overlay('画布对象：图片'), const Offset(35, 45));
    expect(image.x, 335);
    expect(image.y, 345);

    await ctrlZ(tester);
    expect(image.x, 300);
    expect(image.y, 300);
  });

  testWidgets('空拖拽（按下即抬起）不产生撤销条目', (tester) async {
    final shape = PageShapeItem(
      id: 's1',
      shapeType: ShapeType.rect,
      x: 300,
      y: 300,
      width: 120,
      height: 80,
    );
    final page = pageWith(shapes: [shape]);
    await pumpSession(tester, page);
    await selectAndPin(tester, '画布对象：形状', page.document);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorPage)),
      listen: false,
    );
    final controller = container.read(drawingControllerProvider(page.document));
    final entriesBefore = controller.historyService.entryCount;

    // 按下即抬起（无增量）：不产生历史条目。
    final gesture = await tester.startGesture(
      tester.getCenter(overlay('画布对象：形状')),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      controller.historyService.entryCount,
      entriesBefore,
      reason: '空拖拽进栈 = 用户按一次 Ctrl+Z 白吃掉一步真操作',
    );
  });

  testWidgets('独立模式单图片指针拖拽（pointerUp 缺口）→ 撤得回', (tester) async {
    final doc = DrawingDocument(
      id: 'img_drag',
      title: '图片拖拽',
      infinite: true,
      imageItems: [
        DocumentImageItem(
          id: 'img1',
          x: 300,
          y: 300,
          width: 200,
          height: 150,
          filePath: '',
        ),
      ],
    );
    await pumpDoc(tester, doc);

    // 切到矩形选区工具（独立模式对象拖拽的前提）。注意「框选多个元素」
    // 是 marquee（笔记混排框选），独立模式对象命中走的是「矩形选区 (R)」。
    await tester.tap(find.byTooltip('矩形选区 (R)'));
    await tester.pump();
    await pinView(tester, doc);

    // 真指针链路在测试窗口下被 overlay 截走（探针实测 selectedImage 恒
    // null）；改走 controller 会话 API 钉结算缺口修复：
    // endDocumentImageTransform 正是 pointerUp 新补分支调的方法，
    // 会话级「move→end→undo」闭环即该分支的机器事实。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorPage)),
      listen: false,
    );
    final controller = container.read(drawingControllerProvider(doc));
    controller.selectDocumentImageAt(const Offset(350, 350));
    controller.moveSelectedDocumentImage(const Offset(40, 30));
    controller.endDocumentImageTransform();

    final image = doc.imageItems.single;
    expect(image.x, 340, reason: '前置：独立模式图片确实拖动了');
    expect(image.y, 330);
    expect(controller.canUndo, isTrue, reason: '结算必须入栈（缺口修复）');

    controller.undo();
    expect(image.x, 300, reason: 'pointerUp 结算缺口修复后必须撤得回');
    expect(image.y, 300);
  });
}