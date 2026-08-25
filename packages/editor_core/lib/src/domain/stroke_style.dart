// editor_core——StrokeStyle 画笔样式（AFFiNE/Excalidraw 借鉴——2026-08-21）。
//
// 画笔参数（颜色/线宽/透明度/样式）——AFFiNE 工具栏 + Excalidraw 画笔系统本地化。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
library;

import 'tool_engine.dart';

/// 笔画样式（画笔参数——AFFiNE/Excalidraw 借鉴——不可变）。
class StrokeStyle {
  const StrokeStyle({
    this.strokeColor = '#000000',
    this.backgroundColor = 'transparent',
    this.strokeWidth = 2.0,
    this.opacity = 1.0,
    this.strokeStyle = StrokeLineType.solid,
    this.fillMode = FillMode.stroke,
  });

  final String strokeColor;
  final String backgroundColor;
  final double strokeWidth;
  final double opacity;
  final StrokeLineType strokeStyle;

  /// 图形填充模式（stroke/fill/both）。
  final FillMode fillMode;

  StrokeStyle copyWith({
    String? strokeColor,
    String? backgroundColor,
    double? strokeWidth,
    double? opacity,
    StrokeLineType? strokeStyle,
    FillMode? fillMode,
  }) {
    return StrokeStyle(
      strokeColor: strokeColor ?? this.strokeColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      opacity: opacity ?? this.opacity,
      strokeStyle: strokeStyle ?? this.strokeStyle,
      fillMode: fillMode ?? this.fillMode,
    );
  }

  /// 线条宽度范围（Excalidraw 最小 1，最大 32）。
  static const double minWidth = 1.0;
  static const double maxWidth = 32.0;

  /// 调整线宽（范围限制）。
  StrokeStyle withStrokeWidth(double width) {
    return copyWith(strokeWidth: width.clamp(minWidth, maxWidth));
  }

  /// 调整透明度（0~1）。
  StrokeStyle withOpacity(double value) {
    return copyWith(opacity: value.clamp(0.0, 1.0));
  }

  /// 预设样式（AFFiNE/Excalidraw 常用画笔参数）。
  static const thin = StrokeStyle(strokeWidth: 1.0);
  static const medium = StrokeStyle();
  static const thick = StrokeStyle(strokeWidth: 4.0);
  static const extraThick = StrokeStyle(strokeWidth: 8.0);

  /// 预设颜色（AFFiNE 调色板——常用色）。
  static const black = StrokeStyle();
  static const red = StrokeStyle(strokeColor: '#FF0000');
  static const blue = StrokeStyle(strokeColor: '#0000FF');
  static const green = StrokeStyle(strokeColor: '#00AA00');
  static const transparent = StrokeStyle(opacity: 0.0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokeStyle &&
          strokeColor == other.strokeColor &&
          backgroundColor == other.backgroundColor &&
          strokeWidth == other.strokeWidth &&
          opacity == other.opacity &&
          strokeStyle == other.strokeStyle &&
          fillMode == other.fillMode;

  @override
  int get hashCode => Object.hash(strokeColor, backgroundColor, strokeWidth, opacity, strokeStyle, fillMode);
}

/// 线条类型（Excalidraw stroke style 借鉴）。
enum StrokeLineType {
  /// 实线（默认）。
  solid,

  /// 虚线。
  dashed,

  /// 点线。
  dotted,
}
