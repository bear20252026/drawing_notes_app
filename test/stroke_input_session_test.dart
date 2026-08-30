import 'dart:ui' show Color, Offset;

import 'package:drawing_notes_app/features/drawing/application/stroke_input_session.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('持久笔画会保留完整采样并在输入期间仅请求帧刷新', () async {
    final host = _StrokeInputHost(tool: BrushType.eraser);
    final session = StrokeInputSession(host);

    session.startStroke(const Offset(2, 3), pressure: 0.4);
    session.extendStroke(const Offset(8, 9), pressure: 0.8);

    expect(session.isDrawing, isTrue);
    expect(session.activeStroke!.color, const Color(0x00000000));
    expect(session.activeStroke!.points, hasLength(2));
    expect(host.requestedFrames, 2);

    await session.endStroke();

    expect(session.isDrawing, isFalse);
    expect(host.persistentStrokes, hasLength(1));
    final stroke = host.persistentStrokes.single;
    expect(stroke.points.first.offset, const Offset(2, 3));
    expect(stroke.points.first.pressure, 0.4);
    expect(stroke.points.last.offset, const Offset(8, 9));
    expect(stroke.points.last.pressure, 0.8);
    expect(host.temporaryMarkers, isEmpty);
    expect(host.temporaryLasers, isEmpty);
  });

  test('取消活动笔画不会提交持久化内容、临时内容或形状', () async {
    final host = _StrokeInputHost();
    final session = StrokeInputSession(host);

    session.startStroke(const Offset(1, 1));
    session.extendStroke(const Offset(4, 4));
    session.cancelActiveStroke();
    await session.endStroke();

    expect(session.activeStroke, isNull);
    expect(host.requestedFrames, 3);
    expect(host.persistentStrokes, isEmpty);
    expect(host.temporaryMarkers, isEmpty);
    expect(host.temporaryLasers, isEmpty);
    expect(host.recognizedShapes, isEmpty);
  });

  test('临时高亮和激光只交给临时宿主，不产生持久化提交', () async {
    final markerHost = _StrokeInputHost(
      tool: BrushType.marker,
      temporaryMarkerEnabled: true,
    );
    final markerSession = StrokeInputSession(markerHost);
    markerSession.startStroke(const Offset(0, 0));
    markerSession.extendStroke(const Offset(10, 0));
    await markerSession.endStroke();

    expect(markerHost.temporaryMarkers, hasLength(1));
    expect(markerHost.persistentStrokes, isEmpty);
    expect(markerHost.requestedFrames, 3);

    final laserHost = _StrokeInputHost(tool: BrushType.laser);
    final laserSession = StrokeInputSession(laserHost);
    laserSession.startStroke(const Offset(0, 0));
    laserSession.extendStroke(const Offset(10, 0));
    await laserSession.endStroke();

    expect(laserHost.temporaryLasers, hasLength(1));
    expect(laserHost.temporaryLasers.single.stroke.type, BrushType.laser);
    expect(laserHost.persistentStrokes, isEmpty);
    expect(laserHost.requestedFrames, 3);
  });
}

class _StrokeInputHost implements StrokeInputHost {
  _StrokeInputHost({
    this.tool = BrushType.pen,
    this.temporaryMarkerEnabled = false,
  });

  final BrushType tool;

  @override
  final bool temporaryMarkerEnabled;

  @override
  BrushType get strokeTool => tool;

  @override
  Color get strokeColor => const Color(0xFF2357AA);

  @override
  double get strokeSize => 6;

  final List<Stroke> persistentStrokes = <Stroke>[];
  final List<Stroke> temporaryMarkers = <Stroke>[];
  final List<({Stroke stroke, DateTime startedAt})> temporaryLasers =
      <({Stroke stroke, DateTime startedAt})>[];
  final List<({Stroke stroke, PageShapeItem shape})> recognizedShapes =
      <({Stroke stroke, PageShapeItem shape})>[];
  int requestedFrames = 0;

  @override
  void addTemporaryLaser(Stroke stroke, DateTime startedAt) {
    temporaryLasers.add((stroke: stroke, startedAt: startedAt));
  }

  @override
  void addTemporaryMarker(Stroke stroke) => temporaryMarkers.add(stroke);

  @override
  Future<void> commitPersistentStroke(Stroke stroke) async {
    persistentStrokes.add(stroke);
  }

  @override
  Future<void> commitRecognizedShape(Stroke stroke, PageShapeItem shape) async {
    recognizedShapes.add((stroke: stroke, shape: shape));
  }

  @override
  void requestFrame() => requestedFrames++;
}
