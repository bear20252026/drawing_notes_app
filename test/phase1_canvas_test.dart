import 'package:drawing_notes_app/engine/drawing_controller.dart';
import 'package:drawing_notes_app/models/document.dart';
import 'package:drawing_notes_app/models/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 1 验收测试：最小画布（绘制、撤销、清空）。
///
/// 验收标准（来自开发计划 4.3 Phase 1）：
/// - 能用鼠标/手指画出连续线条 → 验证笔画写入图层；
/// - 画错了能撤销 → 验证 undo/redo；
/// - 清空画布 → 验证 clearAll。
void main() {
  DrawingDocument makeDoc() =>
      DrawingDocument(id: 't1', title: '测试画布', width: 200, height: 200);

  DrawingController makeController() => DrawingController(makeDoc());

  group('Phase 1 最小画布', () {
    test('初始状态：有且仅有一个空白图层', () {
      final c = makeController();
      expect(c.document.layers.length, 1);
      expect(c.currentLayer.strokes, isEmpty);
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isFalse);
    });

    test('绘制一条连续线条后，笔画写入当前图层', () async {
      final c = makeController();
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(20, 20));
      c.extendStroke(const Offset(30, 25));
      await c.endStroke();

      expect(c.document.layers.first.strokes.length, 1);
      final stroke = c.document.layers.first.strokes.first;
      expect(stroke.points.length, 3);
      expect(stroke.type, BrushType.pen);
      expect(c.canUndo, isTrue);
    });

    test('撤销：撤销上一笔后笔画消失，重做可恢复', () async {
      final c = makeController();
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(20, 20));
      await c.endStroke();
      expect(c.document.layers.first.strokes.length, 1);

      c.undo();
      expect(c.document.layers.first.strokes, isEmpty);
      expect(c.canRedo, isTrue);

      c.redo();
      expect(c.document.layers.first.strokes.length, 1);
    });

    test('多级撤销：连续画两笔可依次撤销', () async {
      final c = makeController();
      c.startStroke(const Offset(0, 0));
      c.extendStroke(const Offset(5, 5));
      await c.endStroke();
      c.startStroke(const Offset(50, 50));
      c.extendStroke(const Offset(60, 60));
      await c.endStroke();

      expect(c.document.layers.first.strokes.length, 2);
      c.undo();
      expect(c.document.layers.first.strokes.length, 1);
      c.undo();
      expect(c.document.layers.first.strokes, isEmpty);
      expect(c.canUndo, isFalse);
    });

    test('清空画布：清空所有图层全部内容，且可撤销恢复', () async {
      final c = makeController();
      c.startStroke(const Offset(0, 0));
      c.extendStroke(const Offset(10, 10));
      await c.endStroke();

      c.clearAll();
      expect(c.document.layers.first.strokes, isEmpty);

      c.undo();
      expect(c.document.layers.first.strokes.length, 1);
    });

    test('单点（单击未拖动）也应产生一个墨点', () async {
      final c = makeController();
      c.startStroke(const Offset(100, 100));
      await c.endStroke();
      expect(c.document.layers.first.strokes.length, 1);
      expect(c.document.layers.first.strokes.first.points.length, 1);
    });
  });
}
