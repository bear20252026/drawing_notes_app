import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/application/temporary_ink_session.dart';
import 'package:drawing_notes_app/features/drawing/application/temporary_markers.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Stroke makeStroke(BrushType type) => Stroke(
    points: <StrokePoint>[
      const StrokePoint(0, 0, 1),
      const StrokePoint(40, 10, 1),
      const StrokePoint(80, 20, 1),
    ],
    color: const Color(0xFF1A1A1A),
    width: 6,
    type: type,
  );

  test('临时高亮按会话时钟投影并在生命周期结束后清理', () {
    var now = DateTime.utc(2026, 8, 27, 3, 0);
    final session = TemporaryInkSession(onFrameTick: () {}, clock: () => now);
    addTearDown(session.dispose);

    session.addMarker(makeStroke(BrushType.marker));

    expect(session.markerStrokes, hasLength(1));
    expect(session.markerStrokes.single.opacity, closeTo(1, 0.0001));

    now = now.add(temporaryMarkerLifetime);

    expect(session.markerStrokes, isEmpty);
  });

  test('激光尾迹按会话时钟推进首点并在最终淡出后清理', () {
    var now = DateTime.utc(2026, 8, 27, 3, 0);
    final session = TemporaryInkSession(onFrameTick: () {}, clock: () => now);
    addTearDown(session.dispose);

    session.addLaser(makeStroke(BrushType.laser), now);

    expect(session.laserStrokes.single.firstPointIndex, 0);
    now = now.add(laserHoldDuration + const Duration(milliseconds: 900));
    expect(session.laserStrokes.single.firstPointIndex, greaterThan(0));

    now = now.add(laserSweepDuration + laserFinalFadeDuration);
    expect(session.laserStrokes, isEmpty);
  });
}
