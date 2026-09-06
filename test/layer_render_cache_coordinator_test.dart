import 'package:drawing_notes_app/features/drawing/application/layer_render_cache_coordinator.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('缓存协调器随图层增删提供对应的只读绘制视图', () {
    final document = DrawingDocument(id: 'doc-1', title: '缓存测试');
    final coordinator = LayerRenderCacheCoordinator(
      document: document,
      onRenderUpdated: () {},
      isOwnerDisposed: () => false,
    );
    addTearDown(coordinator.dispose);

    expect(coordinator.paintViews, hasLength(1));
    expect(coordinator.paintViews.single.visible, isTrue);

    final secondLayer = Layer(id: 'layer-2', name: '图层 2', opacity: 0.4);
    document.layers.add(secondLayer);
    coordinator.addLayer(secondLayer);

    expect(coordinator.paintViews, hasLength(2));
    expect(coordinator.paintViews.last.opacity, 0.4);

    document.layers.remove(secondLayer);
    coordinator.removeLayer(secondLayer.id);

    expect(coordinator.paintViews, hasLength(1));
  });

  test('无限画布失效只通知刷新，释放后不再调用宿主', () async {
    final document = DrawingDocument(
      id: 'doc-infinite',
      title: '无限画布缓存测试',
      infinite: true,
    );
    var refreshes = 0;
    final coordinator = LayerRenderCacheCoordinator(
      document: document,
      onRenderUpdated: () => refreshes++,
      isOwnerDisposed: () => false,
    );

    await coordinator.invalidateLayer(document.layers.single.id);
    expect(refreshes, 1);

    coordinator.dispose();
    await coordinator.invalidateLayer(document.layers.single.id);
    expect(refreshes, 1);
  });

  test('后台释放图层位图后 paintViews 位图置空，可懒重建（P1 #1）', () async {
    final document = DrawingDocument(id: 'doc-a4', title: '分页');
    final coordinator = LayerRenderCacheCoordinator(
      document: document,
      onRenderUpdated: () {},
      isOwnerDisposed: () => false,
    );
    addTearDown(coordinator.dispose);
    // 触发一次位图生成（非无限画布 → 真实光栅化到 paintViews.image）。
    await coordinator.invalidateLayer(document.layers.single.id);
    expect(
      coordinator.paintViews.single.image,
      isNotNull,
      reason: '绘画后图层位图应已生成',
    );

    // App 后台：释放所有位图（image 置空、标脏），保留缓存索引。
    coordinator.releaseForBackground();
    expect(
      coordinator.paintViews.single.image,
      isNull,
      reason: '后台释放后图层位图应置空，空载不再常驻大图',
    );
    expect(coordinator.paintViews, hasLength(1), reason: '缓存索引保留');

    // 回前台：懒重建，位图重新生成。
    await coordinator.rebuildAll();
    expect(
      coordinator.paintViews.single.image,
      isNotNull,
      reason: '回前台重建后位图应重新生成',
    );
  });
}
