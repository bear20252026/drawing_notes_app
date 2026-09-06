// 分页画布「打开白纸」光栅化回归（2026-09-07）。
//
// 根因：CanvasPainter 对非无限画布只画图层位图（image==null 直接跳过
// 该层），而此前打开已含笔画的文档时无人触发首次光栅化——所有层位图
// 为 null，既有内容整页不可见（用户症状「只有一张白纸」另一半根因；
// 另一半是连线层吞指针，见 paged_canvas_pointer_repro_test.dart）。
//
// 修复：LayerRenderCacheCoordinator 构造即触发 rebuildAll（非无限画布），
// 且 CanvasPainter 在位图未就绪时走矢量回退。本测试断言打开已含笔画的
// 文档后位图确实物化。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_page_editor_session.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

Stroke _stroke(double dx) => Stroke(
  points: [StrokePoint(100, 100, 1), StrokePoint(dx, 300, 1)],
  color: const Color(0xFF000000),
  width: 4,
  type: BrushType.pen,
);

void main() {
  testWidgets('打开已含笔画的分页画布：图层位图应被光栅化（否则白纸）', (
    tester,
  ) async {
    final doc = DrawingDocument(
      id: 'doc-existing',
      title: '画布',
      width: 2480,
      height: 3508,
    );
    // 预置笔画 = 模拟从磁盘加载的既有内容。
    doc.layers.first.strokes.addAll(
      [for (var i = 0; i < 3; i++) _stroke(200.0 + i * 50)],
    );
    final page = NotebookPage(id: 'page-x', title: '既有页', document: doc);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EditorPage(session: NotebookPageEditorSession(page)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // 首次光栅化

    final ctx = tester.element(find.byType(EditorPage));
    final controller = ProviderScope.containerOf(
      ctx,
    ).read(drawingControllerProvider(doc));
    expect(
      controller.paintViews.where((v) => v.image != null).length,
      greaterThan(0),
      reason: '打开既有内容页面应光栅化出图层位图；image==null 时 painter '
          '跳过该层 = 用户看到白纸',
    );
  });

  testWidgets('无限画布不产生离屏位图（矢量路径不受 rebuildAll 影响）', (
    tester,
  ) async {
    final doc = DrawingDocument(
      id: 'doc-infinite',
      title: '画板',
      infinite: true,
    );
    doc.layers.first.strokes.addAll([_stroke(300)]);
    final page = NotebookPage(id: 'page-inf', title: '画板页', document: doc);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EditorPage(session: NotebookPageEditorSession(page)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final ctx = tester.element(find.byType(EditorPage));
    final controller = ProviderScope.containerOf(
      ctx,
    ).read(drawingControllerProvider(doc));
    // 切后台→回前台（此前 rebuildAll 缺无限守卫，会把每层光栅化成
    // painter 永远不用的位图，~24MB/层纯浪费）。
    await controller.rebuildLayerBitmaps();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      controller.paintViews.every((v) => v.image == null),
      isTrue,
      reason: '无限画布走矢量渲染，rebuildAll 不应光栅化出任何位图',
    );
  });

  testWidgets('空图层不持有位图（全透明位图 ~24MB 纯浪费）', (tester) async {
    final doc = DrawingDocument(
      id: 'doc-empty-layer',
      title: '画布',
      width: 2480,
      height: 3508,
    );
    // 两层：一层有笔画、一层全空。
    doc.layers.first.strokes.add(_stroke(250));
    final page = NotebookPage(id: 'page-empty', title: '空层页', document: doc);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EditorPage(session: NotebookPageEditorSession(page)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final ctx = tester.element(find.byType(EditorPage));
    final controller = ProviderScope.containerOf(
      ctx,
    ).read(drawingControllerProvider(doc));
    expect(
      controller.paintViews.where((v) => v.image != null).length,
      1,
      reason: '仅含笔画的那一层应有位图；空层不应光栅化出全透明位图',
    );
  });
}
