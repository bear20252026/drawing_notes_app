import 'package:flutter/gestures.dart';

/// 当前笔画输入的来源与诊断状态。
///
/// 该对象故意区分“真实硬件压力”和“回退模拟压力”：用户应能知道自己
/// 正在使用的是否是设备实际提供的数据，而不是被静默的速度算法误导。
enum InkInputSource {
  stylusPressure,
  touchPressure,
  mouseVelocityFallback,
  constantFallback,
}

extension InkInputSourcePresentation on InkInputSource {
  String get label => switch (this) {
    InkInputSource.stylusPressure => '触控笔压感',
    InkInputSource.touchPressure => '触摸压感',
    InkInputSource.mouseVelocityFallback => '鼠标速度模拟',
    InkInputSource.constantFallback => '固定笔宽',
  };

  bool get isHardwarePressure =>
      this == InkInputSource.stylusPressure ||
      this == InkInputSource.touchPressure;
}

/// 单个 PointerEvent 经正规化后的压力信息。
class InkPressureSample {
  const InkPressureSample({
    required this.value,
    required this.source,
    required this.rawPressure,
    required this.pressureMin,
    required this.pressureMax,
    required this.kind,
  });

  /// 供笔画模型使用的 0~1 标准化压力。
  final double value;
  final InkInputSource source;
  final double rawPressure;
  final double pressureMin;
  final double pressureMax;
  final PointerDeviceKind kind;

  bool get hasHardwarePressure => source.isHardwarePressure;

  /// 可用于状态栏的稳定文案，避免把原始设备范围误当作 0~1。
  String get diagnostics => hasHardwarePressure
      ? '${source.label} ${(value * 100).round()}%'
      : source.label;
}

/// 压感解释与平滑策略。
///
/// Flutter 对无压感设备通常报告 pressure=1 且 min/max 都为 1，因此必须
/// 结合输入种类与压力范围判断，而不能仅以 pressure<1 判定。真正的硬件值
/// 会按设备上报范围正规化为 [0, 1]；软件回退值也在此处明确标识。
class StylusInputProcessor {
  StylusInputProcessor({this.smoothing = 0.35});

  /// 0 表示不平滑，接近 1 表示更稳定但响应更慢。
  final double smoothing;

  double? _previousPressure;

  InkPressureSample process(
    PointerEvent event, {
    double? fallbackPressure,
    bool allowTouchPressure = false,
  }) {
    final range = event.pressureMax - event.pressureMin;
    final supportsPressure = range.abs() > 0.001;
    final isStylus =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    final isTouch = event.kind == PointerDeviceKind.touch;

    InkInputSource source;
    double normalized;
    if (supportsPressure && (isStylus || (allowTouchPressure && isTouch))) {
      final raw = (event.pressure - event.pressureMin) / range;
      normalized = raw.clamp(0.0, 1.0);
      source = isStylus
          ? InkInputSource.stylusPressure
          : InkInputSource.touchPressure;
    } else if (fallbackPressure != null) {
      normalized = fallbackPressure.clamp(0.0, 1.0);
      source = InkInputSource.mouseVelocityFallback;
    } else {
      normalized = 1.0;
      source = InkInputSource.constantFallback;
    }

    // 真实压力和模拟压力均做轻量 EMA 平滑，避免采样毛刺导致线宽跳动。
    final previous = _previousPressure;
    if (previous != null) {
      normalized = previous * smoothing + normalized * (1 - smoothing);
    }
    _previousPressure = normalized;

    return InkPressureSample(
      value: normalized,
      source: source,
      rawPressure: event.pressure,
      pressureMin: event.pressureMin,
      pressureMax: event.pressureMax,
      kind: event.kind,
    );
  }

  /// 每一新笔都从新的压力曲线开始，避免上一笔末端的压力影响下一笔起笔。
  void resetStroke() => _previousPressure = null;
}
