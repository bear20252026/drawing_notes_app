import 'dart:async';
import 'dart:ui' as ui;

import 'package:drawing_notes_app/features/drawing/application/document_image_cache.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final item = DocumentImageItem(
    id: 'image-1',
    filePath: '/missing/image.png',
    x: 0,
    y: 0,
    width: 100,
    height: 80,
  );

  test('同一图片的并发预载复用一个进行中的解码任务', () async {
    final completion = Completer<ui.Image>();
    var attempts = 0;
    var refreshes = 0;
    final cache = DocumentImageCache(
      onImageAvailable: () => refreshes++,
      isOwnerDisposed: () => false,
      decoder: (_) {
        attempts++;
        return completion.future;
      },
    );
    addTearDown(cache.dispose);

    final first = cache.ensureLoaded(<DocumentImageItem>[item]);
    final second = cache.ensureLoaded(<DocumentImageItem>[item]);

    expect(attempts, 1);
    completion.completeError(StateError('模拟损坏图片'));
    await Future.wait(<Future<void>>[first, second]);

    expect(refreshes, 0);
  });

  test('解码失败不会污染缓存，后续预载可重试', () async {
    var attempts = 0;
    final cache = DocumentImageCache(
      onImageAvailable: () {},
      isOwnerDisposed: () => false,
      decoder: (_) async {
        attempts++;
        throw StateError('模拟缺失图片');
      },
    );
    addTearDown(cache.dispose);

    await cache.ensureLoaded(<DocumentImageItem>[item]);
    await cache.ensureLoaded(<DocumentImageItem>[item]);

    expect(attempts, 2);
  });

  test('已销毁的缓存不再发起新的图片解码', () async {
    var attempts = 0;
    final cache = DocumentImageCache(
      onImageAvailable: () {},
      isOwnerDisposed: () => false,
      decoder: (_) async {
        attempts++;
        throw StateError('不应调用');
      },
    );
    cache.dispose();

    expect(cache.imageFor(item), isNull);
    await cache.ensureLoaded(<DocumentImageItem>[item]);

    expect(attempts, 0);
  });
}
