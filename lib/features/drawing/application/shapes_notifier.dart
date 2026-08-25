import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 形状元素选中状态（不可变值对象，应对 Riverpod == 过滤语义）。
///
/// 承载 objects 域（DocumentShape 子域）的可见状态：当前选中形状
/// 集合 + 活动形状 id。元素对象本身（PageShapeItem）不放进状态
/// （含渲染引用），仅暴露 id 集合供 UI 判定"是否选中"。
class ShapesState {
  const ShapesState({required this.selectedIds, this.activeId});

  /// 当前选中的形状 id 集合（不可变）。
  final Set<String> selectedIds;

  /// 活动形状 id（单点选中/变换目标）；null = 无活动形状。
  final String? activeId;

  /// 是否选中了任何形状。
  bool get hasSelection => selectedIds.isNotEmpty;

  static const ShapesState empty =
      ShapesState(selectedIds: {});

  ShapesState copyWith({Set<String>? selectedIds, String? activeId}) =>
      ShapesState(
        selectedIds: Set.unmodifiable(selectedIds ?? this.selectedIds),
        activeId: activeId,
      );

  @override
  bool operator ==(Object other) =>
      other is ShapesState &&
      other.selectedIds.length == selectedIds.length &&
      other.selectedIds.containsAll(selectedIds) &&
      other.activeId == activeId;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(selectedIds),
    activeId,
  );
}

/// 形状元素域 Notifier（objects 子域 Notifier 化示范）。
///
/// 依据 riverpod.dev from_change_notifier/family 官方 + 掘金 Riverpod
/// 实战指南（2026-05）综合定案（"状态逻辑独立/更新不相关时拆分"）：
/// - 不可变 state（== 过滤语义，变更须生成新实例）
/// - build() 承载初始化（官方规则）
/// - 变更方法只赋 state（免 notifyListeners 样板）
/// - 独立可测（ProviderContainer 单测）
///
/// 迁移边界（审慎）：DrawingController 内部 _selectedDocumentShapeIds/
/// _selectedDocumentShapeId 暂不替换（避免双状态源不一致），本 Notifier
/// 暴露"形状选中可见状态"，UI 面板可经 ref.watch 订阅。
class DrawingShapesNotifier extends Notifier<ShapesState> {
  @override
  ShapesState build() => ShapesState.empty;

  /// 设置选中集合与活动 id（由 controller 选中操作驱动）。
  void select({required Set<String> ids, String? activeId}) {
    final next = ShapesState(selectedIds: ids, activeId: activeId);
    if (next == state) return; // == 过滤，避免无效重建
    state = next;
  }

  /// 追加单个形状到选中集合。
  void addToSelection(String id) {
    final ids = {...state.selectedIds, id};
    state = state.copyWith(
      selectedIds: ids,
      activeId: id, // 新选中的成为活动形状
    );
  }

  /// 清除选中。
  void clearSelection() {
    state = ShapesState.empty;
  }
}

/// 形状元素域 Provider（objects 子域 Notifier 化示范）。
final shapesProvider =
    NotifierProvider<DrawingShapesNotifier, ShapesState>(
  DrawingShapesNotifier.new,
);
