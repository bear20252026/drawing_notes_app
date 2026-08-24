// editor_core——BoundText 文本绑定容器（Excalidraw 3.8 借鉴——2026-08-21）。
//
// Excalidraw 3.8 Bound Text and ShapeContainer System 本地化——
// 文本绑定到形状容器（自动跟随/裁剪/自适应）。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - 文本可以"绑定"到形状（rectangle/ellipse/diamond）
// - 绑定后文本自动在容器内换行/裁剪
// - 移动容器时文本自动跟随
// - 容器缩放时文本自适应
library;

/// 文本绑定关系（Excalidraw Bound Text 本地化——不可变）。
///
/// 描述文本和容器之间的绑定关系：
/// - 文本元素（textId）绑定到容器元素（containerId）
/// - 文本在容器内自动换行/裁剪
/// - 容器移动/缩放时文本跟随
class TextBinding {
  const TextBinding({
    required this.textId,
    required this.containerId,
    this.padding = 8.0,
    this.verticalAlign = VerticalAlign.top,
    this.horizontalAlign = HorizontalAlign.left,
    this.autoResize = true,
  });

  /// 绑定的文本元素 ID。
  final String textId;

  /// 绑定的容器元素 ID。
  final String containerId;

  /// 内边距（像素）。
  final double padding;

  /// 垂直对齐。
  final VerticalAlign verticalAlign;

  /// 水平对齐。
  final HorizontalAlign horizontalAlign;

  /// 是否自动调整大小（容器缩放时文本自适应）。
  final bool autoResize;

