import 'dart:ui' show Color, Offset;

import 'package:drawing_notes_app/features/drawing/application/drawing_selection_session.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连续笔画变换以实际内容中心执行且只提交一个快照', () {
    final selectionSession = DrawingSelectionSession()
      ..completeDraft(
        const Selection(
          polygon: <Offset>[
            Offset(-100, -100),
            Offset(100, -100),
            Offset(100, 100),
          ],
          selectedStrokeIndices: <int>[0],
        ),
      );
    final host = _StrokeSelectionHost(
      _documentWithStrokes(<Stroke>[_stroke(0, 10)]),
      selectionSession,
    );
    final session = StrokeSelectionEditingSession(host);

    session.scaleSelectedStrokes(2);
    session.moveSelectedStrokes(const Offset(5, 4));
    session.endTransform();

    final points = host.currentLayer.strokes.single.points;
    expect(points.first.offset, const Offset(0, 4));
    expect(points.last.offset, const Offset(20, 4));
    expect(host.snapshots, hasLength(1));
    expect(
      host.snapshots.single.before.single.strokes.single.points.first.offset,
      const Offset(0, 0),
    );
    expect(
      host.snapshots.single.after.single.strokes.single.points.last.offset,
      const Offset(20, 4),
    );
    expect(host.invalidatedLayerIds, ['base', 'base']);
    expect(host.changeNotifications, 2);

    session.endTransform();
    expect(host.snapshots, hasLength(1), reason: '没有新变换时不能产生空历史记录');
  });

  test('会话复制、粘贴和删除只修改选中笔画并保持快照边界', () {
    final selectionSession = DrawingSelectionSession()
      ..completeDraft(
        const Selection(
          polygon: <Offset>[Offset(0, 0), Offset(20, 0), Offset(20, 20)],
          selectedStrokeIndices: <int>[0],
        ),
      );
    final host = _StrokeSelectionHost(
      _documentWithStrokes(<Stroke>[_stroke(1, 3), _stroke(40, 42)]),
      selectionSession,
    );
    final session = StrokeSelectionEditingSession(host);

    session.copySelectedStrokes();
    session.pasteClipboard();

    expect(host.currentLayer.strokes, hasLength(3));
    expect(
      host.currentLayer.strokes.last.points.first.offset,
      const Offset(21, 21),
    );
    expect(selectionSession.hasSelectedStrokes, isFalse);
    expect(host.snapshots, hasLength(1));
    expect(host.snapshots.single.before.single.strokes, hasLength(2));
    expect(host.snapshots.single.after.single.strokes, hasLength(3));

    selectionSession.completeDraft(
      const Selection(
        polygon: <Offset>[Offset(0, 0), Offset(20, 0), Offset(20, 20)],
        selectedStrokeIndices: <int>[1, 2],
      ),
    );
    session.deleteSelectedStrokes();

    expect(host.currentLayer.strokes, hasLength(1));
    expect(
      host.currentLayer.strokes.single.points.first.offset,
      const Offset(1, 1),
    );
    expect(selectionSession.hasSelectedStrokes, isFalse);
    expect(host.snapshots, hasLength(2));
    expect(host.snapshots.last.before.single.strokes, hasLength(3));
    expect(host.snapshots.last.after.single.strokes, hasLength(1));
  });
}

DrawingDocument _documentWithStrokes(List<Stroke> strokes) => DrawingDocument(
  id: 'stroke_selection',
  title: '笔画选区编辑',
  infinite: true,
  layers: <Layer>[Layer(id: 'base', name: 'base', strokes: strokes)],
);

Stroke _stroke(double from, double to) => Stroke(
  points: <StrokePoint>[StrokePoint(from, from, 1), StrokePoint(to, from, 1)],
  color: const Color(0xFF111111),
  width: 2,
  type: BrushType.pen,
);

class _StrokeSelectionHost implements StrokeSelectionEditingHost {
  _StrokeSelectionHost(this.document, this.selectionSession);

  @override
  final DrawingDocument document;

  @override
  final DrawingSelectionSession selectionSession;

  final List<_LayerSnapshot> snapshots = <_LayerSnapshot>[];
  final List<String> invalidatedLayerIds = <String>[];
  int changeNotifications = 0;

  @override
  Layer get currentLayer => document.layers.single;

  @override
  Future<void> invalidateLayer(String layerId) async {
    invalidatedLayerIds.add(layerId);
  }

  @override
  void notifyChanged() => changeNotifications++;

  @override
  void pushLayerSnapshot(List<Layer> before, List<Layer> after) {
    snapshots.add(_LayerSnapshot(before: before, after: after));
  }
}

class _LayerSnapshot {
  const _LayerSnapshot({required this.before, required this.after});

  final List<Layer> before;
  final List<Layer> after;
}
