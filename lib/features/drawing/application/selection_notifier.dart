import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/selection.dart';

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
///
/// 迁移边界（审慎）：DrawingController 内部 _selectionDraft/
/// _selectionTool 暂不替换（避免双状态源不一致），本 Notifier 打通
/// "selection 域 Notifier"模式，后续逐域替换（叶优先、可回滚）。
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
