import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/rendering/stroke_picture_cache.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

List<StrokePoint> _pts(List<(double, double)> raw) =>
    raw.map((p) => StrokePoint(p.$1, p.$2, 0.5)).toList();

Stroke _makeStroke(List<(double, double)> raw) {
  return Stroke(
    points: _pts(raw),
    color: const ui.Color(0xFF000000),
    width: 3,
    type: BrushType.pen,
  );
}

void main() {
  group('StrokePictureCache', () {
    test('相同笔画集合命中缓存（指纹一致）', () {
      final cache = StrokePictureCache();
      final strokes = [_makeStroke([(0.0, 0.0), (10.0, 10.0)])];
      const size = ui.Size(100, 100);

      final p1 = cache.pictureFor(strokes, size: size);
      final p2 = cache.pictureFor(strokes, size: size);

      expect(p1, isNotNull);
      expect(identical(p1, p2), isTrue, reason: '指纹一致应命中同一张 Picture');
      expect(cache.cacheCount, 1);
      p1?.dispose();
    });

    test('点列替换（replacePoints 递增 revision）→ 指纹失效重建', () {
      final cache = StrokePictureCache();
      final stroke = _makeStroke([(0.0, 0.0), (10.0, 10.0)]);
      const size = ui.Size(100, 100);

      final p1 = cache.pictureFor([stroke], size: size);
      stroke.replacePoints(_pts([(0.0, 0.0), (5.0, 5.0), (20.0, 20.0)]));
      final p2 = cache.pictureFor([stroke], size: size);

      expect(identical(p1, p2), isFalse, reason: 'revision 变化应重建');
      expect(cache.cacheCount, 2);
      p1?.dispose();
      p2?.dispose();
    });

    test('尺寸变化 → 指纹失效重建', () {
      final cache = StrokePictureCache();
      final strokes = [_makeStroke([(0.0, 0.0), (10.0, 10.0)])];

      final p1 = cache.pictureFor(strokes, size: const ui.Size(100, 100));
      final p2 = cache.pictureFor(strokes, size: const ui.Size(200, 200));

      expect(identical(p1, p2), isFalse, reason: '尺寸变化应重建');
      p1?.dispose();
      p2?.dispose();
    });

    test('override 场景不缓存（语义等价旧路径）', () {
      final cache = StrokePictureCache();
      final strokes = [_makeStroke([(0.0, 0.0), (10.0, 10.0)])];
      const size = ui.Size(100, 100);

      final p1 = cache.pictureFor(
        strokes,
        size: size,
        colorOverride: const ui.Color(0xFFFF0000),
      );
      expect(cache.cacheCount, 0, reason: 'override 不缓存');
      p1?.dispose();
    });

    test('空笔画/空尺寸返回 null 不缓存', () {
      final cache = StrokePictureCache();
      expect(cache.pictureFor([], size: const ui.Size(100, 100)), isNull);
      expect(
        cache.pictureFor(
          [_makeStroke([(0.0, 0.0), (10.0, 10.0)])],
          size: ui.Size.zero,
        ),
        isNull,
      );
      expect(cache.cacheCount, 0);
    });

    test('LRU：超过 maxCacheCount 淘汰最久未用', () {
      final cache = StrokePictureCache(maxCacheCount: 2);
      const size = ui.Size(100, 100);
      final a = _makeStroke([(0.0, 0.0), (10.0, 10.0)]);
      final b = _makeStroke([(0.0, 0.0), (20.0, 20.0)]);
      final c = _makeStroke([(0.0, 0.0), (30.0, 30.0)]);

      final pa = cache.pictureFor([a], size: size);
      final pb = cache.pictureFor([b], size: size);
      cache.pictureFor([a], size: size); // 命中 a（LRU 提升到末尾）
      final pc = cache.pictureFor([c], size: size);

      expect(cache.cacheCount, 2, reason: '超过上限应淘汰最久未用');
      // 先验证 a 仍命中（插入 c 前 a 刚被提升，最久未用的是 b）。
      expect(identical(pa, cache.pictureFor([a], size: size)), isTrue);
      // 再验证 b 已被淘汰：再次取 b 应重建（新 Picture 对象）。
      final pb2 = cache.pictureFor([b], size: size);
      expect(identical(pb, pb2), isFalse, reason: 'b 已被淘汰，应重建');
      pa?.dispose();
      pb?.dispose();
      pc?.dispose();
      pb2?.dispose();
    });

    test('invalidate 清空缓存并释放', () {
      final cache = StrokePictureCache();
      final strokes = [_makeStroke([(0.0, 0.0), (10.0, 10.0)])];
      cache.pictureFor(strokes, size: const ui.Size(100, 100));
      expect(cache.cacheCount, 1);
      cache.invalidate();
      expect(cache.cacheCount, 0);
    });
  });
}
