// editor_v2——StrokeStyleNotifier（画笔样式状态管理——2026-08-21）。
//
// 画笔样式（颜色/线宽/透明度/线条类型）状态管理——积木式独立 Notifier。
// 与 EditorV2Notifier 解耦——独立管理画笔参数——不搞崩。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';

/// 画笔样式 Notifier（积木式独立——不耦合 EditorV2Notifier）。
class StrokeStyleNotifier extends Notifier<StrokeStyle> {
  @override
  StrokeStyle build() => const StrokeStyle();

  /// 更新画笔样式。
  void update(StrokeStyle style) {
    state = style;
  }

  /// 更新颜色。
  void updateColor(String color) {
    state = state.copyWith(strokeColor: color);
  }

  /// 更新线宽（范围限制）。
  void updateStrokeWidth(double width) {
    state = state.withStrokeWidth(width);
  }

  /// 更新透明度（0~1）。
  void updateOpacity(double value) {
    state = state.withOpacity(value);
  }

  /// 更新线条类型。
  void updateLineStyle(StrokeLineType type) {
    state = state.copyWith(strokeStyle: type);
  }

  /// 更新填充模式（stroke/fill/both）。
  void updateFillMode(FillMode mode) {
    state = state.copyWith(fillMode: mode);
  }

  /// 重置为默认。
  void reset() {
    state = const StrokeStyle();
  }
}

/// Riverpod Provider（积木式独立）。
final strokeStyleProvider =
    NotifierProvider<StrokeStyleNotifier, StrokeStyle>(
  () => StrokeStyleNotifier(),
);
