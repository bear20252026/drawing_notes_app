// editor_core——BrushStyles 画笔笔画组（Saber 借鉴——2026-08-22）。
//
// 用户需求：什么画笔的笔画功能都可以搬（保留版权说明）。
// 搬运 Saber（GPL-3.0——Adil Hanney）画笔笔画风格：
// - 钢笔（Pen）：压力感应笔画——粗细随压力变化（手写感）
// - 圆珠笔（Ballpoint）：均匀笔画——无压力变化（清晰书写）
// - 荧光笔（Highlighter）：半透明宽笔画——强调/高亮（暗光护眼）
// - 铅笔（Pencil）：纹理笔画——粗糙感（手绘铅笔效果）
//
// 注意：仅借鉴笔画风格参数（非代码复制——GPL-3.0 义务不延伸——
// 版权归属见 NOTICE——Saber 条目）。
// 纯 Dart 不可变——可独立测试——不搞崩。
library;

import 'dart:math' as math;

/// 画笔类型（Saber 画笔组借鉴）。
enum BrushType {
  /// 钢笔（压力感应——粗细随压力变化）。
  pen,

  /// 圆珠笔（均匀——无压力变化）。
  ballpoint,

  /// 荧光笔（半透明宽笔画——高亮）。
  highlighter,

  /// 铅笔（纹理笔画——粗糙感）。
  pencil,
}

/// 笔画点（含压力——Saber 钢笔压力感应——不可变）。
class StrokePoint {
  const StrokePoint({
    required this.x,
    required this.y,
    this.pressure = 1.0,
  });

  final double x;
  final double y;

  /// 压力（0~1——钢笔压力感应）。
  final double pressure;

  StrokePoint copyWith({double? x, double? y, double? pressure}) {
    return StrokePoint(
      x: x ?? this.x,
      y: y ?? this.y,
      pressure: pressure ?? this.pressure,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokePoint && x == other.x && y == other.y && pressure == other.pressure;

  @override
  int get hashCode => Object.hash(x, y, pressure);
}

/// 画笔笔画风格（Saber 画笔组本地化——不可变）。
///
/// 每种画笔的笔画参数（粗细/透明度/压力感应/纹理）——
/// 渲染由 CanvasPainterV2 按参数执行——纯数据可独立测试。
class BrushStyle {
  const BrushStyle({
    required this.type,
    this.baseWidth = 2.0,
    this.opacity = 1.0,
    this.pressureSensitive = false,
    this.textured = false,
    this.capRound = true,
  });

  final BrushType type;

  /// 基准粗细（像素）。
  final double baseWidth;

  /// 不透明度（荧光笔半透明）。
  final double opacity;

  /// 是否压力感应（钢笔——粗细随压力变化）。
  final bool pressureSensitive;

  /// 是否纹理（铅笔——粗糙感）。
  final bool textured;

  /// 圆头笔帽。
  final bool capRound;

  /// 计算有效粗细（钢笔压力感应——baseWidth × pressure 变化；
  /// 其他——固定 baseWidth）。
  double effectiveWidth(double pressure) {
    if (pressureSensitive) {
      // 钢笔：压力 0→最小（40%），1→最大（160%）。
      final ratio = 0.4 + pressure * 1.2;
      return baseWidth * ratio;
    }
    return baseWidth;
  }

  /// 荧光笔（半透明宽笔画——高亮）。
  static const highlighter = BrushStyle(
    type: BrushType.highlighter,
    baseWidth: 8.0,
    opacity: 0.35,
  );

  /// 钢笔（压力感应——手写感）。
  static const pen = BrushStyle(
    type: BrushType.pen,
    pressureSensitive: true,
  );

  /// 圆珠笔（均匀——清晰书写）。
  static const ballpoint = BrushStyle(
    type: BrushType.ballpoint,
    baseWidth: 1.5,
  );

  /// 铅笔（纹理——粗糙感）。
  static const pencil = BrushStyle(
    type: BrushType.pencil,
    baseWidth: 1.0,
    textured: true,
    opacity: 0.8,
  );

  BrushStyle copyWith({
    double? baseWidth,
    double? opacity,
    bool? pressureSensitive,
    bool? textured,
    bool? capRound,
  }) {
    return BrushStyle(
      type: type,
      baseWidth: baseWidth ?? this.baseWidth,
      opacity: opacity ?? this.opacity,
      pressureSensitive: pressureSensitive ?? this.pressureSensitive,
      textured: textured ?? this.textured,
      capRound: capRound ?? this.capRound,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BrushStyle && type == other.type;

  @override
  int get hashCode => type.hashCode;
}

/// 画笔样式服务（Saber 画笔组——积木式纯 Dart）。
class BrushStyles {
  const BrushStyles._();

  /// 所有画笔（工具栏选择——Saber 画笔组）。
  static const List<BrushStyle> all = [
    BrushStyle.pen,
    BrushStyle.ballpoint,
    BrushStyle.highlighter,
    BrushStyle.pencil,
  ];

  /// 按类型获取画笔。
  static BrushStyle of(BrushType type) {
    return all.firstWhere((b) => b.type == type);
  }

  /// 画笔名称（本地化——中文）。
  static String nameOf(BrushType type) {
    switch (type) {
      case BrushType.pen:
        return '钢笔';
      case BrushType.ballpoint:
        return '圆珠笔';
      case BrushType.highlighter:
        return '荧光笔';
      case BrushType.pencil:
        return '铅笔';
    }
  }

  /// 是否压力感应（钢笔）。
  static bool isPressureSensitive(BrushStyle style) => style.pressureSensitive;

  /// 是否半透明（荧光笔——高亮）。
  static bool isTranslucent(BrushStyle style) => style.opacity < 0.8;

  /// 是否纹理（铅笔）。
  static bool isTextured(BrushStyle style) => style.textured;

  /// 笔画压力序列（钢笔压力感应——随时间变化的压力）。
  static List<StrokePoint> withPressure(List<StrokePoint> points) {
    // 钢笔压力变化（正弦波模拟——压力 0.3~1.0）。
    if (points.isEmpty) return points;
    return List.generate(points.length, (i) {
      final t = points.length > 1 ? i / (points.length - 1) : 0.5;
      final pressure = 0.65 + 0.35 * math.sin(t * math.pi); // 起笔收笔轻。
      return points[i].copyWith(pressure: normalizePressure(pressure));
    });
  }

  /// 压感规范化（Saber v1.34/1.35 借鉴——2026-08-22——S Pen 等手写笔兼容）。
  ///
  /// 部分手写笔（S Pen）压力值偏大/偏小——规范化到 0~1：
  /// 低于 0.05 视为误触（0）；高于 0.95 视为满压（1）。
  static double normalizePressure(double raw) {
    if (raw < 0.05) return 0;
    if (raw > 0.95) return 1;
    return raw;
  }
}
