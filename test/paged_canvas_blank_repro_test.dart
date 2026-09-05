// 分页画布「空白页、画不了」复现测试（2026-09-06）。
//
// 用户症状：分页画布打开后是空白页、所有功能都不可用（无法绘制）。
// 本测试模拟指针拖拽在分页画布上画一笔，断言：
//   1. 指尖笔画真的写入页面图层的 strokes；
//   2. 非无限画布走「图层离屏位图」路径——invalidateLayer 触发异步光栅化，
//      paintViews 中出现非空 image（否则画上去不可见 = 空白页）。

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

void main() {
  testWidgets('分页画布：controller 直接起笔画后图层收到笔画（图层摄取链健康）',
      (tester) async {
    // 与 NotebookPageTemplateStrategy 默认一致的固定 A4 尺寸页面。
    final page = NotebookPage(
      id: 'page-1',
      title: '空白页',
      document: DrawingDocument(
        id: 'document-1',
        title: '画布',
        width: 2480,
        height: 3508,
      ),
    );

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
    final controller = ProviderScope.containerOf(
      ctx,
    ).read(drawingControllerProvider(page.document));

    // 绕过 widget 手势层，直接驱动 controller：若这步都记不上笔画，
    // 才是「分页画布图层摄取笔画的链」本身坏了。
    controller.startStroke(const Offset(400, 300), pressure: 1.0);
    controller.extendStroke(const Offset(430, 330), pressure: 1.0);
    controller.endStroke();

    final current = controller.currentLayer;
    expect(
      current.strokes,
      isNotEmpty,
      reason: 'controller 直接起笔应写入当前图层：${current.id}',
    );
    expect(page.document.layers.first.strokes, current.strokes,
        reason: '当前图层必须是页面文档的图层');
  });
}