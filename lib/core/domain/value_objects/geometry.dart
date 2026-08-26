/// 几何值对象 — 零依赖。
///
/// 替代 dart:ui 的 Offset/Size/Rect，使 Domain 层保持零 Flutter 依赖。
/// 在 Infrastructure 层通过扩展与 dart:ui 类型互相转换。
library;

/// 2D 浮点坐标。
class FOffset {
  final double x;
  final double y;

  const FOffset(this.x, this.y);

  static const zero = FOffset(0, 0);

  FOffset operator +(FOffset other) => FOffset(x + other.x, y + other.y);
  FOffset operator -(FOffset other) => FOffset(x - other.x, y - other.y);
  FOffset operator *(double scale) => FOffset(x * scale, y * scale);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FOffset && other.x == x && other.y == y);

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'FOffset($x, $y)';
}

/// 2D 浮点尺寸。
class FSize {
  final double width;
  final double height;

  const FSize(this.width, this.height);

  static const zero = FSize(0, 0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FSize && other.width == width && other.height == height);

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'FSize($width, $height)';
}

/// 浮点矩形（左上角 + 宽高）。
class FRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const FRect(this.x, this.y, this.width, this.height);

  factory FRect.fromLTWH(double left, double top, double width, double height) =>
      FRect(left, top, width, height);

  double get left => x;
  double get top => y;
  double get right => x + width;
  double get bottom => y + height;

  FOffset get center => FOffset(x + width / 2, y + height / 2);

  bool contains(FOffset point) =>
      point.x >= x &&
      point.x <= x + width &&
      point.y >= y &&
      point.y <= y + height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FRect &&
          other.x == x &&
          other.y == y &&
          other.width == width &&
          other.height == height);

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'FRect($x, $y, $width, $height)';
}
