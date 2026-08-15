import 'dart:ui' as ui;

import 'package:drawing_notes_app/core/rendering/ink_layer_painter.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke _stroke({
  required BrushType type,
  required ui.Color color,
  required double width,
  required List<StrokePoint> points,
}) => Stroke(points: points, color: color, width: width, type: type);

void main() {
  final yellowMarker = _stroke(
    type: BrushType.marker,
    color: const ui.Color(0xFFFFD54F),
    width: 24,
    points: const [StrokePoint(20, 60, 0.1), StrokePoint(100, 60, 0.9)],
  );
  final greenMarker = _stroke(
    type: BrushType.marker,
    color: const ui.Color(0xFF81C784),
    width: 24,
    points: const [StrokePoint(20, 40, 0.2), StrokePoint(100, 40, 0.8)],
  );
  final blackPen = _stroke(
    type: BrushType.pen,
    color: const ui.Color(0xFF000000),
    width: 6,
    points: const [StrokePoint(60, 20, 1), StrokePoint(60, 100, 1)],
  );

  test('同色高亮笔归入同一局部合成组', () {
    final plan = InkRenderPlan.fromStrokes([yellowMarker, yellowMarker]);

    expect(plan.markerGroups, hasLength(1));
    expect(plan.markerGroups.single, hasLength(2));
    expect(plan.normalStrokes, isEmpty);
  });

  test('不同色高亮笔分组，普通墨迹始终位于高亮之后', () {
    final plan = InkRenderPlan.fromStrokes([
      yellowMarker,
      blackPen,
      greenMarker,
    ]);

    expect(plan.markerGroups, hasLength(2));
    expect(plan.normalStrokes, [blackPen]);
  });

  test('高亮笔绘制计划可写入 PictureRecorder', () {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const bounds = ui.Rect.fromLTWH(0, 0, 120, 120);

    expect(
      () => InkLayerPainter.paintStrokes(canvas, bounds, [
        yellowMarker,
        blackPen,
      ]),
      returnsNormally,
    );
    recorder.endRecording().dispose();
  });
}
