import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drawing_notes_app/features/drawing/application/document_image_cache.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/wait_until.dart';

/// 真实引擎位图（`decodeImageFromPixels` 是异步的，须在 `runAsync` 内等待）。
/// 4×4 RGBA = 64 字节、8×8 = 256 字节，用于按字节预算构造比例模型。
Future<ui.Image> _pixelImage(int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List(width * height * 4),
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
    rowBytes: width * 4,
  );
  return completer.future;
}

DocumentImageItem _item(String id) => DocumentImageItem(
  id: id,
  filePath: 'img_$id.png',
  x: 0,
  y: 0,
  width: 100,
  height: 80,
);

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

  test('默认字节预算 48MiB（2026-09-24 内存优化 ①：96→48）', () {
    expect(DocumentImageCache.maxCacheBytesDefault, 48 << 20);
  });

  // 交接文档（2026-10-05）第一优先：超预算与失效边界。画布图片长边钳到
  // 4096 后单张 RGBA 仍可达 ~64MB，而预算 48MB——这些用例用小预算 +
  // 注入解码器把同一条边界做成可稳定复现的判据，不靠调大预算掩盖。
  group('超预算与失效边界（2026-10-05 交接第一优先）', () {
    testWidgets('单张超预算图片不自我淘汰：反复重绘只解码一次', (tester) async {
      var attempts = 0;
      final cache = DocumentImageCache(
        onImageAvailable: () {},
        isOwnerDisposed: () => false,
        // 8×8 RGBA=256 字节 > 预算 64 字节：单张就超预算的比例模型。
        maxCacheBytes: 64,
        decoder: (_) async {
          attempts++;
          return _pixelImage(8, 8);
        },
      );
      addTearDown(cache.dispose);

      await tester.runAsync(() async {
        cache.imageFor(_item('big'));
        await waitUntil(() => cache.isCached('big'));
        expect(
          cache.isCached('big'),
          isTrue,
          reason: '单张超预算时若把自己淘汰，imageFor 每帧都 miss、每帧重新解码',
        );
        for (var frame = 0; frame < 30; frame++) {
          expect(cache.imageFor(_item('big')), isNotNull);
        }
      });

      expect(attempts, 1, reason: '已驻留的图片被重绘不得再次触发解码');
    });

    testWidgets('两张以上仍受字节预算约束：淘汰最久未用、留住最近使用', (
      tester,
    ) async {
      final cache = DocumentImageCache(
        onImageAvailable: () {},
        isOwnerDisposed: () => false,
        // 4×4 RGBA=64 字节，预算 128 字节 → 恰好容两张。
        maxCacheBytes: 128,
        decoder: (_) => _pixelImage(4, 4),
      );
      addTearDown(cache.dispose);

      await tester.runAsync(() async {
        cache.imageFor(_item('a'));
        await waitUntil(() => cache.isCached('a'));
        cache.imageFor(_item('b'));
        await waitUntil(() => cache.isCached('b'));

        cache.imageFor(_item('a')); // 访问 a → a 成为最近使用，b 变最久未用
        cache.imageFor(_item('c'));
        await waitUntil(() => cache.isCached('c'));
      });

      expect(cache.isCached('a'), isTrue, reason: 'a 刚被访问，不应是淘汰对象');
      expect(cache.isCached('c'), isTrue);
      expect(cache.isCached('b'), isFalse, reason: 'b 是最久未用，必须被淘汰');
    });

    testWidgets('宿主销毁后返回的解码结果不写回缓存、不请求刷新', (
      tester,
    ) async {
      var ownerDisposed = false;
      var refreshes = 0;
      // ⚠️ 挂起中的解码句柄必须在 `runAsync` 的**真实异步区**里创建：
      // Completer 若在 testWidgets 的 FakeAsync 区构造、再从真实区 complete，
      // 续体会排进假时钟队列，没人泵就永远不回来（实测整条用例卡死到超时）。
      Completer<ui.Image>? completion;
      final cache = DocumentImageCache(
        onImageAvailable: () => refreshes++,
        isOwnerDisposed: () => ownerDisposed,
        decoder: (_) => (completion ??= Completer<ui.Image>()).future,
      );
      addTearDown(cache.dispose);

      await tester.runAsync(() async {
        final load = cache.ensureLoaded([_item('late')]);
        ownerDisposed = true; // 解码返回前宿主已销毁
        completion!.complete(await _pixelImage(4, 4));
        await load;
      });

      expect(cache.isCached('late'), isFalse, reason: '销毁后的结果不得进缓存');
      expect(refreshes, 0, reason: '销毁后不得再请求宿主刷新');
    });

    testWidgets('invalidate 作废在途旧解码，新内容不被旧结果覆盖', (
      tester,
    ) async {
      var attempts = 0;
      // 同上一条用例：挂起的解码只能在真实异步区内构造，否则 complete 之后
      // 续体落在 FakeAsync 队列里永不执行。
      Completer<ui.Image>? stale;
      final cache = DocumentImageCache(
        onImageAvailable: () {},
        isOwnerDisposed: () => false,
        maxCacheBytes: 1024,
        decoder: (_) async {
          attempts++;
          // 第 1 次=改写前的旧字节（晚返回）；第 2 次=改写后的新内容。
          if (attempts == 1) return (stale ??= Completer<ui.Image>()).future;
          return _pixelImage(4, 4);
        },
      );
      addTearDown(cache.dispose);

      await tester.runAsync(() async {
        cache.imageFor(_item('crop')); // 旧请求在途
        cache.invalidate('crop'); // 文件被裁剪重写
        await cache.ensureLoaded([_item('crop')]); // 按新内容重新解码
        expect(cache.isCached('crop'), isTrue);

        stale!.complete(await _pixelImage(16, 16)); // 旧结果此时才返回
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      });

      expect(attempts, 2, reason: 'invalidate 后进行中的旧任务不得继续占据任务位');
      final resident = cache.imageFor(_item('crop'));
      expect(
        resident?.width,
        4,
        reason: '驻留的必须是改写后的新位图，旧字节结果必须作废并释放',
      );
    });

    testWidgets('特征钉桩：ensureLoaded 完成 ≠ 整组图片同时驻留', (tester) async {
      final cache = DocumentImageCache(
        onImageAvailable: () {},
        isOwnerDisposed: () => false,
        maxCacheBytes: 64, // 只容一张 4×4（64 字节）
        decoder: (_) => _pixelImage(4, 4),
      );
      addTearDown(cache.dispose);

      await tester.runAsync(() async {
        await cache.ensureLoaded([_item('a'), _item('b'), _item('c')]);
        final resident = ['a', 'b', 'c'].where(cache.isCached).length;
        expect(
          resident,
          lessThan(3),
          reason: '整组 192 字节 > 预算：后载入的必然淘汰先载入的。'
              '导出/整册渲染不得把 ensureLoaded 当成「图一定在内存里」的保证，'
              '否则就是静默产出缺图的导出文件。',
        );
      });
    });
  });
}
