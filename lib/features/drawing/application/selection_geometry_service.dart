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
}
