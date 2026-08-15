import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 历史状态（不可变值对象，应对 Riverpod == 过滤语义）。
///
/// 承载撤销/重做栈的可见状态（canUndo/canRedo + 当前栈位）；
/// 栈内命令列表不暴露（命令含对象引用，仅用于 controller 内部），
/// 对外只暴露"可撤销/可重做"判定（UI 按钮 enabled 状态）。
class HistoryState {
  const HistoryState({required this.canUndo, required this.canRedo});

  /// 是否存在可撤销的历史（栈位 > 0）。
  final bool canUndo;

  /// 是否存在可重做的历史（栈位 < 栈长度）。
  final bool canRedo;

  static const HistoryState initial =
      HistoryState(canUndo: false, canRedo: false);

  HistoryState copyWith({bool? canUndo, bool? canRedo}) => HistoryState(
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
  );

  @override
  bool operator ==(Object other) =>
      other is HistoryState &&
      other.canUndo == canUndo &&
      other.canRedo == canRedo;

  @override
  int get hashCode => Object.hash(canUndo, canRedo);
}

/// 历史域 Notifier（DrawingController 第三个域 Notifier 化示范）。
///
/// 依据 riverpod.dev from_state_notifier 官方 + replay_riverpod 开源包
/// （ReplayStateNotifier undo/redo 模式）综合定案：
/// - 不可变 state（== 过滤语义，变更须生成新实例）
/// - build() 承载初始化（官方规则）
/// - 变更方法只赋 state（免 notifyListeners 样板）
/// - 独立可测（ProviderContainer 单测）
///
/// 迁移边界（审慎）：DrawingController 内部 _history/_historyPosition
/// 暂不替换（避免双状态源不一致），本 Notifier 暴露"可见历史状态"
/// （canUndo/canRedo），UI 按钮可经 ref.watch 订阅；后续逐域替换。
class DrawingHistoryNotifier extends Notifier<HistoryState> {
  @override
  HistoryState build() => HistoryState.initial;

  /// 命令入栈后更新历史状态（由 controller 或命令栈驱动）。
  void notifyChanged({required bool canUndo, required bool canRedo}) {
    final next = HistoryState(canUndo: canUndo, canRedo: canRedo);
    if (next == state) return; // == 过滤，避免无效重建
    state = next;
  }

  /// 撤销后更新历史状态。
  void afterUndo({required bool canUndo, required bool canRedo}) =>
      notifyChanged(canUndo: canUndo, canRedo: canRedo);

  /// 重做后更新历史状态。
  void afterRedo({required bool canUndo, required bool canRedo}) =>
      notifyChanged(canUndo: canUndo, canRedo: canRedo);
}

/// 历史域 Provider（第三个域 Notifier 化示范）。
final historyProvider =
    NotifierProvider<DrawingHistoryNotifier, HistoryState>(
  DrawingHistoryNotifier.new,
);
