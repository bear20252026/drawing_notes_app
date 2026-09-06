// 回归：封顶光栅化的坐标缩放（2026-09-07「松手后墨迹偏移」根因）。
//
// LayerCompositor.rasterize 把长边超过 2048 的文档光栅化到封顶位图。
// Picture.toImage 按 1:1 光标化、不做缩放——若不先 canvas.scale(位图/文档)，
// 文档坐标的笔画只把左上角截进位图，显示端 drawImageRect 再拉伸整页，
// 墨迹呈 位置×(1/factor) 向右下偏移（活动笔画预览是矢量直绘所以画时
// 正确、一提交就跳，用户实测症状）。本测试在像素级锁定：
// 已知文档位置的笔画，光栅化后墨迹质心必须落在等比缩放后的位置。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/rendering/layer_compositor.dart';

/// 计算位图中墨迹（alpha > 8）的质心。
Future<ui.Offset> inkCentroid(ui.Image image) async {
  final ByteData bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!;
  final data = bytes.buffer.asUint8List();
  var sx = 0.0;
  var sy = 0.0;
  var n = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final a = data[(y * image.width + x) * 4 + 3];
      if (a > 8) {
        sx += x;
        sy += y;
        n++;
      }
    }
  }
  expect(n, greaterThan(0), reason: '位图中应有墨迹');
  return ui.Offset(sx / n, sy / n);
}

Stroke _hLine(double x0, double x1, double y) => Stroke(
  points: [StrokePoint(x0, y, 1), StrokePoint(x1, y, 1)],
  color: const ui.Color(0xFF000000),
  width: 6,
  type: BrushType.pen,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('封顶文档：墨迹质心 = 文档位置 × (位图/文档) 缩放比', () async {
    const docW = 2000;
    const docH = 3000; // 长边 3000 > 2048 → 封顶
    const factor = LayerCompositor.maxBitmapLongEdge / docH;
    final layer = Layer(id: 'l1', name: '图层1')
      ..strokes.add(_hLine(1000, 1100, 1500));

    final image = await const LayerCompositor().rasterize(layer, docW, docH);
    addTearDown(image.dispose);

    expect(image.width, (docW * factor).round());
    expect(image.height, LayerCompositor.maxBitmapLongEdge);

    final centroid = await inkCentroid(image);
    const expected = ui.Offset(1050 * factor, 1500 * factor);
    expect(
      (centroid - expected).distance,
      lessThan(8),
      reason:
          '墨迹应落在缩放后的位置 $expected，实际 $centroid'
          '（若落在 1:1 的 (1050,1500) 附近 = 缺 canvas.scale 的旧 bug）',
    );
  });

  test('非封顶文档：scale(1,1) 零行为变化，墨迹质心 = 文档位置', () async {
    const docW = 1000;
    const docH = 1000;
    final layer = Layer(id: 'l2', name: '图层2')
      ..strokes.add(_hLine(400, 500, 600));

    final image = await const LayerCompositor().rasterize(layer, docW, docH);
    addTearDown(image.dispose);

    expect(image.width, docW);
    expect(image.height, docH);

    final centroid = await inkCentroid(image);
    const expected = ui.Offset(450, 600);
    expect(
      (centroid - expected).distance,
      lessThan(8),
      reason: '非封顶路径必须保持原语义：$expected vs $centroid',
    );
  });
}
