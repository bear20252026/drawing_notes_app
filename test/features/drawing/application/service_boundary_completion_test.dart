import 'dart:async';
import 'dart:ui';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/services/layer_service.dart';
import 'package:drawing_notes_app/features/drawing/application/services/stroke_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stroke preparation receives the point before starting and stops after disposal', () {
    final events = <String>[];
    const point = Offset(10, 20);
    final service = StrokeService(
      onPrepare: (value) {
        expect(value, point);
        events.add('prepare');
      },
      onStart: (value, {pressure = 1}) {
        expect(value, point);
        expect(pressure, 0.5);
        events.add('start');
      },
    );
    service.startStroke(point, pressure: 0.5);
    expect(events, ['prepare', 'start']);
    service.dispose();
    service.prepareStroke(point);
    service.startStroke(point);
    expect(events, ['prepare', 'start']);
  });

  test(
    'layer invalidation forwards bounds and waits for the renderer',
    () async {
      final service = LayerService();
      final completion = Completer<void>();
      final bounds = Rect.fromLTWH(1, 2, 3, 4);
      service.bindLegacyOperations(
        createLayer: ({name}) {},
        deleteLayer: (_) {},
        invalidate: (id, {region}) {
          expect(id, 'layer');
          expect(region, bounds);
          return completion.future;
        },
      );
      var finished = false;
      final pending = service.invalidate('layer', region: bounds).then((_) {
        finished = true;
      });
      await Future<void>.value();
      expect(finished, isFalse);
      completion.complete();
      await pending;
      expect(finished, isTrue);
      service.dispose();
      await service.invalidate('ignored');
    },
  );

  test('unbound layer operations report their missing host', () async {
    final service = LayerService();
    expect(service.invalidate('layer'), throwsStateError);
    expect(() => service.reorderLayer('layer', 1), throwsStateError);
    service.dispose();
    service.reorderLayer('layer', 1);
    await service.invalidate('layer');
  });

  test(
    'layer reorder settles a pending transform and undoes in the correct order',
    () {
      final c = DrawingController(
        DrawingDocument(
          id: 'reorder',
          title: 'reorder',
          width: 200,
          height: 200,
        ),
      );
      addTearDown(c.dispose);
      c.addLayer(name: 'middle');
      c.addLayer(name: 'top');
      c.currentLayerIndex = 0;
      final id = c.currentLayer.id;
      final before = c.document.layers.map((layer) => layer.id).toList();
      c.currentLayer.strokes.add(
        Stroke(
          points: [StrokePoint(10, 10, 1), StrokePoint(20, 10, 1)],
          color: const Color(0xFF112233),
          width: 2,
          type: BrushType.pen,
        ),
      );
      c.selectionTool = SelectionTool.rect;
      c.beginSelection(Offset.zero);
      c.extendSelection(const Offset(50, 50));
      c.endSelection();
      c.moveSelectedStrokes(const Offset(5, 0));
      final count = c.historyService.entryCount;
      c.layerService.reorderLayer(id, 2);
      expect(c.document.layers.map((layer) => layer.id), [
        before[1],
        before[2],
        id,
      ]);
      expect(c.historyService.entryCount, count + 2);
      c.undo();
      expect(c.document.layers.map((layer) => layer.id), before);
      expect(c.document.layers.first.strokes.single.points.first.x, 15);
      c.undo();
      expect(c.document.layers.first.strokes.single.points.first.x, 10);
      c.redo();
      c.redo();
      expect(c.document.layers.last.id, id);
      expect(c.document.layers.last.strokes.single.points.first.x, 15);
      final after = c.historyService.entryCount;
      c.layerService.reorderLayer(id, 2);
      expect(c.historyService.entryCount, after);
      expect(() => c.layerService.reorderLayer(id, -1), throwsRangeError);
      expect(
        () => c.layerService.reorderLayer('missing', 0),
        throwsArgumentError,
      );
      expect(c.historyService.entryCount, after);
    },
  );
}
