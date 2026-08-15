import 'dart:ui' as ui;

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/layer_compositor.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 2 验收测试：基础绘图工具。
///
/// 验收标准（来自开发计划 4.3 Phase 2）：
/// - 画笔粗细可调（滑块或预设）→ 验证 brushSize/eraserSize 生效于笔画宽度；
/// - 颜色选择（基础色板）→ 验证 color 生效于笔画颜色；
/// - 橡皮擦：真正透明擦除（不是画白色）→ 验证渲染像素 alpha 为 0；
/// - 吸管工具：点击画布已有颜色，切换成该颜色 → 验证 pickColorAt 返回预期颜色。
void main() {
  DrawingDocument makeDoc({int w = 200, int h = 200}) =>
      DrawingDocument(id: 't2', title: '测试画布', width: w, height: h);

  DrawingController makeController() => DrawingController(makeDoc());

  group('Phase 2 基础绘图工具', () {
    test('画笔粗细可调：笔画记录使用设置的粗细', () async {
      final c = makeController();
      c.brushSize = 20;
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(50, 50));
      await c.endStroke();
      expect(c.document.layers.first.strokes.first.width, 20);

      // 橡皮擦使用独立的粗细设置
      c.tool = BrushType.eraser;
      c.eraserSize = 40;
      c.startStroke(const Offset(100, 100));
      c.extendStroke(const Offset(150, 150));
      await c.endStroke();
      expect(c.document.layers.first.strokes.last.width, 40);
      expect(c.document.layers.first.strokes.last.type, BrushType.eraser);
    });

    test('颜色选择：笔画使用当前画笔颜色', () async {
      final c = makeController();
      const target = Color(0xFFE53935); // 红色
      c.color = target;
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(50, 50));
      await c.endStroke();
      expect(c.document.layers.first.strokes.first.color, target);
    });

    test('橡皮擦是"透明擦除"而非"画白色"', () async {
      // 渲染一个图层：先画黑色笔画，再用橡皮擦穿过其中间，
      // 检查被擦除处像素 alpha == 0（透明），而非白色。
      final doc = makeDoc();
      final layer = doc.layers.first;
      // 画一条从左到右的水平黑线（y=100）。
      layer.strokes.add(
        Stroke(
          points: [
            const StrokePoint(10, 100, 1),
            const StrokePoint(190, 100, 1),
          ],
          color: const Color(0xFF000000),
          width: 20,
          type: BrushType.pen,
        ),
      );
      // 橡皮擦擦除中间一小段。
      layer.strokes.add(
        Stroke(
          points: [
            const StrokePoint(90, 100, 1),
            const StrokePoint(110, 100, 1),
          ],
          color: const Color(0xFF000000),
          width: 30,
          type: BrushType.eraser,
        ),
      );

      const compositor = LayerCompositor();
      final image = await compositor.rasterize(layer, doc.width, doc.height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bytes, isNotNull);

      int alphaAt(int x, int y) => bytes!.getUint8((y * doc.width + x) * 4 + 3);

      // 被橡皮擦擦除处：alpha 应为 0（透明）。
      expect(alphaAt(100, 100), 0, reason: '橡皮擦应产生透明擦除');
      // 未擦除的黑线处：alpha 应非 0（仍可见）。
      expect(alphaAt(30, 100), greaterThan(0), reason: '未擦除处应保留笔画');
      expect(alphaAt(170, 100), greaterThan(0), reason: '未擦除处应保留笔画');
    });

    test('吸管取色：能取到画布上已有笔画的颜色', () async {
      final c = makeController();
      // 先用红色画一条粗线，等待缓存重建。
      c.color = const Color(0xFFFF5722);
      c.brushSize = 40;
      c.startStroke(const Offset(50, 100));
      c.extendStroke(const Offset(150, 100));
      await c.endStroke();
      // 等图层位图缓存完成重建（渲染异步完成）。
      var image = c.paintViews.first.image;
      for (var i = 0; i < 50 && image == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        image = c.paintViews.first.image;
      }
      expect(image, isNotNull, reason: '图层位图应已生成');

      final picked = await c.pickColorAt(const Offset(100, 100));
      expect(picked, isNotNull);
      // 颜色近似比较：笔画中心应为橙色（允许抗锯齿误差）。
      final p = picked!;
      expect(p.r, closeTo(1.0, 0.15));
      expect(p.g, closeTo(0.34, 0.2));
      expect(p.b, closeTo(0.13, 0.2));
    });

    test('吸管取色：空白区域返回透明色', () async {
      final c = makeController();
      // 画一条线在左侧，右侧留白。
      c.brushSize = 10;
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(20, 10));
      await c.endStroke();
      var image = c.paintViews.first.image;
      for (var i = 0; i < 50 && image == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        image = c.paintViews.first.image;
      }
      final picked = await c.pickColorAt(const Offset(150, 150));
      expect(picked, isNotNull);
      expect(picked!.a, 0, reason: '空白处应为全透明');
    });
  });
}
