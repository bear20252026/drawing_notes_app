import 'package:flutter_riverpod/flutter_riverpod.dart';

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
///
/// 迁移边界（审慎）：DrawingController 内部 viewScale/viewOffset 暂不
/// 替换（避免双状态源不一致）；本 Notifier 打通"独立域 Notifier"模式，
/// 后续逐域替换（叶优先、可回滚）。
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
