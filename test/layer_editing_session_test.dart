import 'dart:ui' show Color, Rect;

import 'package:drawing_notes_app/features/drawing/application/layer_editing_session.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
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

    session.moveLayerDown(1);
    expect(host.document.layers.map((layer) => layer.id), [topId, 'base']);
    expect(host.currentLayerIndex, 0);
    expect(host.snapshots, hasLength(2));

    session.mergeLayerDown(1);
    expect(host.document.layers.map((layer) => layer.id), [topId]);
    expect(host.currentLayerIndex, 0);
    expect(host.removedCacheLayerIds, ['base']);
    expect(host.fullRebuilds, 1);
    expect(host.snapshots, hasLength(3));
    expect(host.snapshots.last.before.map((layer) => layer.id), [
      topId,
      'base',
    ]);
    expect(host.snapshots.last.after.map((layer) => layer.id), [topId]);
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
