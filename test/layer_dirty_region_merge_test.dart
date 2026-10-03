import 'dart:ui' as ui;
import 'dart:ui' show Color, Rect;

import 'package:drawing_notes_app/features/drawing/application/layer_render_cache_coordinator.dart';
import 'package:drawing_notes_app/features/drawing/rendering/layer_compositor.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只记录「本次重建拿到哪个脏区」、不做真实合成的假合成器。
class _RecordingCompositor extends LayerCompositor {
  _RecordingCompositor();

  final List<Rect?> rebuiltRegions = <Rect?>[];

  @override
  Future<ui.Image> rasterize(
    Layer layer,
    int width,
    int height, {
    Rect? region,
    ui.Image? base,
  }) async {
    rebuiltRegions.add(region);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const Color(0xFF000000),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    picture.dispose();
    return image;
  }
}

/// 图层脏矩形待处理队列的合并语义回归（2026-10-03 复核 P-06）。
///
/// 成立依据：`invalidateLayer` 只做「标脏 + 记脏区 + 入队」，而
/// `_rebuildLayerNow` 要等队列轮到才取走脏区。同一轮事件循环里的两个
/// 擦除采样点（一个 PointerDataPacket 内多次 move 会连续派发）各自入队，
/// 后者在 `cache..dirtyRegion = region` 覆盖前者 → 只重建最后一处，
/// 前一处永久残影。
void main() {
  DrawingDocument buildDocument() => DrawingDocument(
    id: 'dirty-merge',
    title: '脏区并集',
    width: 200,
    height: 200,
    layers: <Layer>[
      Layer(
        id: 'layer_1',
        name: '图层 1',
        strokes: <Stroke>[
          Stroke(
            points: <StrokePoint>[
              const StrokePoint(10, 10, 1),
              const StrokePoint(60, 60, 1),
            ],
            color: const Color(0xFF000000),
            width: 2,
            type: BrushType.pen,
          ),
        ],
      ),
    ],
  );

  Future<({LayerRenderCacheCoordinator coordinator, _RecordingCompositor compositor})>
      openCoordinator() async {
    final document = buildDocument();
    final compositor = _RecordingCompositor();
    final coordinator = LayerRenderCacheCoordinator(
      document: document,
      onRenderUpdated: () {},
      isOwnerDisposed: () => false,
      compositor: compositor,
      idleReleaseDelay: Duration.zero,
    );
    addTearDown(coordinator.dispose);
    // 排空构造函数触发的首次整层重建，后续断言只看本用例的重建。
    await coordinator.invalidateLayer(document.layers.single.id);
    compositor.rebuiltRegions.clear();
    return (coordinator: coordinator, compositor: compositor);
  }

  test('同一轮事件循环内两个采样点的脏区取并集，前一处不被丢弃', () async {
    final opened = await openCoordinator();
    final coordinator = opened.coordinator;
    final compositor = opened.compositor;
    const first = Rect.fromLTRB(0, 0, 50, 50);
    const second = Rect.fromLTRB(100, 100, 150, 150);

    // 故意不逐条 await：模拟同一帧内两次擦除失效都排在未启动的重建任务之前。
    final pending = <Future<void>>[
      coordinator.invalidateLayer('layer_1', region: first),
      coordinator.invalidateLayer('layer_1', region: second),
    ];
    await Future.wait(pending);

    expect(compositor.rebuiltRegions, hasLength(1), reason: '待处理区已合并，无需二次重建');
    final rebuilt = compositor.rebuiltRegions.single;
    expect(rebuilt, isNotNull);
    expect(rebuilt!.left, lessThanOrEqualTo(first.left));
    expect(rebuilt.top, lessThanOrEqualTo(first.top));
    expect(rebuilt.right, greaterThanOrEqualTo(second.right));
    expect(rebuilt.bottom, greaterThanOrEqualTo(second.bottom));
  });

  test('待处理脏区存在时收到整层重建请求不得降级为局部矩形', () async {
    final opened = await openCoordinator();
    final coordinator = opened.coordinator;
    final compositor = opened.compositor;

    final pending = <Future<void>>[
      coordinator.invalidateLayer('layer_1', region: const Rect.fromLTRB(0, 0, 20, 20)),
      coordinator.invalidateLayer('layer_1'),
    ];
    await Future.wait(pending);

    expect(compositor.rebuiltRegions, contains(null), reason: 'null = 整层重建');
    expect(compositor.rebuiltRegions, hasLength(1));
  });

  test('逐采样点串行失效仍各自增量重建（P-06 性能设计不回退）', () async {
    final opened = await openCoordinator();
    final coordinator = opened.coordinator;
    final compositor = opened.compositor;
    const first = Rect.fromLTRB(0, 0, 50, 50);
    const second = Rect.fromLTRB(100, 100, 150, 150);

    await coordinator.invalidateLayer('layer_1', region: first);
    await coordinator.invalidateLayer('layer_1', region: second);

    expect(compositor.rebuiltRegions, <Rect?>[first, second], reason: '脏区不跨采样点合并');
  });
}
