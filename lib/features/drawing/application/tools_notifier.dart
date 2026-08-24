import 'package:flutter/painting.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 工具状态（不可变值对象，应对 Riverpod == 过滤语义）。
///
/// 承载画笔/橡皮擦工具的当前配置；所有变更生成新实例（不可变），
/// provider 通知依赖 == 判断。
class ToolsState {
  const ToolsState({
    this.brushType = BrushType.pen,
    this.color = const Color(0xFF1A1A1A),
    this.brushSize = 6.0,
    this.eraserSize = 24.0,
    this.eraserMode = EraserMode.stroke,
  });

  /// 当前工具类型（画笔/橡皮擦等）。
  final BrushType brushType;

  /// 当前画笔颜色。
  final Color color;

  /// 画笔粗细（逻辑像素）。
  final double brushSize;

  /// 橡皮擦粗细（逻辑像素）。
  final double eraserSize;

  /// 橡皮擦模式（整笔擦除/像素擦除）。
  final EraserMode eraserMode;

  /// 当前工具对应的线宽。
  double get currentSize =>
      brushType == BrushType.eraser ? eraserSize : brushSize;

  ToolsState copyWith({
    BrushType? brushType,
    Color? color,
    double? brushSize,
    double? eraserSize,
    EraserMode? eraserMode,
  }) => ToolsState(
    brushType: brushType ?? this.brushType,
    color: color ?? this.color,
    brushSize: brushSize ?? this.brushSize,
    eraserSize: eraserSize ?? this.eraserSize,
    eraserMode: eraserMode ?? this.eraserMode,
  );

  @override
  bool operator ==(Object other) =>
      other is ToolsState &&
      other.brushType == brushType &&
      other.color == color &&
      other.brushSize == brushSize &&
      other.eraserSize == eraserSize &&
      other.eraserMode == eraserMode;

  @override
  int get hashCode => Object.hash(brushType, color, brushSize, eraserSize, eraserMode);
}

/// 工具域 Notifier（DrawingController 域 Notifier 化）。
///
/// 迁移边界：DrawingController 内部 _tool/_color/_brushSize 等暂不替换
/// （避免双状态源不一致）；本 Notifier 暴露"可见工具状态"，
/// UI 工具栏可经 ref.watch 订阅；后续逐域替换。
class ToolsNotifier extends Notifier<ToolsState> {
  @override
  ToolsState build() => const ToolsState();

  void setBrushType(BrushType type) {
    state = state.copyWith(brushType: type);
  }

  void setColor(Color color) {
    state = state.copyWith(color: color);
  }

  void setBrushSize(double size) {
    state = state.copyWith(brushSize: size);
  }

  void setEraserSize(double size) {
    state = state.copyWith(eraserSize: size);
  }

  void setEraserMode(EraserMode mode) {
    state = state.copyWith(eraserMode: mode);
  }
}

/// 工具状态 Provider。
final toolsProvider = NotifierProvider<ToolsNotifier, ToolsState>(
  ToolsNotifier.new,
);
