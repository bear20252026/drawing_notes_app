import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/canvas_model/selection.dart';

/// 绘制域的领域状态 Notifier 集合。
///
/// 本文件统一承载绘制特性（drawing）在 application 层的"不可变纯状态"
/// 域 Notifier，作为 Riverpod 迁移的示范单元（见各 Notifier 注释）：
/// - 视口域（ViewportState / DrawingViewportNotifier / viewportProvider）
/// - 历史域（HistoryState / DrawingHistoryNotifier / historyProvider）
/// - 选区域（SelectionState / DrawingSelectionNotifier / selectionProvider）
///
/// 之所以聚合在一处：三者都是"独立域 Notifier"迁移的同类示范，共享完全
/// 相同的设计语言（不可变 state + build() 初始化 + 变更方法只赋 state +
/// ProviderContainer 独立可测），归属同一 application 层职责，聚合可减少
/// 碎片化，避免单一目录文件数逼近结构门禁上限。
///
/// 迁移边界（审慎，统一约定）：DrawingController 内部 viewScale/viewOffset、
/// _history/_historyPosition、_selectionDraft/_selectionTool 暂不替换（避免
/// 双状态源不一致）；本文件各 Notifier 打通"独立域 Notifier"模式，后续逐域
/// 替换（叶优先、可回滚）。

/// 视口状态（不可变值对象，应对 Riverpod == 过滤语义）。
///
/// 承载画布视图的缩放与平移；所有变更生成新实例（不可变），
/// provider 通知依赖 == 判断（官方 from_change_notifier 指南）。
class ViewportState {
  const ViewportState({required this.scale, required this.offsetX, required this.offsetY});

  /// 缩放系数（1.0 = 原始大小）。
  final double scale;

  /// 平移偏移（画布坐标，逻辑像素）。
  final double offsetX;
  final double offsetY;

  ViewportState copyWith({
    double? scale,
    double? offsetX,
    double? offsetY,
  }) => ViewportState(
    scale: scale ?? this.scale,
    offsetX: offsetX ?? this.offsetX,
    offsetY: offsetY ?? this.offsetY,
  );

  @override
  bool operator ==(Object other) =>
      other is ViewportState &&
      other.scale == scale &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY;

  @override
  int get hashCode => Object.hash(scale, offsetX, offsetY);
}

/// 视口域 Notifier（DrawingController 首个域 Notifier 化迁移示范）。
///
/// 依据 riverpod.dev from_change_notifier 官方指南 + 开源模板
/// （ssoad/ultimate-flutter）综合定案：
/// - 不可变 state（== 过滤语义，变更须生成新实例）
/// - build() 承载初始化（官方规则）
/// - 变更方法只赋 state（免 notifyListeners 样板）
/// - 独立可测（ProviderContainer 单测）
class DrawingViewportNotifier extends Notifier<ViewportState> {
  @override
  ViewportState build() => const ViewportState(scale: 1, offsetX: 0, offsetY: 0);

  /// 设置缩放（clamp 到合理范围，防无限放大缩小）。
  void setScale(double scale) {
    final clamped = scale.clamp(0.1, 8.0);
    if (clamped == state.scale) return;
    state = state.copyWith(scale: clamped);
  }

  /// 平移（累加偏移）。
  void pan(double dx, double dy) {
    state = state.copyWith(offsetX: state.offsetX + dx, offsetY: state.offsetY + dy);
  }

  /// 重置视口。
  void reset() {
    state = const ViewportState(scale: 1, offsetX: 0, offsetY: 0);
  }
}

/// 视口域 Provider（首个域 Notifier 化示范）。
final viewportProvider =
    NotifierProvider<DrawingViewportNotifier, ViewportState>(
  DrawingViewportNotifier.new,
);

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

/// 选区状态（不可变值对象，应对 Riverpod == 过滤语义）。
///
/// 承载区域选择的草稿点列与工具类型；所有变更生成新实例（不可变），
/// provider 通知依赖 == 判断（官方 from_change_notifier 指南 +
/// why_immutability 中文官方）。
class SelectionState {
  const SelectionState({required this.tool, required this.draft});

  /// 当前选择工具（none = 未在选择）。
  final SelectionTool tool;

  /// 选择草稿点列（矩形=2 点、套索=多边顶点）。
  final List<Offset> draft;

  /// 是否存在进行中的选择。
  bool get isActive => tool != SelectionTool.none && draft.isNotEmpty;

  SelectionState copyWith({SelectionTool? tool, List<Offset>? draft}) =>
      SelectionState(
        tool: tool ?? this.tool,
        draft: List.unmodifiable(draft ?? this.draft),
      );

  @override
  bool operator ==(Object other) =>
      other is SelectionState &&
      other.tool == tool &&
      _sameDraft(other.draft);

  @override
  int get hashCode => Object.hash(tool, Object.hashAll(draft));

  bool _sameDraft(List<Offset> other) {
    if (other.length != draft.length) return false;
    for (var i = 0; i < draft.length; i++) {
      if (draft[i] != other[i]) return false;
    }
    return true;
  }
}

/// 选区域 Notifier（DrawingController 第二个域 Notifier 化示范）。
///
/// 依据 riverpod.dev select/from_change_notifier 官方 + 掘金 Riverpod
/// 实战指南（2026-05）综合定案：
/// - 不可变 state（== 过滤语义，变更须生成新实例）
/// - build() 承载初始化（官方规则）
/// - 变更方法只赋 state（免 notifyListeners 样板）
/// - 独立可测（ProviderContainer 单测）
class DrawingSelectionNotifier extends Notifier<SelectionState> {
  @override
  SelectionState build() =>
      const SelectionState(tool: SelectionTool.none, draft: []);

  /// 开始选择（矩形/套索入口）。
  void beginSelection(SelectionTool tool, Offset canvasPoint) {
    state = SelectionState(tool: tool, draft: [canvasPoint]);
  }

  /// 扩展选择草稿（矩形第二点 / 套索追加顶点）。
  void extendSelection(Offset canvasPoint) {
    if (state.tool == SelectionTool.none) return;
    final draft = List<Offset>.of(state.draft);
    if (state.tool == SelectionTool.rect) {
      if (draft.isEmpty) draft.add(canvasPoint);
      draft
        ..removeRange(1, draft.length)
        ..add(canvasPoint);
    } else {
      draft.add(canvasPoint);
    }
    state = state.copyWith(draft: draft);
  }

  /// 结束选择（保留结果，进入已选区状态）。
  void endSelection() {
    if (state.tool == SelectionTool.none) return;
    state = state.copyWith();
  }

  /// 清除选择。
  void clearSelection() {
    state = const SelectionState(tool: SelectionTool.none, draft: []);
  }
}

/// 选区域 Provider（第二个域 Notifier 化示范）。
final selectionProvider =
    NotifierProvider<DrawingSelectionNotifier, SelectionState>(
  DrawingSelectionNotifier.new,
);
