import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 图层窄命令（显隐 / 相邻换位）的真控制器撤销重做覆盖（2026-10-03 复核）。
///
/// 锁的对象是 `LayerVisibilityCommand`/`LayerReorderCommand` 里的
/// `afterLayerUndoRedo()` 调用：它负责钳制 `_currentLayerIndex` 并
/// `notifyListeners`。被删掉时文档状态仍然正确（假上下文只累加计数、从不
/// expect），但图层面板与顶栏不会刷新（用户症状「撤销后 UI 不动」）。
void main() {
  DrawingController makeController() => DrawingController(
    DrawingDocument(
      id: 'layer-narrow-cmd',
      title: '图层窄命令',
      width: 200,
      height: 200,
      layers: <Layer>[Layer(id: 'layer_1', name: '图层 1')],
    ),
  );

  List<String> layerIds(DrawingController c) =>
      c.document.layers.map((layer) => layer.id).toList();

  test('图层显隐撤销/重做：状态还原且每次都通知监听者', () {
    final c = makeController();
    addTearDown(c.dispose);
    c.addLayer();
    final target = c.document.layers[1];

    var notifications = 0;
    c.addListener(() => notifications++);

    c.toggleLayerVisibility(1);
    expect(target.visible, isFalse);

    notifications = 0;
    c.undo();
    expect(target.visible, isTrue, reason: '撤销应还原显隐');
    expect(notifications, 1, reason: 'afterLayerUndoRedo 必须通知一次');

    notifications = 0;
    c.redo();
    expect(target.visible, isFalse);
    expect(notifications, 1, reason: '重做同样必须通知一次');

    expect(c.currentLayerIndex, lessThan(c.document.layers.length));
  });

  test('图层换位撤销/重做：z 序还原且每次都通知监听者', () {
    final c = makeController();
    addTearDown(c.dispose);
    c.addLayer();
    c.addLayer();
    final original = layerIds(c);
    expect(original, hasLength(3));
    final moved = <String>[original[0], original[2], original[1]];

    var notifications = 0;
    c.addListener(() => notifications++);

    c.moveLayerDown(2);
    expect(layerIds(c), moved);

    notifications = 0;
    c.undo();
    expect(layerIds(c), original, reason: '撤销还原原始叠色次序');
    expect(notifications, 1);

    notifications = 0;
    c.redo();
    expect(layerIds(c), moved);
    expect(notifications, 1);

    expect(c.currentLayerIndex, lessThan(c.document.layers.length));
  });

  test('显隐与换位各占一条历史：撤销不串味', () {
    final c = makeController();
    addTearDown(c.dispose);
    c.addLayer();
    c.addLayer();
    final original = layerIds(c);

    c.toggleLayerVisibility(2);
    c.moveLayerDown(2);
    expect(c.document.layers[1].visible, isFalse, reason: '被隐藏的层已下移一位');

    c.undo();
    expect(layerIds(c), original, reason: '只撤销换位');
    expect(c.document.layers[2].visible, isFalse, reason: '显隐仍是切换后的状态');

    c.undo();
    expect(c.document.layers[2].visible, isTrue);
    expect(layerIds(c), original);

    c.redo();
    c.redo();
    expect(layerIds(c), <String>[original[0], original[2], original[1]]);
    expect(c.document.layers[1].visible, isFalse);
  });

  test('换位撤销后当前图层索引仍被钳制在合法范围', () {
    final c = makeController();
    addTearDown(c.dispose);
    c.addLayer();
    c.currentLayerIndex = 1;
    final original = layerIds(c);

    c.moveLayerDown(1);
    expect(c.currentLayerIndex, 0);
    expect(layerIds(c), <String>[original[1], original[0]]);

    c.undo();
    expect(layerIds(c), original, reason: '换位撤销还原 z 序');
    expect(c.currentLayerIndex, lessThan(c.document.layers.length));
  });
}
