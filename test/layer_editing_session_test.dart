import 'dart:ui' show Color, Rect;

import 'package:drawing_notes_app/features/drawing/application/layer_editing_session.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Layer layer(String id, {List<Stroke> strokes = const <Stroke>[]}) =>
      Layer(id: id, name: id, strokes: strokes);

  test('会话独立编排图层结构、缓存协调与不可变快照边界', () {
    final host = _LayerEditingHost(
      DrawingDocument(
        id: 'layer_session',
        title: '图层编辑会话',
        infinite: true,
        layers: [layer('base')],
      ),
    );
    final session = LayerEditingSession(host);

    session.addLayer(name: 'top');
    final topId = host.document.layers.last.id;
    expect(host.document.layers.map((layer) => layer.name), ['base', 'top']);
    expect(host.currentLayerIndex, 1);
    expect(host.addedCacheLayerIds, [topId]);
    expect(host.snapshots, hasLength(1));
    expect(host.snapshots.single.before, hasLength(1));
    expect(host.snapshots.single.after, hasLength(2));
    // 通知计数（2026-10-04 加固：`changeNotifications` 原先自增却从不断言，
    // 而同文件的 `fullRebuilds` 有断言——属遗漏）。读码算值：addLayer 发
    // 恰好 1 次 `notifyChanged`（layer_editing_session.dart:77）。
    expect(
      host.changeNotifications,
      1,
      reason: 'addLayer 只发一次 UI 通知（快照 + 一次通知）',
    );

    // 换位走窄命令（2026-10-03）：不产生快照，只记 (from, to)。
    session.moveLayerDown(1);
    expect(host.document.layers.map((layer) => layer.id), [topId, 'base']);
    expect(host.currentLayerIndex, 0);
    expect(host.moves, hasLength(1));
    expect(host.moves.single, (from: 1, to: 0));
    expect(host.snapshots, hasLength(1), reason: '换位不产生快照');

    session.mergeLayerDown(1);
    expect(host.document.layers.map((layer) => layer.id), [topId]);
    expect(host.currentLayerIndex, 0);
    expect(host.removedCacheLayerIds, ['base']);
    expect(host.fullRebuilds, 1);
    // 快照 = 增层 + 合并（换位不再入快照）。
    expect(host.snapshots, hasLength(2));
    expect(host.snapshots.last.before.map((layer) => layer.id), [
      topId,
      'base',
    ]);
    expect(host.snapshots.last.after.map((layer) => layer.id), [topId]);
    // 总值锁死：addLayer(1) + moveLayerDown(1，:132) = 2；mergeLayerDown
    // 走 rebuildAll 而**不**发 notifyChanged(:148) ⇒ 仍为 2。多一发少一发都红。
    expect(
      host.changeNotifications,
      2,
      reason: '增层与换位各一次通知；向下合并不发通知（只 rebuildAll）',
    );
  });

  test('显隐切换走窄命令：翻转并记录 (索引, 前, 后)，不产生快照', () {
    final host = _LayerEditingHost(
      DrawingDocument(
        id: 'layer_visibility',
        title: '显隐窄命令',
        infinite: true,
        layers: [layer('base')],
      ),
    );
    final session = LayerEditingSession(host);

    session.toggleLayerVisibility(0);
    expect(host.document.layers[0].visible, isFalse);
    expect(host.visibilityChanges, hasLength(1));
    expect(host.visibilityChanges.single, (
      index: 0,
      before: true,
      after: false,
    ));
    expect(host.snapshots, isEmpty, reason: '显隐不产生快照');

    session.toggleLayerVisibility(0);
    expect(host.document.layers[0].visible, isTrue);
    expect(host.visibilityChanges.last, (index: 0, before: false, after: true));
    // 窄命令不产生快照，但每次翻转都必须刷 UI：2 次切换 = 2 次通知（:101）。
    expect(host.changeNotifications, 2, reason: '显隐切换各发一次通知——漏发即画面不更新，多发即重复重建');
  });

  test('局部和全量清空保留既有缓存刷新与无操作语义', () {
    final host = _LayerEditingHost(
      DrawingDocument(
        id: 'layer_clear',
        title: '图层清空',
        infinite: true,
        layers: [
          layer('base', strokes: [_stroke(10)]),
          layer('top', strokes: [_stroke(20)]),
        ],
      ),
      currentLayerIndex: 1,
    );
    final session = LayerEditingSession(host);

    session.clearCurrentLayer();
    expect(host.document.layers[1].strokes, isEmpty);
    expect(host.invalidatedLayerIds, ['top']);
    expect(host.snapshots, hasLength(1));
    expect(host.snapshots.single.before[1].strokes, hasLength(1));
    expect(host.snapshots.single.after[1].strokes, isEmpty);

    session.clearAll();
    expect(
      host.document.layers.every((layer) => layer.strokes.isEmpty),
      isTrue,
    );
    expect(host.fullRebuilds, 1);
    expect(host.snapshots, hasLength(2));

    session.clearAll();
    expect(host.fullRebuilds, 1);
    expect(host.snapshots, hasLength(2));

    session.setLayerOpacity(0, 1.5);
    expect(host.document.layers[0].opacity, 1.0);
    expect(host.snapshots, hasLength(2), reason: '透明度滑块不创建快照历史');
    // 通知计数锁死（读码算值）：clearCurrentLayer 只 invalidateLayer(:160)、
    // clearAll 只 rebuildAll(:176)、第二次 clearAll 空操作提前返回(:173)、
    // 仅 setLayerOpacity 发 1 次通知(:110) ⇒ 总计 1。
    expect(
      host.changeNotifications,
      1,
      reason: '清空走缓存失效/全量重建路径而不重复发通知；只有透明度变更发通知',
    );
  });
}

