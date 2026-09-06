// P0 内存修复回归（2026-09-06 外部专家审计 #2/#3）。
//
// - StrokePictureCache：LRU 淘汰后缓存条数保持有界（淘汰必 dispose 原生
//   Picture，长期绘制不再累积）。
// - DocumentImageCache：超字节预算时按最久未用淘汰并释放，缓存不再无上限
//   增长（多图笔记不再累积到几百 MB）。

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/application/document_image_cache.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_picture_cache.dart';

Stroke _stroke(int seed) => Stroke(
  points: [
    StrokePoint(seed * 10, 20, 0.5),
    StrokePoint(seed * 10 + 60, 90, 0.9),
  ],
  color: const ui.Color(0xFF000000),
  width: 6,
  type: BrushType.pen,
);

Future<ui.Image> _pixelImage(int width, int height) {
  final pixels = Uint8List(width * height * 4);
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    (image) => completer.complete(image),
    rowBytes: width * 4,
  );
  return completer.future;
}

void main() {
  group('StrokePictureCache：LRU 淘汰后条数有界（P0 #3）', () {
    test('超过 maxCacheCount 后条数不再增长（淘汰不泄漏）', () {
      final cache = StrokePictureCache(maxCacheCount: 4);
      // 反复提交不同的笔画集合 → 指纹各异 → 触发多次重建与淘汰。
      for (var i = 0; i < 40; i++) {
        cache.pictureFor([
          _stroke(i),
          _stroke(i + 1),
        ], size: const ui.Size(800, 600));
      }
      expect(cache.cacheCount, 4, reason: '缓存条数必须被 LRU 上限约束');

      cache.invalidate();
      expect(cache.cacheCount, 0);
    });
  });

  testWidgets('DocumentImageCache：超字节预算按最久未用淘汰（P0 #2）', (tester) async {
    late DocumentImageCache cache;
    // 4×4 RGBA = 64 字节；预算 64 → 只容 1 张，超过即淘汰最久未用。
    cache = DocumentImageCache(
      onImageAvailable: () {},
      isOwnerDisposed: () => false,
      maxCacheBytes: 64,
      decoder: (path) => _pixelImage(4, 4),
    );
    addTearDown(cache.dispose);

    DocumentImageItem item(String id) => DocumentImageItem(
      id: id,
      filePath: 'img_$id.png',
      x: 0,
      y: 0,
      width: 100,
      height: 100,
    );

    final a = item('a');
    final b = item('b');

    // decodeImageFromPixels 是真实引擎异步，须在 runAsync 内等待真实完成。
    await tester.runAsync(() async {
      // 载入 a → 保留。
      cache.imageFor(a);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cache.imageFor(a), isNotNull, reason: 'a 应已解码');

      // 载入 b → a 是最久未用且总字节超预算，应被 LRU 淘汰。
      cache.imageFor(b);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cache.imageFor(b), isNotNull, reason: 'b 应已解码');
      expect(cache.imageFor(a), isNull, reason: 'a 应被 LRU 淘汰并释放');
    });

    // 淘汰的 a 会再触发异步重新加载（budget 内只有它，按需重新解码）。
    await tester.runAsync(() async {
      cache.imageFor(a);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cache.imageFor(a), isNotNull, reason: 'a 被淘汰后按需重新解码');
    });
  });
}
