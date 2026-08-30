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
}
