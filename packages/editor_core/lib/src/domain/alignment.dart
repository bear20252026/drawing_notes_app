// editor_core——AlignmentDistribution 对齐分布（tldraw 借鉴——2026-08-21）。
//
// tldraw 对齐和分布本地化——元素对齐/均匀分布。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// tldraw 原版参考：
// - alignment（对齐）：左/中/右/上/中/下对齐
// - distribution（分布）：水平/垂直均匀分布
// - 操作：批量移动元素到对齐/分布位置
library;

/// 对齐类型（tldraw alignment 借鉴）。
enum AlignmentType {
  /// 左对齐（所有元素左边缘对齐）。
  left,

  /// 水平居中（所有元素水平中心对齐）。
  centerHorizontal,

  /// 右对齐（所有元素右边缘对齐）。
  right,

  /// 上对齐（所有元素上边缘对齐）。
  top,

  /// 垂直居中（所有元素垂直中心对齐）。
  centerVertical,

  /// 下对齐（所有元素下边缘对齐）。
  bottom,
}

/// 分布类型（tldraw distribution 借鉴）。
enum DistributionType {
  /// 水平均匀分布（元素间水平间距相等）。
  horizontal,

  /// 垂直均匀分布（元素间垂直间距相等）。
  vertical,
}

/// 元素位置信息（对齐/分布计算输入——不可变）。
class ElementPosition {
  const ElementPosition({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String id;
  final double x;
  final double y;
  final double width;
  final double height;

  double get left => x;
  double get top => y;
  double get right => x + width;
  double get bottom => y + height;
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  ElementPosition moveTo(double newX, double newY) {
    return ElementPosition(id: id, x: newX, y: newY, width: width, height: height);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ElementPosition && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 对齐/分布结果（不可变——移动指令列表）。
class AlignmentResult {
  const AlignmentResult({this.moves = const []});

  /// 需要移动的元素列表（id → 新位置）。
  final List<({String id, double x, double y})> moves;

  bool get isEmpty => moves.isEmpty;
  int get count => moves.length;
}

/// 对齐分布工具（tldraw alignment/distribution 本地化——纯 Dart 静态方法）。
///
/// 功能：
/// - 对齐（左/中/右/上/中/下——所有元素对齐到基准线）
/// - 分布（水平/垂直——元素间间距相等）
/// - 批量计算移动指令（返回 AlignmentResult）
class Alignment {
  const Alignment._();

  /// 对齐（tldraw alignment 核心算法）。
  ///
  /// 输入：元素位置列表 + 对齐类型。
  /// 输出：需要移动的元素列表（AlignmentResult）。
  static AlignmentResult align(List<ElementPosition> elements, AlignmentType type) {
    if (elements.length < 2) return const AlignmentResult();

    final moves = <({String id, double x, double y})>[];
    switch (type) {
      case AlignmentType.left:
        final minX = elements.map((e) => e.left).reduce((a, b) => a < b ? a : b);
        for (final e in elements) {
          if (e.left != minX) moves.add((id: e.id, x: minX, y: e.y));
        }
      case AlignmentType.centerHorizontal:
        final avgCenterX = elements.map((e) => e.centerX).reduce((a, b) => a + b) / elements.length;
        for (final e in elements) {
          final newX = avgCenterX - e.width / 2;
          if ((e.x - newX).abs() > 0.01) moves.add((id: e.id, x: newX, y: e.y));
        }
      case AlignmentType.right:
        final maxRight = elements.map((e) => e.right).reduce((a, b) => a > b ? a : b);
        for (final e in elements) {
          final newX = maxRight - e.width;
          if ((e.x - newX).abs() > 0.01) moves.add((id: e.id, x: newX, y: e.y));
        }
      case AlignmentType.top:
        final minY = elements.map((e) => e.top).reduce((a, b) => a < b ? a : b);
        for (final e in elements) {
          if (e.top != minY) moves.add((id: e.id, x: e.x, y: minY));
        }
      case AlignmentType.centerVertical:
        final avgCenterY = elements.map((e) => e.centerY).reduce((a, b) => a + b) / elements.length;
        for (final e in elements) {
          final newY = avgCenterY - e.height / 2;
          if ((e.y - newY).abs() > 0.01) moves.add((id: e.id, x: e.x, y: newY));
        }
      case AlignmentType.bottom:
        final maxBottom = elements.map((e) => e.bottom).reduce((a, b) => a > b ? a : b);
        for (final e in elements) {
          final newY = maxBottom - e.height;
          if ((e.y - newY).abs() > 0.01) moves.add((id: e.id, x: e.x, y: newY));
        }
    }
    return AlignmentResult(moves: moves);
  }

  /// 均匀分布（tldraw distribution 核心算法）。
  ///
  /// 输入：元素位置列表 + 分布类型。
  /// 输出：需要移动的元素列表（AlignmentResult）。
  static AlignmentResult distribute(List<ElementPosition> elements, DistributionType type) {
    if (elements.length < 3) return const AlignmentResult();

    final moves = <({String id, double x, double y})>[];

    if (type == DistributionType.horizontal) {
      // 按水平位置排序。
      final sorted = List<ElementPosition>.from(elements)..sort((a, b) => a.x.compareTo(b.x));
      final totalWidth = sorted.fold(0.0, (sum, e) => sum + e.width);
      final totalSpace = sorted.last.right - sorted.first.left;
      final gap = (totalSpace - totalWidth) / (sorted.length - 1);
      var currentX = sorted.first.left;
      for (var i = 1; i < sorted.length - 1; i++) {
        currentX += sorted[i - 1].width + gap;
        if ((sorted[i].x - currentX).abs() > 0.01) {
          moves.add((id: sorted[i].id, x: currentX, y: sorted[i].y));
        }
      }
    } else {
      // 按垂直位置排序。
      final sorted = List<ElementPosition>.from(elements)..sort((a, b) => a.y.compareTo(b.y));
      final totalHeight = sorted.fold(0.0, (sum, e) => sum + e.height);
      final totalSpace = sorted.last.bottom - sorted.first.top;
      final gap = (totalSpace - totalHeight) / (sorted.length - 1);
      var currentY = sorted.first.top;
      for (var i = 1; i < sorted.length - 1; i++) {
        currentY += sorted[i - 1].height + gap;
        if ((sorted[i].y - currentY).abs() > 0.01) {
          moves.add((id: sorted[i].id, x: sorted[i].x, y: currentY));
        }
      }
    }

    return AlignmentResult(moves: moves);
  }
}
