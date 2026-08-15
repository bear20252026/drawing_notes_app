import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/features/drawing/application/selection_geometry_service.dart';

/// Q-1 God Class 拆分（2026-08-16）：SelectionGeometryService 纯计算
/// 服务——选区中心与外接框计算独立单测（从 controller 解耦）。
void main() {
  test('选区中心：多点外接框中心', () {
    final strokes = [
      Stroke(
        points: [const StrokePoint(0, 0, 0.5), const StrokePoint(10, 0, 0.5)],
        color: const Color(0xFF000000),
        width: 2,
        type: BrushType.pen,
      ),
      Stroke(
        points: [const StrokePoint(0, 20, 0.5), const StrokePoint(10, 20, 0.5)],
        color: const Color(0xFF000000),
        width: 2,
        type: BrushType.pen,
      ),
    ];
    final center = SelectionGeometryService.centerOfStrokes(strokes);
    expect(center, const Offset(5, 10));
  });

  test('选区中心：空笔画返回 null（调用方回退）', () {
    expect(SelectionGeometryService.centerOfStrokes(const []), isNull);
  });

  test('选区中心：单点返回该点', () {
    final strokes = [
      Stroke(
        points: const [StrokePoint(7, 9, 0.5)],
        color: const Color(0xFF000000),
        width: 2,
        type: BrushType.pen,
      ),
    ];
    expect(SelectionGeometryService.centerOfStrokes(strokes), const Offset(7, 9));
  });
}
