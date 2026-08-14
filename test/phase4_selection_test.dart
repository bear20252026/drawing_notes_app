import 'package:drawing_notes_app/engine/drawing_controller.dart';
import 'package:drawing_notes_app/models/document.dart';
import 'package:drawing_notes_app/models/selection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 4 验收测试：选区与变换。
///
/// 验收标准（来自开发计划 4.3 Phase 4）：
/// - 矩形选区工具（框选一块区域）
/// - 套索选区工具（自由画线选择区域）
/// - 选中内容后可以：移动、缩放、旋转
/// - 复制/粘贴选中内容
/// - 删除选中内容
/// - 能选中画布上一部分内容并独立移动/缩放，不影响其他部分
void main() {
  DrawingDocument makeDoc() =>
      DrawingDocument(id: 't4', title: '测试画布', width: 400, height: 400);

  DrawingController makeController() => DrawingController(makeDoc());

  /// 在当前图层画一条从 a 到 b 的直线（供选区命中测试使用）。
  Future<void> drawLine(DrawingController c, Offset a, Offset b) async {
    c.startStroke(a);
    c.extendStroke(b);
    await c.endStroke();
  }

  /// 画三条互不重叠的线：左(50,50)-(150,50)、中(200,50)-(300,50)、右(100,300)-(200,300)。
  Future<void> drawThreeLines(DrawingController c) async {
    await drawLine(c, const Offset(50, 50), const Offset(150, 50));
    await drawLine(c, const Offset(200, 50), const Offset(300, 50));
    await drawLine(c, const Offset(100, 300), const Offset(200, 300));
  }

  /// 用矩形选区框选 (0,0)-(160,160) 区域。
  void rectSelect(DrawingController c) {
    c.selectionTool = SelectionTool.rect;
    c.beginSelection(const Offset(0, 0));
    c.extendSelection(const Offset(160, 160));
    c.endSelection();
  }

  group('Phase 4 选区与变换', () {
    test('矩形选区：框选区域内（含部分相交）的笔画被命中', () async {
      final c = makeController();
      await drawThreeLines(c);

      rectSelect(c);

      expect(c.hasSelection, isTrue);
      // 第一条线 (50,50)-(150,50) 整条在选区内；第二条线起点(200,50)在选区外；
      // 第三条线 (100,300) 起点在 (0,0)-(160,160) 框内？y=300 超出，不在。
      expect(c.hasSelectedStrokes, isTrue);
      expect(c.selection.selectedStrokeIndices, [0], reason: '只有第一条线命中');
    });

    test('矩形选区：框住多条线时全部命中', () async {
      final c = makeController();
      await drawThreeLines(c);

      c.selectionTool = SelectionTool.rect;
      c.beginSelection(const Offset(0, 0));
      c.extendSelection(const Offset(400, 400));
      c.endSelection();

      expect(c.selection.selectedStrokeIndices, [0, 1, 2]);
    });

    test('套索选区：自由多边形命中笔画', () async {
      final c = makeController();
      await drawThreeLines(c);

      c.selectionTool = SelectionTool.lasso;
      c.beginSelection(const Offset(0, 0));
      c.extendSelection(const Offset(150, 0));
      c.extendSelection(const Offset(150, 150));
      c.extendSelection(const Offset(0, 150));
      c.endSelection();

      expect(c.selection.selectedStrokeIndices, [0]);
    });

    test('移动选中内容：只有命中的笔画移动，其他笔画不受影响', () async {
      final c = makeController();
      await drawThreeLines(c);

      rectSelect(c);
      final before0 = c.document.layers.first.strokes[0].points.first.offset;
      final before1 = c.document.layers.first.strokes[1].points.first.offset;

      c.moveSelectedStrokes(const Offset(50, 100));
      c.endTransform();

      final strokes = c.document.layers.first.strokes;
      expect(strokes[0].points.first.offset, before0 + const Offset(50, 100));
      // 未选中的第二条线位置不变
      expect(strokes[1].points.first.offset, before1);
    });

    test('移动后可撤销：恢复到移动前位置', () async {
      final c = makeController();
      await drawThreeLines(c);
      rectSelect(c);
      final before0 = c.document.layers.first.strokes[0].points.first.offset;

      c.moveSelectedStrokes(const Offset(50, 100));
      c.endTransform();
      c.undo();

      expect(
        c.document.layers.first.strokes[0].points.first.offset,
        before0,
        reason: '撤销后笔画回到原位',
      );
    });

    test('缩放选中内容：围绕选区中心按比例放大', () async {
      final c = makeController();
      await drawLine(c, const Offset(100, 100), const Offset(120, 100));
      rectSelect(c);
      // 变换必须围绕实际选中笔画的外接框中心，而非可任意画大的套索中心。
      const center = Offset(110, 100);
      final first = c.document.layers.first.strokes.first.points.first.offset;

      c.scaleSelectedStrokes(2.0);
      c.endTransform();

      final newFirst =
          c.document.layers.first.strokes.first.points.first.offset;
      final expected = center + (first - center) * 2.0;
      expect(
        (newFirst - expected).distance,
        lessThan(1e-6),
        reason: '缩放围绕中心生效',
      );
    });

    test('旋转选中内容：围绕选区中心旋转 90 度', () async {
      final c = makeController();
      await drawLine(c, const Offset(100, 100), const Offset(120, 100));
      rectSelect(c);
      // 与缩放一致：使用实际墨迹边界中心，避免大套索导致旋转漂移。
      const center = Offset(110, 100);
      final first = c.document.layers.first.strokes.first.points.first.offset;

      c.rotateSelectedStrokes(3.14159265 / 2);
      c.endTransform();

      final newFirst =
          c.document.layers.first.strokes.first.points.first.offset;
      // 旋转 90°：(dx, dy) -> (-dy, dx)
      final dx = first.dx - center.dx;
      final dy = first.dy - center.dy;
      final expected = Offset(center.dx - dy, center.dy + dx);
      expect((newFirst - expected).distance, lessThan(1e-3));
    });

    test('删除选中内容：只删除命中的笔画', () async {
      final c = makeController();
      await drawThreeLines(c);

      rectSelect(c);
      c.deleteSelectedStrokes();

      final strokes = c.document.layers.first.strokes;
      expect(strokes.length, 2, reason: '删除了一条，剩两条');
      expect(strokes[0].points.first.offset.dx, 200, reason: '第二条线仍在');
      expect(strokes[1].points.first.offset.dx, 100, reason: '第三条线仍在');
      expect(c.hasSelection, isFalse, reason: '删除后选区清空');
    });

    test('删除后撤销：笔画恢复', () async {
      final c = makeController();
      await drawThreeLines(c);
      rectSelect(c);
      c.deleteSelectedStrokes();
      expect(c.document.layers.first.strokes.length, 2);

      c.undo();
      expect(c.document.layers.first.strokes.length, 3, reason: '撤销后三条线恢复');
    });

    test('复制+粘贴：粘贴后笔画数量增加且内容相同', () async {
      final c = makeController();
      await drawLine(c, const Offset(100, 100), const Offset(120, 100));
      rectSelect(c);

      c.copySelectedStrokes();
      expect(c.document.layers.first.strokes.length, 1, reason: '复制不改变画布');

      c.pasteClipboard();
      final strokes = c.document.layers.first.strokes;
      expect(strokes.length, 2, reason: '粘贴后多一条');

      // 粘贴内容与原始内容长度一致
      expect(strokes[0].points.length, strokes[1].points.length);
      // 粘贴位置偏移了（不在原位置）
      expect(
        (strokes[1].points.first.offset - strokes[0].points.first.offset)
            .distance,
        greaterThan(0),
        reason: '粘贴内容应位于不同位置',
      );
    });

    test('清除选区：选区与命中结果被清空', () async {
      final c = makeController();
      await drawThreeLines(c);
      rectSelect(c);
      expect(c.hasSelection, isTrue);

      c.clearSelection();
      expect(c.hasSelection, isFalse);
      expect(c.hasSelectedStrokes, isFalse);
    });

    test('切换选区工具会清空旧选区', () async {
      final c = makeController();
      await drawThreeLines(c);
      rectSelect(c);
      expect(c.hasSelection, isTrue);

      c.selectionTool = SelectionTool.lasso;
      expect(c.hasSelection, isFalse, reason: '切换工具后旧选区清空');
    });
  });
}
