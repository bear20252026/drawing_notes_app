// editor_core——ColorMagnifier 取色放大镜（用户需求——2026-08-22）。
//
// 用户需求：取色板功能困难——应在鼠标所指位置中央生成小放大镜——
// 放大显示那到底是什么颜色。
//
// 纯 Dart 不可变模型——可独立测试——不搞崩。
// 放大镜逻辑：采样点周围区域 → 放大显示 → 提取中心颜色。
library;

/// 放大镜配置（用户需求——不可变）。
class MagnifierConfig {
  const MagnifierConfig({
    this.radius = 16,        // 采样半径（像素）。
    this.zoom = 3,           // 放大倍数（3x）。
    this.showCrosshair = true, // 显示十字准线。
    this.showHex = true,     // 显示 HEX 颜色值。
  });

  final int radius;
  final int zoom;
  final bool showCrosshair;
  final bool showHex;

  MagnifierConfig copyWith({int? radius, int? zoom, bool? showCrosshair, bool? showHex}) {
    return MagnifierConfig(
      radius: radius ?? this.radius,
      zoom: zoom ?? this.zoom,
      showCrosshair: showCrosshair ?? this.showCrosshair,
      showHex: showHex ?? this.showHex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MagnifierConfig && radius == other.radius && zoom == other.zoom;

  @override
  int get hashCode => Object.hash(radius, zoom);
}

/// 放大镜显示尺寸（不可变）。
class MagnifierSize {
  const MagnifierSize({required this.width, required this.height});

  final int width;
  final int height;

  /// 是否有效（正尺寸）。
  bool get isValid => width > 0 && height > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MagnifierSize && width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// 取色结果（不可变）。
class PickedColor {
  const PickedColor({required this.r, required this.g, required this.b, this.positionX = 0, this.positionY = 0});

  final int r;
  final int g;
  final int b;
  final double positionX;
  final double positionY;

  /// HEX 颜色（#RRGGBB）。
  String get hex =>
      '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PickedColor && r == other.r && g == other.g && b == other.b;

  @override
  int get hashCode => Object.hash(r, g, b);
}

/// 取色放大镜服务（用户需求——积木式纯 Dart）。
///
/// 功能：
/// - 采样区域计算（鼠标位置周围 radius 区域——放大显示）
/// - 像素颜色提取（从图像字节采样——中心像素）
/// - 放大镜显示尺寸（radius × zoom）
/// - HEX 颜色输出（显示在放大镜中央）
class ColorMagnifier {
  const ColorMagnifier();

  /// 计算放大镜显示尺寸（radius × 2 × zoom——放大区域）。
  MagnifierSize magnifierSize(MagnifierConfig config) {
    final side = config.radius * 2 * config.zoom;
    return MagnifierSize(width: side, height: side);
  }

  /// 提取像素颜色（从图像字节——BGR/RGB 格式）。
  ///
  /// [imageBytes]：图像像素字节（每像素 4 字节——RGBA 或 BGRA）。
  /// [width]/[height]：图像尺寸。
  /// [px]/[py]：采样位置（鼠标坐标）。
  /// [bgrOrder]：字节顺序（true = BGRA——某些平台；false = RGBA）。
  PickedColor pickColor({
    required List<int> imageBytes,
    required int width,
    required int height,
    required double px,
    required double py,
    bool bgrOrder = false,
  }) {
    final x = px.round().clamp(0, width - 1);
    final y = py.round().clamp(0, height - 1);
    final index = (y * width + x) * 4;

    if (index + 3 >= imageBytes.length) {
      return const PickedColor(r: 0, g: 0, b: 0);
    }

    final int r;
    final int g;
    final int b;
    if (bgrOrder) {
      b = imageBytes[index];
      g = imageBytes[index + 1];
      r = imageBytes[index + 2];
    } else {
      r = imageBytes[index];
      g = imageBytes[index + 1];
      b = imageBytes[index + 2];
    }

    return PickedColor(r: r, g: g, b: b, positionX: px, positionY: py);
  }

  /// 计算放大镜应显示的内容区域（鼠标位置周围——采样区）。
  ({int left, int top, int right, int bottom}) sampleRegion(
    MagnifierConfig config, {
    required double px,
    required double py,
  }) {
    return (
      left: px.round() - config.radius,
      top: py.round() - config.radius,
      right: px.round() + config.radius,
      bottom: py.round() + config.radius,
    );
  }

  /// 放大镜是否应显示（取色模式开启时）。
  bool shouldShow(bool eyedropperActive, MagnifierConfig config) {
    return eyedropperActive && config.zoom > 0;
  }
}