  TextBinding copyWith({
    double? padding,
    VerticalAlign? verticalAlign,
    HorizontalAlign? horizontalAlign,
    bool? autoResize,
  }) {
    return TextBinding(
      textId: textId,
      containerId: containerId,
      padding: padding ?? this.padding,
      verticalAlign: verticalAlign ?? this.verticalAlign,
      horizontalAlign: horizontalAlign ?? this.horizontalAlign,
      autoResize: autoResize ?? this.autoResize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextBinding && textId == other.textId && containerId == other.containerId;

  @override
  int get hashCode => Object.hash(textId, containerId);
}

/// 垂直对齐（Excalidraw vertical align 借鉴）。
enum VerticalAlign {
  top,
  middle,
  bottom,
}

/// 水平对齐（Excalidraw horizontal align 借鉴）。
enum HorizontalAlign {
  left,
  center,
  right,
}

/// 容器元素类型（Excalidraw container types 借鉴）。
enum ContainerType {
  rectangle,
  ellipse,
  diamond,
  frame,
}

/// 容器元素（Excalidraw container 本地化——不可变）。
///
/// 注意：避免与 Flutter ShapeContainer Widget 冲突——重命名为 ShapeContainer。
class ShapeContainer {
  const ShapeContainer({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.padding = 8.0,
    this.clipText = true,
    this.autoResize = true,
    this.textIds = const [],
  });

  final String id;
  final ContainerType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double padding;

  /// 是否裁剪文本（文本在容器内裁剪）。
  final bool clipText;

  /// 是否自动调整大小。
  final bool autoResize;

  /// 绑定的文本元素 ID 列表。
  final List<String> textIds;

  /// 可用区域（扣除内边距）。
  ({double x, double y, double width, double height}) get contentArea => (
    x: x + padding,
    y: y + padding,
    width: width - padding * 2,
    height: height - padding * 2,
  );

  /// 边界。
  ({double left, double top, double right, double bottom}) get bounds =>
      (left: x, top: y, right: x + width, bottom: y + height);

  /// 绑定的文本数量。
  int get textCount => textIds.length;

  /// 是否有绑定文本。
  bool get hasText => textIds.isNotEmpty;

  /// 添加文本绑定。
  ShapeContainer addText(String textId) {
    if (textIds.contains(textId)) return this;
    return copyWith(textIds: [...textIds, textId]);
  }

  /// 移除文本绑定。
  ShapeContainer removeText(String textId) {
    return copyWith(textIds: textIds.where((id) => id != textId).toList());
  }

  /// 移动容器（文本跟随——通过返回移动偏移量实现）。
  ShapeContainer moveTo(double newX, double newY) {
    return copyWith(x: newX, y: newY);
  }

  /// 缩放容器。
  ShapeContainer resize(double newWidth, double newHeight) {
    return copyWith(
      width: newWidth.clamp(padding * 2, 10000),
      height: newHeight.clamp(padding * 2, 10000),
    );
  }

  /// 计算文本在容器内的位置（根据对齐方式）。
  ({double x, double y}) getTextPosition(double textWidth, double textHeight,
      {VerticalAlign vAlign = VerticalAlign.top, HorizontalAlign hAlign = HorizontalAlign.left}) {
    final area = contentArea;
    double tx, ty;
    switch (hAlign) {
      case HorizontalAlign.left:
        tx = area.x;
      case HorizontalAlign.center:
        tx = area.x + (area.width - textWidth) / 2;
      case HorizontalAlign.right:
        tx = area.x + area.width - textWidth;
    }
    switch (vAlign) {
      case VerticalAlign.top:
        ty = area.y;
      case VerticalAlign.middle:
        ty = area.y + (area.height - textHeight) / 2;
      case VerticalAlign.bottom:
        ty = area.y + area.height - textHeight;
    }
    return (x: tx, y: ty);
  }

  ShapeContainer copyWith({
    ContainerType? type,
    double? x,
    double? y,
    double? width,
    double? height,
    double? padding,
    bool? clipText,
    bool? autoResize,
    List<String>? textIds,
  }) {
    return ShapeContainer(
      id: id,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      padding: padding ?? this.padding,
      clipText: clipText ?? this.clipText,
      autoResize: autoResize ?? this.autoResize,
      textIds: textIds ?? this.textIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ShapeContainer && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 文本绑定管理器（Excalidraw Bound Text 系统本地化——积木式纯 Dart）。
///
/// 管理文本和容器之间的绑定关系。
class TextBindingManager {
  const TextBindingManager({
    this.bindings = const [],
    this.containers = const [],
  });

  final List<TextBinding> bindings;
  final List<ShapeContainer> containers;

  /// 添加绑定。
  TextBindingManager addBinding(TextBinding binding) {
    return TextBindingManager(
      bindings: [...bindings, binding],
      containers: containers.map((c) => c.id == binding.containerId ? c.addText(binding.textId) : c).toList(),
    );
  }

  /// 移除绑定。
  TextBindingManager removeBinding(String textId) {
    final binding = bindings.where((b) => b.textId == textId).firstOrNull;
    if (binding == null) return this;
    return TextBindingManager(
      bindings: bindings.where((b) => b.textId != textId).toList(),
      containers: containers.map((c) => c.id == binding.containerId ? c.removeText(textId) : c).toList(),
    );
  }

  /// 添加容器。
  TextBindingManager addContainer(ShapeContainer container) {
    return TextBindingManager(bindings: bindings, containers: [...containers, container]);
  }

  /// 移除容器（同时移除所有绑定到该容器的文本）。
  TextBindingManager removeContainer(String containerId) {
    return TextBindingManager(
      bindings: bindings.where((b) => b.containerId != containerId).toList(),
      containers: containers.where((c) => c.id != containerId).toList(),
    );
  }

  /// 获取文本绑定的容器。
  ShapeContainer? getContainerForText(String textId) {
    final binding = bindings.where((b) => b.textId == textId).firstOrNull;
    if (binding == null) return null;
    return containers.where((c) => c.id == binding.containerId).firstOrNull;
  }

  /// 获取容器绑定的所有文本。
  List<String> getTextsForContainer(String containerId) {
    return bindings.where((b) => b.containerId == containerId).map((b) => b.textId).toList();
  }

  /// 获取绑定关系。
  TextBinding? getBinding(String textId) {
    return bindings.where((b) => b.textId == textId).firstOrNull;
  }

  int get bindingCount => bindings.length;
  int get containerCount => containers.length;

  TextBindingManager copyWith({List<TextBinding>? bindings, List<ShapeContainer>? containers}) {
    return TextBindingManager(
      bindings: bindings ?? this.bindings,
      containers: containers ?? this.containers,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextBindingManager && bindingCount == other.bindingCount;

  @override
  int get hashCode => bindingCount.hashCode;
}
