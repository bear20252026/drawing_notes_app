// 分页画布「白纸无法作画」真实指针回归（2026-09-07）。
//
// 根因：连线层 ConnectorPainter 是裸 CustomPaint（CustomPainter.hitTest
// 默认返回 true），分页模式下这层 Positioned.fill 盖住整块画布吞掉全部
// 指针事件（独立画布无此层故正常）。既有测试直驱 controller 绕过了
// 手势层，所以一直绿——本测试必须用真实指针事件走完整命中链。
//
// 覆盖：鼠标 / 触屏 / 触控笔三种输入在分页画布模式各落一笔。

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_page_editor_session.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

Future<DrawingController> pumpEditor(WidgetTester tester, String id) async {
  final doc = DrawingDocument(
    id: id,
    title: '画布',
    width: 2480,
    height: 3508,
  );
  final page = NotebookPage(id: 'page-$id', title: '空白页', document: doc);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: EditorPage(session: NotebookPageEditorSession(page)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200)); // 首次视口适配
  final ctx = tester.element(find.byType(EditorPage));
  return ProviderScope.containerOf(ctx).read(drawingControllerProvider(doc));
}

Future<void> drawStroke(WidgetTester tester, PointerDeviceKind kind) async {
  final gesture = await tester.startGesture(const Offset(400, 300), kind: kind);
  await gesture.moveBy(const Offset(30, 30));
  await gesture.moveBy(const Offset(30, 20));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  for (final kind in [
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
  ]) {
    testWidgets('分页画布：真实${kind.name}指针事件经手势层落笔', (tester) async {
      final controller = await pumpEditor(tester, 'doc-${kind.name}');
      final before = controller.currentLayer.strokes.length;
      await drawStroke(tester, kind);
      expect(
        controller.currentLayer.strokes.length,
        greaterThan(before),
        reason: '${kind.name} 指针在分页画布上应能画出笔画（若失败=画布被'
            '上层裸 CustomPaint 吞掉命中，回归「白纸无法作画」）',
      );
    });
  }
}
