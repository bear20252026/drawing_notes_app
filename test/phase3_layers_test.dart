import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3 验收测试：图层系统。
///
/// 验收标准（来自开发计划 4.3 Phase 3）：
/// - 新建图层、删除图层
/// - 图层列表面板，显示所有图层缩略图（UI 部分见 widget 测试）
/// - 图层显示/隐藏切换
/// - 图层透明度调节（滑块，0-100%）
/// - 图层顺序调整（上移/下移）
/// - 图层合并（把两个图层合成一个）
/// - 最终合并不丢失内容
void main() {
  DrawingDocument makeDoc() =>
      DrawingDocument(id: 't3', title: '测试画布', width: 200, height: 200);

  DrawingController makeController() => DrawingController(makeDoc());

  /// 在当前图层画一笔（返回该笔画）。
  Future<Stroke> drawStroke(DrawingController c, Offset from, Offset to) async {
    c.startStroke(from);
    c.extendStroke(to);
    await c.endStroke();
    return c.currentLayer.strokes.last;
  }

  group('Phase 3 图层系统', () {
    test('新建图层：新增到最上层并自动选中', () {
      final c = makeController();
      expect(c.document.layers.length, 1);

      c.addLayer();
      expect(c.document.layers.length, 2);
      expect(c.currentLayerIndex, 1, reason: '新图层应自动选中');

      c.addLayer();
      expect(c.document.layers.length, 3);
      expect(c.currentLayerIndex, 2);
    });

    test('删除图层：可删除，且至少保留一个图层', () {
      final c = makeController();
      c.addLayer();
      c.addLayer();
      expect(c.document.layers.length, 3);

      c.removeLayer(2);
      expect(c.document.layers.length, 2);

      c.removeLayer(1);
      expect(c.document.layers.length, 1);

      // 最后一个图层不能被删除
      c.removeLayer(0);
      expect(c.document.layers.length, 1, reason: '至少保留一个图层');
    });

    test('图层显隐切换：visible 属性翻转', () {
      final c = makeController();
      c.addLayer();
      final layer = c.document.layers[1];
      expect(layer.visible, isTrue);

      c.toggleLayerVisibility(1);
      expect(layer.visible, isFalse);

      c.toggleLayerVisibility(1);
      expect(layer.visible, isTrue);
    });

    test('图层透明度调节：0~1 范围生效', () {
      final c = makeController();
      c.addLayer();
      c.setLayerOpacity(1, 0.5);
      expect(c.document.layers[1].opacity, 0.5);

      c.setLayerOpacity(1, 0);
      expect(c.document.layers[1].opacity, 0);

      c.setLayerOpacity(1, 1.2); // 越界值被钳制
      expect(c.document.layers[1].opacity, 1.0);
    });

    test('图层排序：上移/下移互换顺序，撤销可恢复', () {
      final c = makeController();
      c.addLayer(); // 索引0: 底, 索引1: 上
      final bottom = c.document.layers[0];
      final top = c.document.layers[1];

      c.moveLayerDown(1); // 把上层移到下面
      expect(c.document.layers[0].id, top.id);
      expect(c.document.layers[1].id, bottom.id);
      expect(c.currentLayerIndex, 0);

      c.moveLayerUp(0); // 再移回上面
      expect(c.document.layers[0].id, bottom.id);
      expect(c.document.layers[1].id, top.id);
      expect(c.currentLayerIndex, 1);

      // 撤销恢复到"上移之后"状态
      c.undo();
      expect(c.document.layers[0].id, top.id);
      expect(c.document.layers[1].id, bottom.id);
    });

    test('图层合并：上下两层内容合并不丢失', () async {
      final c = makeController();
      c.addLayer(); // 索引1：上层
      c.currentLayerIndex = 0;
      await drawStroke(c, const Offset(10, 10), const Offset(50, 10)); // 底层画一笔
      c.currentLayerIndex = 1;
      await drawStroke(c, const Offset(10, 50), const Offset(50, 50)); // 上层画一笔

      final bottomStrokesBefore = c.document.layers[0].strokes.length;
      final topStrokesBefore = c.document.layers[1].strokes.length;

      c.mergeLayerDown(1); // 上层合并到下层

      expect(c.document.layers.length, 1, reason: '合并后只剩一层');
      final merged = c.document.layers[0];
      expect(
        merged.strokes.length,
        bottomStrokesBefore + topStrokesBefore,
        reason: '合并后内容不丢失（笔画数相加）',
      );
      // 笔画顺序：底层内容在前，上层内容在后
      expect(merged.strokes.first.points.first.offset.dy, 10, reason: '底层笔画在前');
      expect(merged.strokes.last.points.first.offset.dy, 50, reason: '上层笔画在后');

      // 撤销可恢复为两层
      c.undo();
      expect(c.document.layers.length, 2);
    });

    test('多图层分别绘制：每个图层独立保存笔画', () async {
      final c = makeController();
      c.addLayer();
      c.addLayer();

      c.currentLayerIndex = 0;
      await drawStroke(c, const Offset(0, 0), const Offset(10, 10));
      c.currentLayerIndex = 1;
      await drawStroke(c, const Offset(100, 100), const Offset(110, 110));
      c.currentLayerIndex = 2;
      await drawStroke(c, const Offset(50, 50), const Offset(60, 60));

      expect(c.document.layers[0].strokes.length, 1);
      expect(c.document.layers[1].strokes.length, 1);
      expect(c.document.layers[2].strokes.length, 1);
      expect(c.document.layers[0].strokes.first.points.first.offset.dx, 0);
      expect(c.document.layers[2].strokes.first.points.first.offset.dx, 50);
    });

    test('图层操作可撤销：删除图层后撤销可恢复', () {
      final c = makeController();
      c.addLayer();
      final layerId = c.document.layers[1].id;

      c.removeLayer(1);
      expect(c.document.layers.length, 1);

      c.undo();
      expect(c.document.layers.length, 2);
      expect(c.document.layers[1].id, layerId, reason: '撤销后图层恢复');
    });
  });
}
