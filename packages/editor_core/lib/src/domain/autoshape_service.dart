// editor_core——AutoshapeService 手绘整形（Excalidraw+ 借鉴——2026-08-22）。
//
// Excalidraw+ Autoshape（Shift+X）：手绘草图 → 自动整形为完美几何形状
//（直线/矩形/圆形）——用户画不直的线条自动修正。
//
// 本地化：手绘点序列 → 整形判定（近似共线→直线/四角→矩形/闭合→圆形）。
// 纯 Dart 不可变（无 Flutter 依赖——R-02）——可独立测试——不搞崩。
//
// 版权：Excalidraw+（MIT）——仅概念借鉴——NOTICE 已记录。
library;

import 'dart:math' as math;

/// 整形用点（纯 Dart——替代 Flutter Offset——不可变）。
class AutoPoint {
  const AutoPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoPoint && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// 整形结果（不可变——手绘 → 几何形状）。
class AutoshapeResult {
  const AutoshapeResult({
    required this.shape,
    required this.confidence,
    this.rectX1 = 0,
    this.rectY1 = 0,
    this.rectX2 = 0,
    this.rectY2 = 0,
    this.startX = 0,
    this.startY = 0,
    this.endX = 0,
    this.endY = 0,
  });

  /// 整形后的形状类型（'line'/'rect'/'ellipse'/null = 保持手绘）。
  final String? shape;

  /// 整形置信度（0~1——高于阈值才整形）。
  final double confidence;

  /// 整形后的矩形四角（rect/ellipse——line 为 0）。
  final double rectX1, rectY1, rectX2, rectY2;

  /// 直线起点/终点（line）。
  final double startX, startY, endX, endY;

  bool get shouldShape => confidence >= 0.8;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoshapeResult && shape == other.shape && confidence == other.confidence;

  @override
  int get hashCode => Object.hash(shape, confidence);
}

/// 手绘整形服务（Excalidraw+ Autoshape 本地化——积木式纯 Dart）。
///
/// 整形判定：
/// - 近似共线（点到直线最大距离小）→ 直线
/// - 四角闭合（包围盒 + 面积占比）→ 矩形
/// - 闭合近似圆形（半径方差小）→ 椭圆
class AutoshapeService {
  const AutoshapeService();

  /// 整形判定（手绘点序列 → 几何形状）。
  AutoshapeResult shape(List<AutoPoint> points) {
    if (points.length < 3) {
      return const AutoshapeResult(shape: null, confidence: 0);
    }

    // 1. 直线判定（点到首尾连线最大距离小）。
    final line = _asLine(points);
    if (line.$1 >= 0.8) {
      return AutoshapeResult(
        shape: 'line',
        confidence: line.$1,
        startX: line.$2.$1.x,
        startY: line.$2.$1.y,
        endX: line.$2.$2.x,
        endY: line.$2.$2.y,
      );
    }

    // 2. 闭合判定（首尾接近——矩形/圆形候选）。
    if (!_isClosed(points)) {
      return const AutoshapeResult(shape: null, confidence: 0);
    }

    final bounds = _bounds(points);

    // 3. 矩形判定（四角——包围盒面积占比）。
    final rectConfidence = _asRect(points, bounds);
    if (rectConfidence >= 0.8) {
      return AutoshapeResult(
        shape: 'rect',
        confidence: rectConfidence,
        rectX1: bounds.$1,
        rectY1: bounds.$2,
        rectX2: bounds.$3,
        rectY2: bounds.$4,
      );
    }

    // 4. 圆形判定（半径方差小）。
    final ellipseConfidence = _asEllipse(points, bounds);
    if (ellipseConfidence >= 0.8) {
      return AutoshapeResult(
        shape: 'ellipse',
        confidence: ellipseConfidence,
        rectX1: bounds.$1,
        rectY1: bounds.$2,
        rectX2: bounds.$3,
        rectY2: bounds.$4,
      );
    }

    return const AutoshapeResult(shape: null, confidence: 0);
  }

  /// 点到直线距离（数学公式——纯 Dart）。
  double _pointToLineDistance(AutoPoint p, AutoPoint a, AutoPoint b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return _dist(p, a);
    final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq;
    final projX = a.x + t * dx;
    final projY = a.y + t * dy;
    return _dist(p, AutoPoint(projX, projY));
  }

  /// 两点距离。
  double _dist(AutoPoint a, AutoPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// 直线判定（点到首尾连线最大距离——越小越直）。
  (double, (AutoPoint, AutoPoint)) _asLine(List<AutoPoint> points) {
    final start = points.first;
    final end = points.last;
    double maxDist = 0;
    for (final p in points) {
      final d = _pointToLineDistance(p, start, end);
      if (d > maxDist) maxDist = d;
    }
    final length = _dist(start, end);
    final confidence = length > 0 ? (1 - maxDist / length).clamp(0.0, 1.0) : 0.0;
    return (confidence, (start, end));
  }

  /// 闭合判定（首尾距离小）。
  bool _isClosed(List<AutoPoint> points) {
    if (points.length < 4) return false;
    final bounds = _bounds(points);
    final diagonal = math.max(
      (bounds.$3 - bounds.$1).abs(),
      (bounds.$4 - bounds.$2).abs(),
    );
    return diagonal > 0 && _dist(points.first, points.last) < diagonal * 0.15;
  }

  /// 矩形判定（边框距离法——点靠近包围盒边框 = 矩形；
  /// 圆形点在中途——距离大——可区分）。
  double _asRect(List<AutoPoint> points, (double, double, double, double) bounds) {
    final width = (bounds.$3 - bounds.$1).abs();
    final height = (bounds.$4 - bounds.$2).abs();
    if (width < 2 || height < 2) return 0;

    // 每个点到包围盒边框（四条边）的最小距离——平均小 = 矩形。
    var totalDist = 0.0;
    for (final p in points) {
      final dLeft = (p.x - bounds.$1).abs();
      final dRight = (p.x - bounds.$3).abs();
      final dTop = (p.y - bounds.$2).abs();
      final dBottom = (p.y - bounds.$4).abs();
      final minDist = [dLeft, dRight, dTop, dBottom]
          .reduce((a, b) => a < b ? a : b);
      totalDist += minDist;
    }
    final avgDist = totalDist / points.length;
    // 归一化：平均距离相对对角线越小 = 越矩形。
    final diagonal = math.sqrt(width * width + height * height);
    final confidence = diagonal > 0 ? (1 - avgDist / (diagonal * 0.1)).clamp(0.0, 1.0) : 0.0;
    return confidence;
  }

  /// 圆形判定（点到中心距离方差小——半径均匀）。
  double _asEllipse(List<AutoPoint> points, (double, double, double, double) bounds) {
    final cx = (bounds.$1 + bounds.$3) / 2;
    final cy = (bounds.$2 + bounds.$4) / 2;
    final distances = points.map((p) => _dist(p, AutoPoint(cx, cy))).toList();
    final avg = distances.reduce((a, b) => a + b) / distances.length;
    if (avg <= 0) return 0;
    final variance =
        distances.map((d) => (d - avg) * (d - avg)).reduce((a, b) => a + b) / distances.length;
    final stdDev = math.sqrt(variance);
    return (1 - stdDev / avg).clamp(0.0, 1.0);
  }

  /// 包围盒。
  (double, double, double, double) _bounds(List<AutoPoint> points) {
    var minX = points.first.x, maxX = points.first.x;
    var minY = points.first.y, maxY = points.first.y;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return (minX, minY, maxX, maxY);
  }
}
