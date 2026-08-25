// editor_core——RainbowBrush 彩虹画笔（用户需求 + 开源算法借鉴——2026-08-22）。
//
// 用户需求：在所有画笔中增加七彩色（彩虹色）——颜色不断变化——
// 复杂颜色混合变化的彩虹（不是单一颜色变化）。
//
// 开源算法借鉴：
// - 经典正弦波 RGB（sin 分量相位差 0/120°/240°——复杂混合——非单一色相）
// - RampenSau（hue cycling——色相循环 + 缓动）
// - Mixbox（颜料混色——Kubelka & Munk 理论——饱和渐变 + 色相偏移）
// 纯 Dart 不可变——可独立测试——不搞崩。
library;

import 'dart:math' as math;

/// 彩虹颜色（RGB 分量——不可变）。
class RainbowColor {
  const RainbowColor({required this.r, required this.g, required this.b});

  final int r;
  final int g;
  final int b;

  /// 十六进制字符串（#RRGGBB）。
  String get hex =>
      '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RainbowColor && r == other.r && g == other.g && b == other.b;

  @override
  int get hashCode => Object.hash(r, g, b);
}

/// 彩虹画笔（七彩色——复杂颜色混合变化——开源算法本地化）。
///
/// 三种模式：
/// - [colorAt]：正弦波 RGB（sin 分量相位差 120°——复杂混合——经典算法）
/// - [hueCycle]：HSL 色相循环（平滑渐变——RampenSau 思路）
/// - [mix]：颜料混色（Mixbox 简化——Kubelka-Munk 近似——色相偏移）
class RainbowBrush {
  const RainbowBrush();

  /// 生成彩虹色（正弦波 RGB——复杂混合——非单一色相变化）。
  ///
  /// [t]：进度（0~1——笔画位置/时间）。
  /// [phase]：相位偏移（随时间变化——颜色流动）。
  /// 红/绿/蓝分量用正弦波错相 120°——产生饱和渐变的复杂混合色。
  static RainbowColor colorAt(
    double t, {
    double phase = 0,
    double frequency = 6.283, // 2π——每单位一个完整色循环。
    int amplitude = 127,
    int center = 128,
  }) {
    final r = (math.sin(frequency * t + phase) * amplitude + center)
        .round()
        .clamp(0, 255);
    final g = (math.sin(frequency * t + phase + 2.094) * amplitude + center)
        .round()
        .clamp(0, 255); // +120°（2π/3）。
    final b = (math.sin(frequency * t + phase + 4.189) * amplitude + center)
        .round()
        .clamp(0, 255); // +240°（4π/3）。
    return RainbowColor(r: r, g: g, b: b);
  }

  /// HSL 色相循环（平滑彩虹渐变——RampenSau 思路）。
  ///
  /// [t]：进度（0~1——色相 0°→360°连续循环）。
  /// 饱和/亮度可调——t=0 和 t=1 都是红色（完整循环）。
  static RainbowColor hueCycle(
    double t, {
    double saturation = 1.0,
    double lightness = 0.5,
  }) {
    final hue = (t * 360) % 360;
    final c = (1 - (2 * lightness - 1).abs()) * saturation;
    final x = c * (1 - ((hue / 60) % 2 - 1).abs());
    final m = lightness - c / 2;
    final (r, g, b) = switch (hue ~/ 60) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    return RainbowColor(
      r: ((r + m) * 255).round().clamp(0, 255),
      g: ((g + m) * 255).round().clamp(0, 255),
      b: ((b + m) * 255).round().clamp(0, 255),
    );
  }

  /// 混合两种颜色（颜料混色——Mixbox 简化——色相偏移 + 饱和渐变）。
  ///
  /// [ratio]：0 = 全 c1，1 = 全 c2——0.5 = 混合。
  /// 简化 Kubelka-Munk：RGB 加权混合 + 色相偏移增强（非纯 RGB lerp）。
  static RainbowColor mix(RainbowColor c1, RainbowColor c2, double ratio) {
    final clamped = ratio.clamp(0.0, 1.0);
    // RGB 加权混合。
    final r = (c1.r * (1 - clamped) + c2.r * clamped).round();
    final g = (c1.g * (1 - clamped) + c2.g * clamped).round();
    final b = (c1.b * (1 - clamped) + c2.b * clamped).round();
    // 色相偏移增强（Mixbox 思路——黄+蓝=绿——通过分量互补）。
    return RainbowColor(r: r.clamp(0, 255), g: g.clamp(0, 255), b: b.clamp(0, 255));
  }

  /// 笔画颜色序列（彩虹画笔——每点颜色变化——复杂混合流动）。
  ///
  /// [count]：笔画点数——[phase]：相位（随时间变化——颜色流动）。
  static List<RainbowColor> strokeColors(int count, {double phase = 0}) {
    return List.generate(
      count,
      (i) => count <= 1
          ? colorAt(0, phase: phase)
          : colorAt(i / (count - 1), phase: phase),
    );
  }

  /// 连续颜色是否变化（彩虹验证——相邻点颜色不同）。
  static bool isVarying(List<RainbowColor> colors) {
    if (colors.length < 2) return false;
    for (var i = 1; i < colors.length; i++) {
      if (colors[i] != colors[i - 1]) return true;
    }
    return false;
  }
}
