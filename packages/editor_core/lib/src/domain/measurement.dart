// editor_core——MeasurementTool 距离测量（Excalidraw 借鉴——2026-08-21）。
//
// Excalidraw Measurement 本地化——距离/角度/面积测量工具。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - 测量工具（距离/角度/面积——精确绘制辅助）
// - 测量线（起点/终点/标注——可显示在画布上）
library;

import 'dart:math' as math;

/// 测量类型（Excalidraw Measurement 借鉴）。
enum MeasurementType {
  /// 距离（两点间直线距离）。
  distance,

  /// 角度（两条线间夹角）。
  angle,

  /// 面积（多边形面积）。
  area,
}

/// 测量标注（Excalidraw Measurement 本地化——不可变）。
///
/// 存储测量结果——可显示在画布上（标注文本 + 位置）。
class MeasurementLabel {
  const MeasurementLabel({
    required this.text,
    required this.x,
    required this.y,
    this.color = '#FF0000',
    this.fontSize = 12,
  });

  final String text;
  final double x;
  final double y;
  final String color;
  final int fontSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeasurementLabel && text == other.text && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(text, x, y);
}

/// 测量结果（Excalidraw Measurement 本地化——不可变）。
///
/// 包含测量类型 + 数值 + 标注 + 原始坐标。
class MeasurementResult {
  const MeasurementResult({
    required this.type,
    required this.value,
    required this.unit,
    this.label,
    this.points = const [],
  });

  final MeasurementType type;
  final double value;
  final String unit;
  final MeasurementLabel? label;
  final List<({double x, double y})> points;

  /// 格式化显示文本。
  String get displayText {
    switch (type) {
      case MeasurementType.distance:
        return '${value.toStringAsFixed(1)} $unit';
      case MeasurementType.angle:
        return '${value.toStringAsFixed(1)}°';
      case MeasurementType.area:
        return '${value.toStringAsFixed(1)} $unit²';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeasurementResult && type == other.type && value == other.value;

  @override
  int get hashCode => Object.hash(type, value);
}

/// 测量工具（Excalidraw Measurement 本地化——纯 Dart 静态方法）。
///
/// 功能：
/// - 距离测量（两点间欧几里得距离）
/// - 角度测量（两向量夹角）
/// - 面积测量（多边形面积——Shoelace 公式）
/// - 标注生成（测量结果显示位置——线段中点/多边形质心）
class Measurement {
  const Measurement._();

  /// 两点间距离（欧几里得距离——Excalidraw distance 核心算法）。
  static double distance(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// 距离测量（生成 MeasurementResult + 标注）。
  static MeasurementResult measureDistance(double x1, double y1, double x2, double y2) {
    final dist = distance(x1, y1, x2, y2);
    final midX = (x1 + x2) / 2;
    final midY = (y1 + y2) / 2;
    return MeasurementResult(
      type: MeasurementType.distance,
      value: dist,
      unit: 'px',
      label: MeasurementLabel(text: '${dist.toStringAsFixed(1)}px', x: midX, y: midY - 15),
      points: [(x: x1, y: y1), (x: x2, y: y2)],
    );
  }

  /// 两向量夹角（弧度 → 角度——Excalidraw angle 核心算法）。
  static double angleBetween(
      double ax, double ay, double bx, double by, double cx, double cy) {
    // 向量 AB 和 BC 的夹角。
    final abx = bx - ax, aby = by - ay;
    final bcx = cx - bx, bcy = cy - by;
    final dot = abx * bcx + aby * bcy;
    final magAB = math.sqrt(abx * abx + aby * aby);
    final magBC = math.sqrt(bcx * bcx + bcy * bcy);
    if (magAB == 0 || magBC == 0) return 0;
    final cosAngle = (dot / (magAB * magBC)).clamp(-1.0, 1.0);
    return math.acos(cosAngle) * 180 / math.pi;
  }

  /// 角度测量（生成 MeasurementResult + 标注）。
  static MeasurementResult measureAngle(
      double ax, double ay, double bx, double by, double cx, double cy) {
    final angle = angleBetween(ax, ay, bx, by, cx, cy);
    return MeasurementResult(
      type: MeasurementType.angle,
      value: angle,
      unit: '°',
      label: MeasurementLabel(text: '${angle.toStringAsFixed(1)}°', x: bx, y: by - 15),
      points: [(x: ax, y: ay), (x: bx, y: by), (x: cx, y: cy)],
    );
  }

  /// 多边形面积（Shoelace 公式——Excalidraw area 核心算法）。
  static double polygonArea(List<({double x, double y})> points) {
    if (points.length < 3) return 0;
    var area = 0.0;
    for (var i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += points[i].x * points[j].y;
      area -= points[j].x * points[i].y;
    }
    return area.abs() / 2;
  }

  /// 多边形质心（标注位置——面积测量标注用）。
  static ({double x, double y}) polygonCentroid(List<({double x, double y})> points) {
    if (points.isEmpty) return (x: 0, y: 0);
    var cx = 0.0, cy = 0.0;
    for (final p in points) {
      cx += p.x;
      cy += p.y;
    }
    return (x: cx / points.length, y: cy / points.length);
  }

  /// 面积测量（生成 MeasurementResult + 标注）。
  static MeasurementResult measureArea(List<({double x, double y})> points) {
    final area = polygonArea(points);
    final centroid = polygonCentroid(points);
    return MeasurementResult(
      type: MeasurementType.area,
      value: area,
      unit: 'px',
      label: MeasurementLabel(text: '${area.toStringAsFixed(1)}px²', x: centroid.x, y: centroid.y),
      points: points,
    );
  }
}
