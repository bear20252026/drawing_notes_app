import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 笔画状态（不可变值对象，应对 Riverpod == 过滤语义）。
///
/// 承载当前正在绘制的笔画和已完成笔画的摘要信息；
/// 所有变更生成新实例（不可变），provider 通知依赖 == 判断。
///
/// 注意：完整笔画数据仍在 DrawingController._strokes 中（性能考量），
/// 本状态仅暴露 UI 需要的摘要信息。
class StrokesState {
  const StrokesState({
    this.activeStroke,
    this.strokeCount = 0,
    this.isDrawing = false,
  });

  /// 当前正在绘制的笔画（未完成）。
  final Stroke? activeStroke;

  /// 已完成笔画总数。
  final int strokeCount;

  /// 是否正在绘制中。
  final bool isDrawing;

  StrokesState copyWith({
    Stroke? activeStroke,
    bool clearActiveStroke = false,
    int? strokeCount,
    bool? isDrawing,
  }) => StrokesState(
    activeStroke: clearActiveStroke ? null : (activeStroke ?? this.activeStroke),
    strokeCount: strokeCount ?? this.strokeCount,
    isDrawing: isDrawing ?? this.isDrawing,
  );

  @override
  bool operator ==(Object other) =>
      other is StrokesState &&
      other.activeStroke == activeStroke &&
      other.strokeCount == strokeCount &&
      other.isDrawing == isDrawing;

  @override
  int get hashCode => Object.hash(activeStroke, strokeCount, isDrawing);
}

/// 笔画域 Notifier（DrawingController 域 Notifier 化）。
///
/// 迁移边界：DrawingController 内部 _strokes 暂不替换
/// （避免双状态源不一致）；本 Notifier 暴露"可见笔画状态"，
/// UI 可经 ref.watch 订阅；后续逐域替换。
class StrokesNotifier extends Notifier<StrokesState> {
  @override
  StrokesState build() => const StrokesState();

  /// 开始新笔画。
  void startStroke(Stroke stroke) {
    state = state.copyWith(
      activeStroke: stroke,
      isDrawing: true,
    );
  }

  /// 更新当前笔画（添加点）。
  void updateStroke(Stroke stroke) {
    state = state.copyWith(activeStroke: stroke);
  }

  /// 结束当前笔画。
  void endStroke() {
    state = state.copyWith(
      clearActiveStroke: true,
      strokeCount: state.strokeCount + 1,
      isDrawing: false,
    );
  }

  /// 设置笔画总数（从控制器同步）。
  void setStrokeCount(int count) {
    state = state.copyWith(strokeCount: count);
  }
}

/// 笔画状态 Provider。
final strokesProvider = NotifierProvider<StrokesNotifier, StrokesState>(
  StrokesNotifier.new,
);
