import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 图片元素选中状态（不可变值对象，应对 Riverpod == 过滤语义）。
///
/// 承载 objects 域（DocumentImage 子域）的可见状态：当前选中图片集合与
/// 活动图片 id。元素对象本身不放进状态，仅暴露 id 集合供 UI 判定是否选中。
class ImagesState {
  const ImagesState({required this.selectedIds, this.activeId});

  /// 当前选中的图片 id 集合（不可变）。
  final Set<String> selectedIds;

  /// 活动图片 id（单点选中/变换目标）；null = 无活动图片。
  final String? activeId;

  bool get hasSelection => selectedIds.isNotEmpty;

  static const ImagesState empty = ImagesState(selectedIds: {}, activeId: null);

  ImagesState copyWith({Set<String>? selectedIds, String? activeId}) =>
      ImagesState(
        selectedIds: Set.unmodifiable(selectedIds ?? this.selectedIds),
        activeId: activeId,
      );

  @override
  bool operator ==(Object other) =>
      other is ImagesState &&
      other.selectedIds.length == selectedIds.length &&
      other.selectedIds.containsAll(selectedIds) &&
      other.activeId == activeId;

  @override
  int get hashCode => Object.hash(Object.hashAll(selectedIds), activeId);
}

/// 图片元素域的可见选择状态。
///
/// 运行时图片选择仍由 `DocumentObjectEditingSession` 持有。本 notifier 只向
/// Riverpod 消费方暴露不可变的可见状态，避免形成第二个可写运行时状态源。
class DrawingImagesNotifier extends Notifier<ImagesState> {
  @override
  ImagesState build() => ImagesState.empty;

  void select({required Set<String> ids, String? activeId}) {
    final next = ImagesState(selectedIds: ids, activeId: activeId);
    if (next == state) return;
    state = next;
  }

  void addToSelection(String id) {
    final ids = {...state.selectedIds, id};
    state = state.copyWith(selectedIds: ids, activeId: id);
  }

  void clearSelection() => state = ImagesState.empty;
}

final imagesProvider = NotifierProvider<DrawingImagesNotifier, ImagesState>(
  DrawingImagesNotifier.new,
);

/// 形状元素选中状态（不可变值对象，应对 Riverpod == 过滤语义）。
///
/// 承载 objects 域（DocumentShape 子域）的可见状态：当前选中形状集合与
/// 活动形状 id。元素对象本身不放进状态，仅暴露 id 集合供 UI 判定是否选中。
class ShapesState {
  const ShapesState({required this.selectedIds, this.activeId});

  /// 当前选中的形状 id 集合（不可变）。
  final Set<String> selectedIds;

  /// 活动形状 id（单点选中/变换目标）；null = 无活动形状。
  final String? activeId;

  bool get hasSelection => selectedIds.isNotEmpty;

  static const ShapesState empty = ShapesState(selectedIds: {}, activeId: null);

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
  int get hashCode => Object.hash(Object.hashAll(selectedIds), activeId);
}

/// 形状元素域的可见选择状态。
///
/// 运行时形状选择仍由 `DocumentObjectEditingSession` 持有。本 notifier 只向
/// Riverpod 消费方暴露不可变的可见状态，避免形成第二个可写运行时状态源。
class DrawingShapesNotifier extends Notifier<ShapesState> {
  @override
  ShapesState build() => ShapesState.empty;

  void select({required Set<String> ids, String? activeId}) {
    final next = ShapesState(selectedIds: ids, activeId: activeId);
    if (next == state) return;
    state = next;
  }

  void addToSelection(String id) {
    final ids = {...state.selectedIds, id};
    state = state.copyWith(selectedIds: ids, activeId: id);
  }

  void clearSelection() => state = ShapesState.empty;
}

final shapesProvider = NotifierProvider<DrawingShapesNotifier, ShapesState>(
  DrawingShapesNotifier.new,
);
