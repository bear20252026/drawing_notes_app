import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 图片元素选中状态（不可变值对象，应对 Riverpod == 过滤语义）。
///
/// 承载 objects 域（DocumentImage 子域）的可见状态：当前选中图片
/// 集合 + 活动图片 id。元素对象本身（DocumentImageItem）不放进状态
/// （含渲染引用），仅暴露 id 集合供 UI 判定"是否选中"。
class ImagesState {
  const ImagesState({required this.selectedIds, this.activeId});

  /// 当前选中的图片 id 集合（不可变）。
  final Set<String> selectedIds;

  /// 活动图片 id（单点选中/变换目标）；null = 无活动图片。
  final String? activeId;

  /// 是否选中了任何图片。
  bool get hasSelection => selectedIds.isNotEmpty;

  static const ImagesState empty =
      ImagesState(selectedIds: {});

  ImagesState copyWith({Set<String>? selectedIds, String? activeId}) =>
      ImagesState(
        selectedIds: Set.unmodifiable(selectedIds ?? this.selectedIds),
        activeId: activeId,
      );

  // 深度 == 比较（集合成员），依据 riverpod.dev select 官方 +
  // 掘金源码评析（select 用 != 比较，新建 List 每次都判"变了"）：
  // 内容相同必须判等，否则 select 触发无效重建。
  @override
  bool operator ==(Object other) =>
      other is ImagesState &&
      other.selectedIds.length == selectedIds.length &&
      other.selectedIds.containsAll(selectedIds) &&
      other.activeId == activeId;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(selectedIds),
    activeId,
  );
}

/// 图片元素域 Notifier（objects 子域 Notifier 化示范）。
///
/// 依据 riverpod.dev providers/select/refs 官方 + 掘金 Riverpod 实战
/// 指南/源码评析（中英双语交叉验证）综合定案：
/// - 不可变 state（== 过滤语义，变更须生成新实例）
/// - build() 承载初始化（官方规则）
/// - 变更方法只赋 state（免 notifyListeners 样板）
/// - 独立可测（ProviderContainer 单测）
///
/// 迁移边界（审慎）：DrawingController 内部 _selectedDocumentImageIds/
/// _selectedDocumentImageId 暂不替换（避免双状态源不一致），本 Notifier
/// 暴露"图片选中可见状态"，UI 面板可经 ref.watch 订阅。
class DrawingImagesNotifier extends Notifier<ImagesState> {
  @override
  ImagesState build() => ImagesState.empty;

  /// 设置选中集合与活动 id（由 controller 选中操作驱动）。
  void select({required Set<String> ids, String? activeId}) {
    final next = ImagesState(selectedIds: ids, activeId: activeId);
    if (next == state) return; // == 过滤，避免无效重建
    state = next;
  }

  /// 追加单个图片到选中集合。
  void addToSelection(String id) {
    final ids = {...state.selectedIds, id};
    state = state.copyWith(
      selectedIds: ids,
      activeId: id, // 新选中的成为活动图片
    );
  }

  /// 清除选中。
  void clearSelection() {
    state = ImagesState.empty;
  }
}

/// 图片元素域 Provider（objects 子域 Notifier 化示范）。
final imagesProvider =
    NotifierProvider<DrawingImagesNotifier, ImagesState>(
  DrawingImagesNotifier.new,
);
