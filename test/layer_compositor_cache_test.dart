import 'dart:ui' as ui;

import 'package:drawing_notes_app/features/drawing/rendering/layer_compositor.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_picture_cache.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke _stroke({required BrushType type}) => Stroke(
  points: const [StrokePoint(20, 60, 0.5), StrokePoint(100, 60, 0.9)],
  color: const ui.Color(0xFF000000),
  width: 6,
  type: type,
);

void main() {
  group('LayerCompositor pictureCache 接入', () {
    test('启用缓存：相同图层全量重建命中指纹（缓存条目增长）', () async {
      final cache = StrokePictureCache();
      final compositor = LayerCompositor(pictureCache: cache);
      final layer = Layer(id: 'l1', name: 'L1');
      layer.strokes.add(_stroke(type: BrushType.pen));

      await compositor.rasterize(layer, 100, 100);
      expect(cache.cacheCount, 1, reason: '首次全量重建应缓存');

      await compositor.rasterize(layer, 100, 100);
      expect(cache.cacheCount, 1, reason: '同图层再次重建应命中缓存');
    });

    test('启用缓存：笔画新增 → 指纹失效重建', () async {
      final cache = StrokePictureCache();
      final compositor = LayerCompositor(pictureCache: cache);
      final layer = Layer(id: 'l1', name: 'L1');
      layer.strokes.add(_stroke(type: BrushType.pen));

      await compositor.rasterize(layer, 100, 100);
      expect(cache.cacheCount, 1);

      layer.strokes.add(_stroke(type: BrushType.pen));
      await compositor.rasterize(layer, 100, 100);
      expect(cache.cacheCount, 2, reason: '笔画集合变化应重建新条目');
    });

    test('启用缓存：marker 图层不走缓存（保"不叠色"语义）', () async {
      final cache = StrokePictureCache();
      final compositor = LayerCompositor(pictureCache: cache);
      final layer = Layer(id: 'l1', name: 'L1');
      layer.strokes.add(_stroke(type: BrushType.marker));

      await compositor.rasterize(layer, 100, 100);
      expect(cache.cacheCount, 0, reason: 'marker 图层应回退原路径不缓存');
    });

    test('未启用缓存：pictureCache null 走原路径', () async {
      const compositor = LayerCompositor();
      final layer = Layer(id: 'l1', name: 'L1');
      layer.strokes.add(_stroke(type: BrushType.pen));

      final image = await compositor.rasterize(layer, 100, 100);
      expect(image, isNotNull);
      image.dispose();
    });
  });

  group('图层位图长边封顶（2026-09-06 内存治理）', () {
    test('小画布保持原尺寸（scale=1，零行为变化）', () async {
      const compositor = LayerCompositor();
      final layer = Layer(id: 'small', name: 'L');
      layer.strokes.add(_stroke(type: BrushType.pen));

      final image = await compositor.rasterize(layer, 100, 100);
      expect(image.width, 100);
      expect(image.height, 100);
      image.dispose();
    });

    test('大画布（如 A4 2480×3508）位图长边封顶到 2048', () async {
      const compositor = LayerCompositor();
      final layer = Layer(id: 'a4', name: 'L');
      layer.strokes.add(_stroke(type: BrushType.pen));

      final image = await compositor.rasterize(layer, 2480, 3508);
      // 长边 3508 → 2048；短边按同比例：2480*2048/3508 ≈ 1448。
      expect(image.height, LayerCompositor.maxBitmapLongEdge);
      expect(image.width, lessThan(LayerCompositor.maxBitmapLongEdge));
      expect(image.width, closeTo(1448, 2));
      // 内存：2048²×4 ≈ 16MB 上限，远小于原 2480×3508×4 ≈ 35MB。
      expect(
        image.width * image.height * 4,
        lessThan(LayerCompositor.maxBitmapLongEdge *
            LayerCompositor.maxBitmapLongEdge *
            4),
      );
      image.dispose();
    });
  });
}