Stroke _stroke(double x) => Stroke(
  points: [StrokePoint(x, x, 1), StrokePoint(x + 1, x + 1, 1)],
  color: const Color(0xFF111111),
  width: 2,
  type: BrushType.pen,
);

class _LayerEditingHost implements LayerEditingHost {
  _LayerEditingHost(this.document, {this.currentLayerIndex = 0});

  @override
  final DrawingDocument document;

  @override
  int currentLayerIndex;
  final List<_LayerSnapshot> snapshots = <_LayerSnapshot>[];
  final List<({int from, int to})> moves = <({int from, int to})>[];
  final List<({int index, bool before, bool after})> visibilityChanges =
      <({int index, bool before, bool after})>[];
  final List<String> addedCacheLayerIds = <String>[];
  final List<String> removedCacheLayerIds = <String>[];
  final List<String> invalidatedLayerIds = <String>[];
  int changeNotifications = 0;
  int fullRebuilds = 0;

  @override
  Layer get currentLayer => document.layers[currentLayerIndex];

  @override
  void addLayerCache(Layer layer) => addedCacheLayerIds.add(layer.id);

  @override
  Future<void> invalidateLayer(String layerId, {Rect? region}) async {
    invalidatedLayerIds.add(layerId);
  }

  @override
  void notifyChanged() => changeNotifications++;

  @override
  void pushLayerSnapshot(List<Layer> before, List<Layer> after) {
    snapshots.add(_LayerSnapshot(before: before, after: after));
  }

  @override
  void pushLayerVisibility(int index, bool before, bool after) {
    visibilityChanges.add((index: index, before: before, after: after));
  }

  @override
  void pushLayerMove(int from, int to) {
    moves.add((from: from, to: to));
  }

  @override
  Future<void> rebuildAll() async {
    fullRebuilds++;
  }

  @override
  void removeLayerCache(String layerId) => removedCacheLayerIds.add(layerId);

  @override
  void setCurrentLayerIndexForLayerEdit(int value) {
    currentLayerIndex = value;
  }
}

class _LayerSnapshot {
  const _LayerSnapshot({required this.before, required this.after});

  final List<Layer> before;
  final List<Layer> after;
}
