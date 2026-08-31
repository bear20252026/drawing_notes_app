// 门禁探针：画板编辑器页在 390dp 手机屏无布局溢出。
//
// 背景（2026-09-01）：画板底部工具条为固定尺寸滑块区（如 132px 滑块 +
// 选中形状时两条 80px 滑块），在 390dp 手机屏上存在溢出风险；主页面
// 390 门禁（app_shell_smoke_test）只覆盖首页三页签，不含画板编辑器。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpEditor(WidgetTester tester, DrawingDocument document) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: EditorPage(document: document))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('390x844：空文档画板编辑器无溢出', (tester) async {
    await pumpEditor(tester, DrawingDocument(id: 'p1', title: '空'));
    expect(tester.takeException(), isNull, reason: '空文档画板在 390dp 下溢出');
  });

  testWidgets('390x844：选中形状（样式滑块显示）无溢出', (tester) async {
    final document = DrawingDocument(id: 'p1', title: '形状');
    document.shapes.add(
      PageShapeItem(
        id: 'shp1',
        shapeType: ShapeType.rect,
        x: 30,
        y: 30,
        width: 80,
        height: 60,
        color: 0xFF000000,
        strokeWidth: 2,
      ),
    );
    await pumpEditor(tester, document);

    // 点击形状选中 → 底部工具条切换为形状样式控件（线宽/填充滑块）。
    await tester.tapAt(const Offset(60, 60));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull, reason: '选中形状后 390dp 下溢出');
  });

  testWidgets('390x844：选中文字（字号滑块+样式按钮显示）无溢出', (tester) async {
    final document = DrawingDocument(id: 'p1', title: '文字');
    document.textItems.add(
      PageTextItem(
        id: 'txt1',
        x: 30,
        y: 30,
        text: '标题',
        fontSize: 24,
        color: 0xFF000000,
      ),
    );
    await pumpEditor(tester, document);

    await tester.tapAt(const Offset(50, 50));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull, reason: '选中文字后 390dp 下溢出');
  });

  testWidgets('390x844：框选多元素出选区操作条（缩放/旋转滑块）无溢出', (tester) async {
    final document = DrawingDocument(id: 'p1', title: '多选');
    document.shapes.add(
      PageShapeItem(
        id: 'shp1',
        shapeType: ShapeType.rect,
        x: 30,
        y: 60,
        width: 60,
        height: 50,
        color: 0xFF000000,
        strokeWidth: 2,
      ),
    );
    document.shapes.add(
      PageShapeItem(
        id: 'shp2',
        shapeType: ShapeType.ellipse,
        x: 120,
        y: 60,
        width: 60,
        height: 50,
        color: 0xFF000000,
        strokeWidth: 2,
      ),
    );
    await pumpEditor(tester, document);

    // 框选工具拖一圈罩住两个形状 → 选区操作条出现。
    await tester.tap(find.byTooltip('框选多个元素'));
    await tester.pump();
    await tester.dragFrom(const Offset(20, 40), const Offset(200, 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull, reason: '选区操作条在 390dp 下溢出');
  });
}
