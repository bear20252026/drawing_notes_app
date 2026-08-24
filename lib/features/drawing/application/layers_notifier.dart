import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 图层状态（不可变值对象，应对 Riverpod == 过滤语义）。
///
/// 承载当前图层索引和图层可见性；所有变更生成新实例（不可变），
/// provider 通知依赖 == 判断。
class LayersState {
  const LayersState({
    this.currentLayerIndex = 0,
    this.layerCount = 1,
    this.layerVisibility = const [true],
  });

  /// 当前活跃图层索引。
  final int currentLayerIndex;

  /// 图层总数。
  final int layerCount;

  /// 各图层可见性列表（索引对应图层索引）。
  final List<bool> layerVisibility;

  /// 当前图层是否可见。
  bool get isCurrentLayerVisible =>
      currentLayerIndex < layerVisibility.length &&
      layerVisibility[currentLayerIndex];

  LayersState copyWith({
    int? currentLayerIndex,
    int? layerCount,
    List<bool>? layerVisibility,
  }) => LayersState(
    currentLayerIndex: currentLayerIndex ?? this.currentLayerIndex,
    layerCount: layerCount ?? this.layerCount,
    layerVisibility: layerVisibility ?? this.layerVisibility,
  );

  @override
  bool operator ==(Object other) =>
      other is LayersState &&
      other.currentLayerIndex == currentLayerIndex &&
      other.layerCount == layerCount &&
      _sameVisibility(other.layerVisibility);

  @override
  int get hashCode => Object.hash(currentLayerIndex, layerCount, Object.hashAll(layerVisibility));

  bool _sameVisibility(List<bool> other) {
    if (other.length != layerVisibility.length) return false;
    for (var i = 0; i < layerVisibility.length; i++) {
      if (other[i] != layerVisibility[i]) return false;
    }
    return true;
  }
}

/// 图层域 Notifier（DrawingController 域 Notifier 化）。
///
/// 迁移边界：DrawingController 内部 _currentLayerIndex 暂不替换
/// （避免双状态源不一致）；本 Notifier 暴露"可见图层状态"，
/// UI 图层面板可经 ref.watch 订阅；后续逐域替换。
class LayersNotifier extends Notifier<LayersState> {
  @override
  LayersState build() => const LayersState();

  /// 切换当前图层。
  void setCurrentLayer(int index) {
    if (index >= 0 && index < state.layerCount) {
      state = state.copyWith(currentLayerIndex: index);
    }
  }

  /// 切换图层可见性。
  void toggleVisibility(int index) {
    if (index >= 0 && index < state.layerVisibility.length) {
      final newVisibility = List<bool>.from(state.layerVisibility);
      newVisibility[index] = !newVisibility[index];
      state = state.copyWith(layerVisibility: newVisibility);
    }
  }

  /// 添加新图层。
  void addLayer() {
    final newCount = state.layerCount + 1;
    final newVisibility = [...state.layerVisibility, true];
    state = state.copyWith(
      layerCount: newCount,
      layerVisibility: newVisibility,
    );
  }

  /// 删除图层（至少保留一个图层）。
  void removeLayer(int index) {
    if (state.layerCount <= 1) return;
    if (index < 0 || index >= state.layerCount) return;

    final newCount = state.layerCount - 1;
    final newVisibility = List<bool>.from(state.layerVisibility)..removeAt(index);
    final newIndex = state.currentLayerIndex >= newCount
        ? newCount - 1
        : state.currentLayerIndex;
    state = state.copyWith(
      currentLayerIndex: newIndex,
      layerCount: newCount,
      layerVisibility: newVisibility,
    );
  }

  /// 同步图层状态（从控制器同步）。
  void syncFromController({
    required int currentLayerIndex,
    required int layerCount,
  }) {
    var visibility = state.layerVisibility;
    while (visibility.length < layerCount) {
      visibility = [...visibility, true];
    }
    state = state.copyWith(
      currentLayerIndex: currentLayerIndex,
      layerCount: layerCount,
      layerVisibility: visibility,
    );
  }
}

/// 图层状态 Provider。
final layersProvider = NotifierProvider<LayersNotifier, LayersState>(
  LayersNotifier.new,
);
