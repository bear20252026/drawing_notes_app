import 'dart:math' as math;
import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 选区几何计算服务（Q-1 God Class 拆分 2026-08-16——最小落地）。
///
/// Flutter 官方架构指南："Refactor one screen at a time，不整体重写"——
/// 从 DrawingController 提取纯计算职责为独立服务类（Services 最底层、
/// thin、无状态）。选区中心/外接框计算与 controller 状态解耦——可独立
/// 单测；controller 保留缓存与状态编排（交互编排留 State）。
class SelectionGeometryService {
  const SelectionGeometryService();

  /// 计算一组笔画的外接框中心（遍历所有采样点——O(N×M)）。
  /// 无有效点返回 null（调用方决定回退到选区自身中心）。
  static Offset? centerOfStrokes(Iterable<Stroke> strokes) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final stroke in strokes) {
      for (final point in stroke.points) {
        minX = minX < point.x ? minX : point.x;
        minY = minY < point.y ? minY : point.y;
        maxX = maxX > point.x ? maxX : point.x;
        maxY = maxY > point.y ? maxY : point.y;
      }
    }
    if (!minX.isFinite) return null;
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  /// 线段相交判定（Q-1 拆分 2026-08-16——第七步）：[ab] 与 [cd] 是否相交
  /// （含共线重叠）。从 DrawingController 提取——纯几何判定——可独立单测。
  static bool segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    final abC = _cross(a, b, c);
    final abD = _cross(a, b, d);
    final cdA = _cross(c, d, a);
    final cdB = _cross(c, d, b);
    const epsilon = 1e-8;
    if (abC.abs() < epsilon && abD.abs() < epsilon) {
      final overlapX =
          math.max(math.min(a.dx, b.dx), math.min(c.dx, d.dx)) <=
          math.min(math.max(a.dx, b.dx), math.max(c.dx, d.dx));
      final overlapY =
          math.max(math.min(a.dy, b.dy), math.min(c.dy, d.dy)) <=
          math.min(math.max(a.dy, b.dy), math.max(c.dy, d.dy));
      return overlapX && overlapY;
    }
    return (abC >= 0) != (abD >= 0) && (cdA >= 0) != (cdB >= 0);
  }

  /// 射线法判断 [point] 是否位于 [polygon] 内部。
  static bool pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (
      var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++
    ) {
      final a = polygon[index];
      final b = polygon[previous];
      final intersects =
          (a.dy > point.dy) != (b.dy > point.dy) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (intersects) inside = !inside;
    }
    return inside;
  }

  /// 判断一条笔画是否有采样点落在选区内，或任一线段穿越选区边界。
  static bool strokeIntersectsPolygon(
    List<StrokePoint> points,
    List<Offset> polygon,
  ) {
    if (points.any((point) => pointInPolygon(point.offset, polygon))) {
      return true;
    }
    if (points.length < 2 || polygon.length < 3) return false;
    for (var index = 1; index < points.length; index++) {
      final start = points[index - 1].offset;
      final end = points[index].offset;
      for (var edge = 0; edge < polygon.length; edge++) {
        final boundaryStart = polygon[edge];
        final boundaryEnd = polygon[(edge + 1) % polygon.length];
        if (segmentsIntersect(start, end, boundaryStart, boundaryEnd)) {
          return true;
        }
      }
    }
    return false;
  }

  static double _cross(Offset o, Offset p, Offset q) =>
      (p.dx - o.dx) * (q.dy - o.dy) - (p.dy - o.dy) * (q.dx - o.dx);

  /// 点到线段距离（Q-1 拆分 2026-08-16——第八步）：点 [point] 到线段
  /// [ab] 的最短距离（投影 t + clamp 0-1——权威算法，对齐 tldraw
  /// DistanceToLineSegment parametric t-projection 与掘金投影公式）。
  static double distanceToSegment(Offset point, Offset a, Offset b) {
    final segment = b - a;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    if (lengthSquared <= 1e-8) return (point - a).distance;
    final projected =
        ((point - a).dx * segment.dx + (point - a).dy * segment.dy) /
        lengthSquared;
    final t = projected.clamp(0.0, 1.0);
    return (point - (a + segment * t)).distance;
  }

  /// 缩放变换（纯计算）：点 [p] 围绕 [center] 缩放 [factor] 倍。
  static Offset scalePoint(Offset p, Offset center, double factor) =>
      center + (p - center) * factor;

  /// 旋转变换（纯计算）：点 [p] 围绕 [center] 旋转（cosA/sinA 由调用方
  /// 预先计算——避免每点重复三角函数）。
  static Offset rotatePoint(Offset p, Offset center, double cosA, double sinA) {
    final dx = p.dx - center.dx;
    final dy = p.dy - center.dy;
    return Offset(
      center.dx + dx * cosA - dy * sinA,
      center.dy + dx * sinA + dy * cosA,
    );
  }
}
