import 'dart:ui' as ui;

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 本轮缺陷修复回归测试。
///
/// 覆盖：
/// - 连续绘制：快速画多笔后位图完整包含所有笔画（串行化重建修复）；
/// - 橡皮擦：透明擦除生效（像素级验证）；
/// - 快捷键：Ctrl+Z/Ctrl+Y 对应的控制器操作（undo/redo）可用；
/// - 便利贴标签：isSticky 字段创建与序列化保留。
void main() {
  DrawingDocument makeDoc({int w = 200, int h = 200}) =>
      DrawingDocument(id: 'fix_doc', title: '修复回归', width: w, height: h);

  group('连续绘制（修复"画几笔画不上"）', () {
    test('快速连续画 5 笔：全部保留且位图更新', () async {
      final c = DrawingController(makeDoc());
      for (var i = 0; i < 5; i++) {
        c.startStroke(Offset(i * 30.0, 10));
        c.extendStroke(Offset(i * 30.0 + 20, 10));
        await c.endStroke(); // 每笔触发一次异步重建
      }
      // 等所有重建完成。
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.document.layers.first.strokes.length, 5, reason: '5 笔都应保留');
      final image = c.paintViews.first.image;
      expect(image, isNotNull, reason: '位图应已生成（画面不空白）');
    });

    test('连续画两笔后位图包含第二笔内容（不会停留在旧状态）', () async {
      final c = DrawingController(makeDoc());
      c.brushSize = 10;
      c.color = const Color(0xFF000000);
      // 第一笔在左侧。
      c.startStroke(const Offset(20, 100));
      c.extendStroke(const Offset(60, 100));
      await c.endStroke();
      // 第二笔在右侧（不等待第一笔重建完成，模拟快速绘制）。
      c.startStroke(const Offset(140, 100));
      c.extendStroke(const Offset(180, 100));
      await c.endStroke();
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // 校验位图右侧有内容（第二笔可见）。
      final bytes = await c.paintViews.first.image!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(bytes, isNotNull);
      int alphaAt(int x) =>
          bytes!.getUint8((100 * c.document.width + x) * 4 + 3);
      expect(alphaAt(160), greaterThan(0), reason: '第二笔应显示在位图上');
      expect(alphaAt(40), greaterThan(0), reason: '第一笔也应显示');
    });
  });

  group('橡皮擦（修复"无法擦除"）', () {
    test('画线后用橡皮擦穿过：被擦处透明、其余保留', () async {
      final c = DrawingController(makeDoc());
      c.brushSize = 16;
      c.startStroke(const Offset(20, 100));
      c.extendStroke(const Offset(180, 100));
      await c.endStroke();

      c.tool = BrushType.eraser;
      c.eraserSize = 24;
      c.startStroke(const Offset(80, 100));
      c.extendStroke(const Offset(120, 100));
      await c.endStroke();
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final bytes = await c.paintViews.first.image!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(bytes, isNotNull);
      int alphaAt(int x) =>
          bytes!.getUint8((100 * c.document.width + x) * 4 + 3);
      expect(alphaAt(100), 0, reason: '橡皮擦处应透明（被擦除）');
      expect(alphaAt(30), greaterThan(0), reason: '未擦除处保留');
      expect(alphaAt(170), greaterThan(0), reason: '未擦除处保留');
    });
  });

  group('快捷键（Ctrl+Z/Ctrl+Y）', () {
    test('撤销/重做控制器操作在快捷键语义下可用', () async {
      final c = DrawingController(makeDoc());
      // 模拟 Ctrl+Z：undo()。
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(20, 20));
      await c.endStroke();
      expect(c.canUndo, isTrue);

      // Ctrl+Z → undo
      c.undo();
      expect(c.document.layers.first.strokes, isEmpty);
      expect(c.canRedo, isTrue);

      // Ctrl+Y → redo
      c.redo();
      expect(c.document.layers.first.strokes.length, 1);
    });
  });

  group('便利贴标签（isSticky）', () {
    test('创建便利贴标签：isSticky 为 true 且可序列化保留', () {
      final item = PageTextItem(
        id: 'sticky_1',
        x: 50,
        y: 60,
        text: '重要提醒',
        fontSize: 32,
        color: 0xFFFFF59D,
        isSticky: true,
      );
      expect(item.isSticky, isTrue);

      final restored = PageTextItem.fromJson(item.toJson());
      expect(restored.isSticky, isTrue, reason: '标签标志应序列化保留');
      expect(restored.text, '重要提醒');
      expect(restored.fontSize, 32);
    });

    test('普通文字块 isSticky 默认 false', () {
      final item = PageTextItem(id: 't1', x: 0, y: 0, text: '普通文字');
      expect(item.isSticky, isFalse);
      final restored = PageTextItem.fromJson(item.toJson());
      expect(restored.isSticky, isFalse);
    });

    test('页面序列化往返：便利贴与普通文字混排保留', () {
      final page = NotebookPage(
        id: 'pg_1',
        title: '混排页',
        document: DrawingDocument(id: 'd1', title: '页'),
      );
      page.textItems.add(
        PageTextItem(id: 'a', x: 0, y: 0, text: '普通', isSticky: false),
      );
      page.textItems.add(
        PageTextItem(id: 'b', x: 100, y: 100, text: '标签', isSticky: true),
      );
      final restored = NotebookPage.fromJson(page.toJson());
      expect(restored.textItems[0].isSticky, isFalse);
      expect(restored.textItems[1].isSticky, isTrue);
    });
  });

  group('纸张模板（借鉴 Relatum/GoodNotes）', () {
    test('paperType 默认空白，可切换并序列化保留', () {
      final doc = DrawingDocument(id: 'pt1', title: '纸张');
      expect(doc.paperType, PaperType.blank);
      doc.paperType = PaperType.grid;
      final restored = DrawingDocument.fromJson(doc.toJson());
      expect(restored.paperType, PaperType.grid, reason: '模板类型应序列化保留');
    });

    test('四种模板均可序列化往返', () {
      for (final t in PaperType.values) {
        final doc = DrawingDocument(id: 'pt2', title: 't')..paperType = t;
        final restored = DrawingDocument.fromJson(doc.toJson());
        expect(restored.paperType, t);
      }
    });

    test('未知 paperType 回退为空白（向后兼容）', () {
      final json = DrawingDocument(id: 'pt3', title: 't').toJson();
      json['paperType'] = 'unknown_legacy';
      final restored = DrawingDocument.fromJson(json);
      expect(restored.paperType, PaperType.blank);
    });
  });
}
