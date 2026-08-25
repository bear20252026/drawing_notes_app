// editor_core——ArrowBinding 箭头绑定（Excalidraw 借鉴——2026-08-21）。
//
// Excalidraw Arrow Binding 本地化——箭头端点绑定到形状（连接形状的箭头）。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - Arrow 的 start/end binding 各绑定到一个 shape（elementId）
// - focus: -1~1（箭头端点在形状上的位置——0=中心，-1=左，1=右）
// - gap: 箭头与形状边缘的间距
library;

/// 端点绑定（箭头端点绑定到形状——Excalidraw binding 本地化——不可变）。
class EndpointBinding {
  const EndpointBinding({
    required this.elementId,
    this.focus = 0.0,
    this.gap = 4.0,
  });

  /// 绑定的目标形状 ID。
  final String elementId;

  /// 焦点（-1~1——箭头端点在形状上的位置。
  /// 0=中心，-1=左边缘，1=右边缘）。
  final double focus;

  /// 间距（箭头端点与形状边缘的间距——像素）。
  final double gap;

  EndpointBinding copyWith({String? elementId, double? focus, double? gap}) {
    return EndpointBinding(
      elementId: elementId ?? this.elementId,
      focus: focus ?? this.focus,
      gap: gap ?? this.gap,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EndpointBinding && elementId == other.elementId && focus == other.focus;

  @override
  int get hashCode => Object.hash(elementId, focus);
}

/// 箭头绑定（Excalidraw Arrow Binding 本地化——不可变）。
///
/// 箭头可以绑定到 0 或 1 或 2 个形状（起点/终点）。
class ArrowBinding {
  const ArrowBinding({
    this.startBinding,
    this.endBinding,
  });

  /// 起点绑定（绑定到形状——可选）。
  final EndpointBinding? startBinding;

  /// 终点绑定（绑定到形状——可选）。
  final EndpointBinding? endBinding;

  /// 是否至少有一端绑定。
  bool get isBound => startBinding != null || endBinding != null;

  /// 是否两端都绑定。
  bool get isFullyBound => startBinding != null && endBinding != null;

  ArrowBinding copyWith({EndpointBinding? startBinding, EndpointBinding? endBinding}) {
    return ArrowBinding(
      startBinding: startBinding ?? this.startBinding,
      endBinding: endBinding ?? this.endBinding,
    );
  }

  /// 绑定起点到形状。
  ArrowBinding bindStart(String elementId, {double focus = 0.0, double gap = 4.0}) {
    return copyWith(startBinding: EndpointBinding(elementId: elementId, focus: focus, gap: gap));
  }

  /// 绑定终点到形状。
  ArrowBinding bindEnd(String elementId, {double focus = 0.0, double gap = 4.0}) {
    return copyWith(endBinding: EndpointBinding(elementId: elementId, focus: focus, gap: gap));
  }

  /// 解绑起点（直接构造——避免 copyWith 的 ?? 问题）。
  ArrowBinding unbindStart() => ArrowBinding(endBinding: endBinding);

  /// 解绑终点（直接构造——避免 copyWith 的 ?? 问题）。
  ArrowBinding unbindEnd() => ArrowBinding(startBinding: startBinding);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowBinding && startBinding == other.startBinding && endBinding == other.endBinding;

  @override
  int get hashCode => Object.hash(startBinding, endBinding);
}
