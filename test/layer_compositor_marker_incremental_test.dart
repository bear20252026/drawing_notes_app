// D12 续（2026-09-23）：marker 层增量脏矩形回归。
//
// 背景：v1.17.12 的增量路径逐笔画 drawStroke，marker 会以半透明
// srcOver 直绘破坏「同色不叠色」，因此对含高亮笔的图层强制全量重建。
// 放行后区域重绘与全量同走 InkLayerPainter 计划（同色分组 darken 层）。
// 本文件锁定两条不变量：
//   1. 增量结果与全量重建逐字节一致（区域内清空重绘 = 区域内全量；
//      区域外字节同源自旧位图）；
//   2. 脏矩形之外与旧位图逐字节一致（增量只改区域内）。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/rendering/layer_compositor.dart';
import 'package:flutter_test/flutter_test.dart';

const _canvasSize = 128;
const _markerYellow = ui.Color(0xFFFFEB3B);
const _penBlack = ui.Color(0xFF000000);

Stroke _marker(OffsetLike a, OffsetLike b) => Stroke(
  points: [StrokePoint(a.x, a.y, 0.5), StrokePoint(b.x, b.y, 0.9)],
  color: _markerYellow,
  width: 14,
  type: BrushType.marker,
);

Stroke _pen(OffsetLike a, OffsetLike b) => Stroke(
  points: [StrokePoint(a.x, a.y, 0.5), StrokePoint(b.x, b.y, 0.9)],
  color: _penBlack,
  width: 5,
  type: BrushType.pen,
);

class OffsetLike {
  const OffsetLike(this.x, this.y);
  final double x;
  final double y;
}

Future<Uint8List> _pixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('D12：marker 层增量重建与全量重建一致（容差内）', () async {
    const compositor = LayerCompositor();
    final layer = Layer(id: 'l1', name: 'L1');
    // 底面：一条横贯高亮 + 一条竖穿黑笔（高亮在下、墨迹在上）。
    final m1 = _marker(OffsetLike(10, 64), OffsetLike(118, 64));
    final n1 = _pen(OffsetLike(64, 20), OffsetLike(64, 110));
    layer.strokes.addAll([m1, n1]);
    final baseImage = await compositor.rasterize(layer, _canvasSize, _canvasSize);

    // 追加同色高亮：斜穿 m1 与 n1，走增量脏矩形路径。
    // 区域取整数对齐的竖带（完整盖住 m2 的包围盒并留边），使 clipRect
    // 无分数边缘抗锯齿，区域内可与全量重建做逐字节等价断言。
    final m2 = _marker(OffsetLike(55, 15), OffsetLike(75, 115));
    layer.strokes.add(m2);
    const region = ui.Rect.fromLTWH(40.0, 0.0, 48.0, 128.0);
    final incrementalImage = await compositor.rasterize(
      layer,
      _canvasSize,
      _canvasSize,
      region: region,
      base: baseImage,
    );
    // 对照组：同一笔画集合的全量重建。
    final fullImage = await compositor.rasterize(layer, _canvasSize, _canvasSize);

    final base = await _pixels(baseImage);
    final incremental = await _pixels(incrementalImage);
    final full = await _pixels(fullImage);

    // 1) 增量 vs 全量：区域内逐字节一致（清空重绘 = 区域内全量）；
    //    区域外字节同源（base 原样保留），全图应零差异。
    var outliers = 0;
    for (var i = 0; i < incremental.length; i++) {
      if (incremental[i] != full[i]) outliers++;
    }
    expect(outliers, 0,
        reason: 'marker 增量重建偏离全量重建（$outliers 处字节差异）');

    // 2) 脏矩形外与旧位图逐字节一致（外扩 2px 避开裁剪边缘抗锯齿）。
    final left = (region.left - 2).floor().clamp(0, _canvasSize);
    final top = (region.top - 2).floor().clamp(0, _canvasSize);
    final right = (region.right + 2).ceil().clamp(0, _canvasSize);
    final bottom = (region.bottom + 2).ceil().clamp(0, _canvasSize);
    for (var y = 0; y < _canvasSize; y++) {
      for (var x = 0; x < _canvasSize; x++) {
        if (x >= left && x < right && y >= top && y < bottom) continue;
        final o = (y * _canvasSize + x) * 4;
        for (var c = 0; c < 4; c++) {
          expect(incremental[o + c], base[o + c],
              reason: '脏矩形外像素 ($x,$y) 通道 $c 被增量重建意外改动');
        }
      }
    }

    baseImage.dispose();
    incrementalImage.dispose();
    fullImage.dispose();
  });

  test('D12：marker 层增量重建确实生效（区域内出现新笔画）', () async {
    const compositor = LayerCompositor();
    final layer = Layer(id: 'l1', name: 'L1');
    layer.strokes.add(_marker(OffsetLike(10, 64), OffsetLike(118, 64)));
    final baseImage = await compositor.rasterize(layer, _canvasSize, _canvasSize);
    final base = await _pixels(baseImage);

    final m2 = _marker(OffsetLike(55, 15), OffsetLike(75, 115));
    layer.strokes.add(m2);
    final incrementalImage = await compositor.rasterize(
      layer,
      _canvasSize,
      _canvasSize,
      region: const ui.Rect.fromLTWH(40.0, 0.0, 48.0, 128.0),
      base: baseImage,
    );
    final incremental = await _pixels(incrementalImage);

    // 若 marker 仍被强制全量（忽略 region），此处行为也正确但路径不同；
    // 该断言锁定「区域内确实渲染出了新笔画」的可见效果。
    var changed = 0;
    for (var i = 0; i < incremental.length; i += 4) {
      if ((incremental[i] - base[i]).abs() > 8 ||
          (incremental[i + 1] - base[i + 1]).abs() > 8) {
        changed++;
      }
    }
    expect(changed, greaterThan(0), reason: '增量重建后区域内应出现新高亮笔画');

    baseImage.dispose();
    incrementalImage.dispose();
  });
}
