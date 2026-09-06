// 回归：分页画布「指针落点 = 墨迹落点」一致性锁定（2026-09-07）。
//
// 用户报告画布上指针位置与笔画出现位置有偏移。排查后确认 Dart 层坐标链
// 自洽：指针 e.localPosition（画布表面局部坐标）→ viewToCanvas → 文档坐标
// 写入笔画 → CanvasPainter 同一变换画回。本测试验证：在画布表面上某局部
// 位置落笔，记录的文档坐标经 canvasToView 反投影回视图后，应正好等于该
// 局部位置（即墨迹画在指针下面）。
// 若此测试绿，说明偏移不来自 Dart 逻辑，而来自显示/DPI/原生层。

import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/canvas_painter.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_page_editor_session.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

void main() {
  testWidgets('墨迹出现在指针位置：canvasToView(落笔文档坐标) == 指针局部位置', (tester) async {
    final doc = DrawingDocument(
      id: 'doc-off',
      title: '画布',
      width: 2480,
      height: 3508,
    );
    final page = NotebookPage(id: 'page-off', title: '页', document: doc);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EditorPage(session: NotebookPageEditorSession(page)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final ctx = tester.element(find.byType(EditorPage));
    final controller = ProviderScope.containerOf(
      ctx,
    ).read(drawingControllerProvider(doc));

    // 带平移 + 缩放的视口，确保测试覆盖变换（不只是在恒等变换下）。
    controller.viewScale = 1.35;
    controller.viewOffset = const Offset(120, -80);
    controller.viewRotation = 0;
    controller.tickFrame();
    await tester.pump(const Duration(milliseconds: 16));

    // 画布表面（CanvasPainter 所属 CustomPaint）的全局左上角 = 局部坐标原点。
    final surfaceFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is CanvasPainter,
    );
    expect(surfaceFinder, findsOneWidget);
    final surfaceTopLeft = tester.getTopLeft(surfaceFinder);

    // 在画布表面上选一个局部位置落笔。
    final local = const Offset(430, 310);
    final global = surfaceTopLeft + local;

    final gesture = await tester.startGesture(
      global,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(Offset.zero);
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    final stroke = controller.currentLayer.strokes.firstOrNull;
    expect(stroke, isNotNull, reason: '应有落笔');
    final p0 = stroke!.points.first;
    final recorded = Offset(p0.x, p0.y);

    // 关键不变式：落笔的文档坐标反投影回视图，应回到指针的那个局部位置。
    final projected = controller.canvasToView(recorded);
    final diff = (projected - local).distance;
    // scale 1.35：1 个视图像素 ≈ 0.74 文档像素，落笔往返有少量舍入。
    expect(
      diff,
      lessThan(1.5),
      reason:
          '墨迹应渲染在指针下面：projected=$projected local=$local '
          'diff=$diff（scale=${controller.viewScale}）',
    );
  });
}
