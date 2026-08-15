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

  test('变换：缩放点围绕中心', () {
    expect(
      SelectionGeometryService.scalePoint(
        const Offset(10, 10),
        const Offset(0, 0),
        2,
      ),
      const Offset(20, 20),
    );
    expect(
      SelectionGeometryService.scalePoint(
        const Offset(10, 0),
        const Offset(5, 0),
        0.5,
      ),
      const Offset(7.5, 0),
    );
  });

  test('变换：旋转点围绕中心（90°）', () {
    // cos(π/2)=0, sin(π/2)=1——(10,0) 绕 (0,0) 旋转 90° → (0,10)。
    final rotated = SelectionGeometryService.rotatePoint(
      const Offset(10, 0),
      const Offset(0, 0),
      0,
      1,
    );
    expect(rotated.dx, closeTo(0, 1e-9));
    expect(rotated.dy, closeTo(10, 1e-9));
  });

  test('几何：线段相交判定（含共线重叠）', () {
    // 相交：对角线交叉。
    expect(
      SelectionGeometryService.segmentsIntersect(
        const Offset(0, 0),
        const Offset(10, 10),
        const Offset(0, 10),
        const Offset(10, 0),
      ),
      isTrue,
    );
    // 不相交：平行线段。
    expect(
      SelectionGeometryService.segmentsIntersect(
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(0, 5),
        const Offset(10, 5),
      ),
      isFalse,
    );
    // 共线重叠。
    expect(
      SelectionGeometryService.segmentsIntersect(
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(5, 0),
        const Offset(15, 0),
      ),
      isTrue,
    );
  });

  test('几何：点到线段距离（投影 t + clamp）', () {
    // 垂足在线段内：点 (5,5) 到 (0,0)-(10,0) → 5。
    expect(
      SelectionGeometryService.distanceToSegment(
        const Offset(5, 5),
        const Offset(0, 0),
        const Offset(10, 0),
      ),
      closeTo(5, 1e-9),
    );
    // 投影在段外：点 (15,5) → 端点 (10,0) 距离 √(25+25)。
    expect(
      SelectionGeometryService.distanceToSegment(
        const Offset(15, 5),
        const Offset(0, 0),
        const Offset(10, 0),
      ),
      closeTo(7.0710678119, 1e-6),
    );
    // 零长度段：退化为点到端点距离。
    expect(
      SelectionGeometryService.distanceToSegment(
        const Offset(3, 4),
        const Offset(0, 0),
        const Offset(0, 0),
      ),
      closeTo(5, 1e-9),
    );
  });
}
